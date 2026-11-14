import AppKit
import LedgerCore
import Observation

/// 一覧の一行。
struct ItemRow: Identifiable, Equatable {
    var id: Int
    var name: String
    /// どのアプリのものか、またはどこにあるか。
    var detail: String?
    var size: UInt64
    var share: Double
    var flags: TreeStorage.Flags
    var modified: UInt32

    var isDirectory: Bool { flags.contains(.directory) }

    /// 容量の代わりに出す状態。読めなかったものなど、容量が分からない項目に使う。
    var status: String? {
        if flags.contains(.needsPermission) { return "要許可" }
        if flags.contains(.unreadable) { return "読取不可" }
        if flags.contains(.mountPoint) { return "別ボリューム" }
        if flags.contains(.dataless) { return "未ダウンロード" }
        if flags.contains(.hardLinkDuplicate) { return "ハードリンク" }
        return nil
    }
}

/// 左の一覧で選ぶもの。
enum SidebarItem: Hashable {
    case category(String)
    case allFolders
}

@MainActor @Observable
final class LedgerModel {
    enum Phase { case needsPermission, idle, scanning, done }

    let launch: LaunchOptions
    private(set) var phase: Phase = .idle
    private(set) var hasFullDiskAccess: Bool
    private(set) var progress = DiskScanner.Progress()
    private(set) var volume: VolumeInfo?
    private(set) var classification: Classification?

    var sidebarSelection: SidebarItem? {
        didSet { if oldValue != sidebarSelection { path = []; selection = nil; rebuild() } }
    }
    /// 種類の中で開いていったフォルダ。空なら種類の一覧そのもの。
    private(set) var path: [Int] = []
    var selection: Int?

    private(set) var rows: [ItemRow] = []
    private(set) var listSize: UInt64 = 0

    private var scanner: DiskScanner?
    private var ticker: Task<Void, Never>?

    init(launch: LaunchOptions) {
        self.launch = launch
        hasFullDiskAccess = launch.forcePermissionScreen ? false : FullDiskAccess.isGranted
        phase = needsPermission ? .needsPermission : .idle
    }

    /// 確認用に場所を指定したときは、許可を求めない。
    private var needsPermission: Bool { launch.scanRoot == nil && launch.loadPath == nil && !hasFullDiskAccess }

    var canScan: Bool { phase != .scanning && !needsPermission }

    var tree: Tree? { scanner?.tree }

    var selectedGroup: Classification.Group? {
        guard case .category(let id) = sidebarSelection else { return nil }
        return classification?.groups.first { $0.id == id }
    }

    var title: String {
        switch sidebarSelection {
        case .category: selectedGroup?.rule.name ?? ""
        case .allFolders: "フォルダ階層"
        case nil: ""
        }
    }

    /// 見出しの下に出す道筋。
    var breadcrumb: [(index: Int, name: String)] {
        guard let tree else { return [] }
        return tree.read { t in
            path.enumerated().map { (offset, node) in
                (offset, offset == 0 && sidebarSelection != .allFolders ? shortPath(t, node) : t.name(node))
            }
        }
    }

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
        // 確認用の場所指定では、許可を求める窓を決して出さないよう、該当する場所を読まない。
        let options = launch.scanRoot.map { DiskScanner.Options(rootPath: $0, includeVolumeSummary: false, skipPromptingPaths: true) }
            ?? DiskScanner.Options()
        let scanner: DiskScanner
        if let file = launch.loadPath, let loaded = try? DiskScanner(archive: URL(fileURLWithPath: file)) {
            scanner = loaded
        } else {
            scanner = DiskScanner(options: options)
        }
        self.scanner = scanner
        classification = nil
        rows = []
        path = []
        selection = nil
        phase = .scanning
        if !scanner.progress().finished {
            DispatchQueue.global(qos: .userInitiated).async { scanner.run() }
        }

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, self.scanner === scanner else { return }
                self.progress = scanner.progress()
                self.volume = scanner.volume
                if self.progress.finished {
                    await self.finish(scanner)
                    return
                }
            }
        }
    }

    private func finish(_ scanner: DiskScanner) async {
        let tree = scanner.tree
        let purgeable = scanner.volume?.purgeable ?? 0
        let result = await Task.detached(priority: .userInitiated) {
            let apps = InstalledApps.current()
            return tree.read { Categories.classify($0, purgeable: purgeable, apps: apps) }
        }.value
        guard self.scanner === scanner else { return }
        classification = result
        phase = .done
        if sidebarSelection == nil || selectedGroup == nil && sidebarSelection != .allFolders {
            sidebarSelection = result.groups.first.map { .category($0.id) } ?? .allFolders
        } else {
            rebuild()
        }
        if let name = launch.focusName {
            if let group = result.groups.first(where: { $0.id == name }) {
                sidebarSelection = .category(group.id)
            } else if let match = tree.read({ t in rows.first { t.name($0.id) == name }?.id }) {
                open(match)
            }
        }
        if let path = launch.dumpPath {
            let volume = scanner.volume
            let error: String? = tree.read { t in
                do { try TreeArchive.write(t, volume: volume, to: URL(fileURLWithPath: path)); return nil } catch { return "\(error)" }
            }
            if let error { FileHandle.standardError.write(Data((error + "\n").utf8)) }
            NSApp.terminate(nil)
            return
        }
        if let path = launch.snapshotPath {
            Task {
                try? await Task.sleep(for: .seconds(1))
                Snapshot.write(to: path)
            }
        }
    }

    /// 一覧を今の選択から作り直す。
    func rebuild() {
        guard let tree, phase == .done else { rows = []; return }
        let top: [Int]
        if let last = path.last {
            top = tree.read { t in t.sortedChildren(last) }
        } else {
            switch sidebarSelection {
            case .category: top = selectedGroup?.nodes ?? []
            case .allFolders: top = tree.read { t in t.sortedChildren(0) }
            case nil: top = []
            }
        }
        let atCategoryRoot = path.isEmpty && sidebarSelection != .allFolders
        tree.read { t in
            let total = path.last.map { t.size[$0] } ?? (selectedGroup?.size ?? top.reduce(UInt64(0)) { $0 + t.size[$1] })
            listSize = path.isEmpty ? (selectedGroup?.size ?? total) : total
            let denominator = Double(max(total, 1))
            let group = atCategoryRoot ? selectedGroup : nil
            rows = top.map { i in
                let name = t.name(i)
                let size = group?.ownSize(of: i, in: t) ?? t.size[i]
                var detail: String?
                if atCategoryRoot {
                    detail = parentPath(t, i)
                }
                if t.isDirectory(i), i != 0, AppNames.perAppParents.contains(t.name(Int(t.parent[i]))) {
                    detail = AppNames.name(forFolder: name).map { atCategoryRoot ? "\($0)・\(detail ?? "")" : $0 } ?? detail
                }
                if let bucket = classification?.settingsBucket(of: i, in: t) {
                    detail = [detail, bucket.rawValue].compactMap { $0 }.joined(separator: "・")
                }
                return ItemRow(id: i, name: name, detail: detail, size: size, share: Double(size) / denominator,
                               flags: t.flags[i], modified: t.modified[i])
            }
        }
    }

    /// フォルダなら中に入る。
    func open(_ node: Int) {
        guard let tree, tree.read({ $0.isDirectory(node) && $0.childCount[node] > 0 }) else {
            selection = node
            return
        }
        path.append(node)
        selection = nil
        rebuild()
    }

    /// 道筋の index 番目まで戻る。-1 で種類の一覧へ。
    func goBack(to index: Int) {
        let previous = path.count > index + 1 ? path[index + 1] : nil
        path = Array(path.prefix(index + 1))
        rebuild()
        selection = previous
    }

    func goUp() {
        guard !path.isEmpty else { return }
        goBack(to: path.count - 2)
    }

    func name(of node: Int) -> String { tree?.read { $0.name(node) } ?? "" }

    /// /System/Volumes/Data/Users/<自分> を ~ に縮めた、親フォルダの場所。
    private func parentPath(_ t: TreeStorage, _ node: Int) -> String? {
        guard node != 0 else { return nil }
        let parent = Int(t.parent[node])
        return parent == 0 ? "/" : shortPath(t, parent)
    }

    private func shortPath(_ t: TreeStorage, _ node: Int) -> String {
        guard var p = t.path(node) else { return t.name(node) }
        let data = VolumeInfo.dataVolumePath
        if p.hasPrefix(data + "/") { p.removeFirst(data.count) }
        let home = NSHomeDirectory()
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { p = "~" + p.dropFirst(home.count) }
        return p
    }

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
