import Foundation

/// ディスクを複数のスレッドで走査し、Tree に書き足す。
/// 読んだディレクトリの中身はその場で木に足し、ファイルの容量を祖先へ加えるので、走査の途中でも集計が見られる。
public final class DiskScanner: @unchecked Sendable {
    public struct Progress: Sendable {
        public var files = 0
        public var directories = 0
        public var unreadable = 0
        public var bytes: UInt64 = 0
        public var currentPath = ""
        public var finished = false
        public var elapsed: TimeInterval = 0

        public init() {}
    }

    public struct Options: Sendable {
        public var rootPath: String
        /// 根の下にシステムボリュームと「その他」の項目を足し、ディスクの使用量全体と合わせる。
        public var includeVolumeSummary: Bool
        public var threads: Int
        /// 許可を求める窓が出る場所を読まない。フルディスクアクセスがないときに使う。
        public var skipPromptingPaths: Bool

        public init(rootPath: String = VolumeInfo.defaultScanRoot, includeVolumeSummary: Bool = true,
                    threads: Int = ProcessInfo.processInfo.activeProcessorCount,
                    skipPromptingPaths: Bool = !FullDiskAccess.isGranted) {
            self.rootPath = rootPath
            self.includeVolumeSummary = includeVolumeSummary
            self.skipPromptingPaths = skipPromptingPaths
            self.threads = max(1, threads)
        }
    }

    public let tree: Tree
    public let options: Options
    public private(set) var volume: VolumeInfo?

    private struct Job {
        var node: UInt32
        var path: String
    }

    private let queue = NSCondition()
    private var pending: [Job] = []
    private var active = 0
    private var cancelled = false

    private let statsLock = NSLock()
    private var stats = Progress()
    private var startDate = Date()

    private var seenHardLinks = Set<UInt64>()
    private var rootDevice: Int32 = 0
    private var otherNode: Int?

    public init(options: Options = Options()) {
        self.options = options
        self.tree = Tree()
    }

    /// 書き出した走査結果を、読み終えた状態として持つ。確認用。
    public init(archive url: URL) throws {
        let (storage, volume) = try TreeArchive.read(from: url)
        self.options = Options(rootPath: storage.rootPath, skipPromptingPaths: true)
        self.tree = Tree(storage: storage)
        self.volume = volume
        stats.finished = true
    }

    public func progress() -> Progress {
        statsLock.lock()
        defer { statsLock.unlock() }
        var p = stats
        p.elapsed = Date().timeIntervalSince(startDate)
        return p
    }

    public func cancel() {
        queue.lock()
        cancelled = true
        queue.broadcast()
        queue.unlock()
    }

    /// 走査が終わるまで戻らない。
    public func run() {
        Self.disableDatalessMaterialization()
        startDate = Date()
        let root = options.rootPath
        var info = stat()
        rootDevice = lstat(root, &info) == 0 ? Int32(info.st_dev) : 0

        let volume = options.includeVolumeSummary ? VolumeInfo.current() : nil
        self.volume = volume
        tree.write { t in
            t.rootPath = root
            t.appendNode(parent: 0, name: volume?.name ?? (root as NSString).lastPathComponent,
                         size: 0, flags: .directory, modified: 0)
        }
        pending = [Job(node: 0, path: root)]

        DispatchQueue.concurrentPerform(iterations: options.threads) { _ in worker() }
        finish()
    }

    /// 走査が iCloud などのファイルのダウンロードを引き起こさないよう、このプロセスでは中身の取り寄せを止める。
    static func disableDatalessMaterialization() {
        // sys/resource.h: IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF
        _ = setiopolicy_np(3, 0, 1)
    }

    private func worker() {
        let reader = DirectoryReader()
        var listing = DirectoryListing()
        while true {
            queue.lock()
            while pending.isEmpty && active > 0 && !cancelled { queue.wait() }
            if pending.isEmpty || cancelled {
                queue.broadcast()
                queue.unlock()
                return
            }
            let job = pending.removeLast()
            active += 1
            queue.unlock()

            let status = reader.read(path: job.path, into: &listing)
            let next = record(job: job, status: status, listing: listing)

            queue.lock()
            pending.append(contentsOf: next)
            active -= 1
            queue.broadcast()
            queue.unlock()
        }
    }

    /// 読んだ中身を木に足し、次に読むディレクトリを返す。
    private func record(job: Job, status: Int32, listing: DirectoryListing) -> [Job] {
        var subdirectories: [Job] = []
        var addedBytes: UInt64 = 0
        var fileCount = 0
        var dirCount = 0
        let parent = Int(job.node)
        let unreadable = (status == EACCES || status == EPERM) && listing.entries.isEmpty

        tree.write { t in
            if unreadable {
                t.flags[parent].insert(.unreadable)
                return
            }
            var count = listing.entries.count
            if job.node == 0, volume != nil, options.includeVolumeSummary { count += 2 }
            t.firstChild[parent] = UInt32(t.count)
            t.childCount[parent] = UInt32(count)

            listing.names.withUnsafeBytes { names in
                for entry in listing.entries {
                    let name = UnsafeRawBufferPointer(rebasing: names[entry.nameStart ..< entry.nameStart + entry.nameLength])
                    var flags: TreeStorage.Flags = []
                    var size: UInt64 = 0
                    let index = t.count
                    var descend = false
                    switch entry.type {
                    case ObjectType.directory:
                        flags.insert(.directory)
                        dirCount += 1
                        if entry.fileFlags & fileFlagDataless != 0 {
                            flags.insert(.dataless)
                        } else if entry.device != rootDevice {
                            flags.insert(.mountPoint)
                        } else {
                            descend = true
                        }
                    default:
                        fileCount += 1
                        if entry.type == ObjectType.symlink { flags.insert(.symlink) }
                        if entry.fileFlags & fileFlagDataless != 0 { flags.insert(.dataless) }
                        size = entry.allocatedSize
                        if entry.linkCount > 1, !seenHardLinks.insert(entry.fileID).inserted {
                            flags.insert(.hardLinkDuplicate)
                            size = 0
                        }
                    }
                    t.appendNode(parent: job.node, name: name, size: size, flags: flags, modified: entry.modified)
                    addedBytes &+= size
                    if descend {
                        let childName = String(decoding: name, as: UTF8.self)
                        let path = job.path.hasSuffix("/") ? job.path + childName : job.path + "/" + childName
                        if options.skipPromptingPaths, FullDiskAccess.prompts(path: path, scanRoot: options.rootPath) {
                            t.flags[index].insert(.needsPermission)
                        } else {
                            subdirectories.append(Job(node: UInt32(index), path: path))
                        }
                    }
                }
            }
            if job.node == 0, let volume, options.includeVolumeSummary {
                t.appendNode(parent: 0, name: "macOS 本体", size: volume.systemUsed, flags: .synthetic, modified: 0)
                addedBytes &+= volume.systemUsed
                otherNode = t.count
                t.appendNode(parent: 0, name: "その他", size: 0, flags: .synthetic, modified: 0)
            }
            t.addSize(addedBytes, from: parent)
        }

        statsLock.lock()
        stats.files += fileCount
        stats.directories += dirCount
        stats.bytes &+= addedBytes
        if unreadable { stats.unreadable += 1 }
        stats.currentPath = job.path
        statsLock.unlock()
        return subdirectories
    }

    /// データボリュームの使用量のうち、読めた分で説明できない残りを「その他」に入れる。
    /// 読めなかったフォルダ、ローカルスナップショット、管理者だけが読める場所などがここに含まれる。
    private func finish() {
        if !cancelled, let volume, let otherNode {
            tree.write { t in
                let scanned = t.size[0] &- volume.systemUsed
                let rest = volume.dataUsed > scanned ? volume.dataUsed - scanned : 0
                t.size[otherNode] = rest
                t.addSize(rest, from: 0)
            }
        }
        statsLock.lock()
        stats.finished = true
        stats.currentPath = ""
        statsLock.unlock()
    }
}
