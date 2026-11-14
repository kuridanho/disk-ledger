import AppKit
import LedgerCore
import Observation

/// 一覧の一行。
struct ItemRow: Identifiable, Equatable {
    var id: Int
    var name: String
    var size: UInt64
    var share: Double
    var flags: TreeStorage.Flags
    var modified: UInt32

    var isDirectory: Bool { flags.contains(.directory) }

    /// 容量の代わりに出す状態。読めなかったものなど、容量が分からない項目に使う。
    var status: String? {
        if flags.contains(.needsPermission) { return "許可が必要" }
        if flags.contains(.unreadable) { return "読めません" }
        if flags.contains(.mountPoint) { return "別のボリューム" }
        if flags.contains(.dataless) { return "iCloud のみ" }
        if flags.contains(.hardLinkDuplicate) { return "リンク" }
        return nil
    }
}

@MainActor @Observable
final class LedgerModel {
    enum Phase { case needsPermission, idle, scanning, done }

    let launch: LaunchOptions
    private(set) var phase: Phase = .idle
    private(set) var hasFullDiskAccess: Bool
    private(set) var progress = DiskScanner.Progress()
    private(set) var volume: VolumeInfo?

    private(set) var focus = 0
    var selection: Int?
    var hovered: Int?

    private(set) var arcs: [SunburstArc] = []
    private(set) var rows: [ItemRow] = []
    private(set) var breadcrumb: [(node: Int, name: String)] = []
    private(set) var focusSize: UInt64 = 0
    private(set) var unreadableCount = 0

    private var scanner: DiskScanner?
    private var ticker: Task<Void, Never>?

    init(launch: LaunchOptions) {
        self.launch = launch
        hasFullDiskAccess = launch.forcePermissionScreen ? false : FullDiskAccess.isGranted
        phase = needsPermission ? .needsPermission : .idle
    }

    /// 確認用に場所を指定したときは、許可を求めない。
    private var needsPermission: Bool { launch.scanRoot == nil && !hasFullDiskAccess }

    var canScan: Bool { phase != .scanning && !needsPermission }

    var tree: Tree? { scanner?.tree }

    func refreshPermission() {
        guard !launch.forcePermissionScreen else { return }
        let granted = FullDiskAccess.isGranted
        guard granted != hasFullDiskAccess else { return }
        hasFullDiskAccess = granted
        if phase == .needsPermission, !needsPermission {
            phase = .idle
            startScan()
        }
    }

    func startIfPossible() {
        if launch.forcePermissionScreen, let path = launch.snapshotPath {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                Snapshot.write(to: path)
            }
            return
        }
        if canScan { startScan() }
    }

    func startScan() {
        guard canScan else { return }
        ticker?.cancel()
        let options = launch.scanRoot.map { DiskScanner.Options(rootPath: $0, includeVolumeSummary: false) }
            ?? DiskScanner.Options()
        let scanner = DiskScanner(options: options)
        self.scanner = scanner
        focus = 0
        selection = nil
        hovered = nil
        phase = .scanning
        DispatchQueue.global(qos: .userInitiated).async { scanner.run() }

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.scanner === scanner else { return }
                self.progress = scanner.progress()
                self.volume = scanner.volume
                self.rebuild()
                if self.progress.finished {
                    self.finish()
                    return
                }
            }
        }
    }

    private func finish() {
        phase = .done
        if let name = launch.focusName, let tree {
            let match = tree.read { t in t.children(0).first { t.name($0) == name } }
            if let match { focus(on: match) }
        }
        if let path = launch.snapshotPath {
            Task {
                try? await Task.sleep(for: .seconds(1))
                Snapshot.write(to: path)
            }
        }
    }

    /// 図と一覧を今の木から作り直す。走査中は木が伸び続けるので定期的に呼ぶ。
    func rebuild() {
        guard let tree else { return }
        tree.read { t in
            guard t.count > focus else { return }
            focusSize = t.size[focus]
            arcs = SunburstLayout.arcs(in: t, center: focus)
            let total = Double(max(focusSize, 1))
            rows = t.sortedChildren(focus).map { i in
                ItemRow(id: i, name: t.name(i), size: t.size[i], share: Double(t.size[i]) / total,
                        flags: t.flags[i], modified: t.modified[i])
            }
            breadcrumb = t.ancestry(focus).map { ($0, t.name($0)) }
        }
        unreadableCount = progress.unreadable
    }

    func focus(on node: Int) {
        guard let tree, tree.read({ $0.isDirectory(node) && $0.childCount[node] > 0 }) else { return }
        focus = node
        selection = nil
        hovered = nil
        rebuild()
    }

    func focusParent() {
        guard focus != 0, let tree else { return }
        let parent = tree.read { Int($0.parent[focus]) }
        let previous = focus
        focus(on: parent)
        selection = previous
    }

    /// 図や一覧で項目が選ばれたとき。フォルダなら中に入る。
    func open(_ node: Int) {
        guard let tree else { return }
        if tree.read({ $0.isDirectory(node) && $0.childCount[node] > 0 }) {
            focus(on: node)
        } else {
            selection = node
        }
    }

    func name(of node: Int) -> String { tree?.read { $0.name(node) } ?? "" }

    func size(of node: Int) -> UInt64 { tree?.read { $0.size[node] } ?? 0 }

    /// Finder で開けるパス。データボリュームの中のパスは、/Users のような普段の形に直す。
    func displayPath(of node: Int) -> String? {
        guard let real = tree?.read({ $0.path(node) }) else { return nil }
        let prefix = VolumeInfo.dataVolumePath
        if real.hasPrefix(prefix + "/") {
            let short = String(real.dropFirst(prefix.count))
            if FileManager.default.fileExists(atPath: short) { return short }
        }
        return real
    }

    func revealInFinder(_ node: Int) {
        guard let path = displayPath(of: node) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyPath(_ node: Int) {
        guard let path = displayPath(of: node) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    /// フルディスクアクセスは許可したあとに開き直さないと効かないことがあるので、自分を開き直す。
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
