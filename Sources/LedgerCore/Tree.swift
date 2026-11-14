import Foundation

/// 走査結果の木。数百万件を持つため、ノードを構造体にせず、項目ごとの配列に分けて持つ。
/// ノード 0 が根で、あるディレクトリの子は必ず連続した番号で並び、親より後ろに置かれる。
public struct TreeStorage: Sendable {
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let directory = Flags(rawValue: 1 << 0)
        /// 権限がなく中を読めなかったディレクトリ。
        public static let unreadable = Flags(rawValue: 1 << 1)
        /// iCloud などで中身が手元にないもの。中は読まない。
        public static let dataless = Flags(rawValue: 1 << 2)
        /// 別のボリュームの入口。中には入らない。
        public static let mountPoint = Flags(rawValue: 1 << 3)
        /// 既に数えたファイルへのハードリンク。容量は 0 として扱う。
        public static let hardLinkDuplicate = Flags(rawValue: 1 << 4)
        public static let symlink = Flags(rawValue: 1 << 5)
        /// ディスクにない、集計のために作った項目（システム、その他など）。
        public static let synthetic = Flags(rawValue: 1 << 6)
        /// フルディスクアクセスがないため、確認の窓を出さないよう読まなかった場所。
        public static let needsPermission = Flags(rawValue: 1 << 7)
    }

    public internal(set) var parent: [UInt32] = []
    public internal(set) var size: [UInt64] = []
    public internal(set) var firstChild: [UInt32] = []
    public internal(set) var childCount: [UInt32] = []
    public internal(set) var flags: [Flags] = []
    /// 更新日時（1970年からの秒）。
    public internal(set) var modified: [UInt32] = []
    var nameStart: [UInt32] = []
    var nameLength: [UInt16] = []
    var nameBytes: [UInt8] = []
    /// 根に当たる実際のパス。
    public internal(set) var rootPath: String = "/"

    public var count: Int { parent.count }

    public func name(_ i: Int) -> String {
        let start = Int(nameStart[i])
        return String(decoding: nameBytes[start ..< start + Int(nameLength[i])], as: UTF8.self)
    }

    public func children(_ i: Int) -> Range<Int> {
        let start = Int(firstChild[i])
        return start ..< start + Int(childCount[i])
    }

    public func isDirectory(_ i: Int) -> Bool { flags[i].contains(.directory) }

    /// 子を容量の大きい順に返す。
    public func sortedChildren(_ i: Int) -> [Int] {
        children(i).sorted { size[$0] > size[$1] }
    }

    /// 根からの道筋（根を含む）。
    public func ancestry(_ i: Int) -> [Int] {
        var chain = [i]
        var p = i
        while p != 0 {
            p = Int(parent[p])
            chain.append(p)
        }
        return chain.reversed()
    }

    /// ディスク上の実際のパス。集計用の項目には nil を返す。
    public func path(_ i: Int) -> String? {
        if flags[i].contains(.synthetic) { return nil }
        if i == 0 { return rootPath }
        var parts: [String] = []
        var p = i
        while p != 0 {
            parts.append(name(p))
            p = Int(parent[p])
        }
        let base = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        return base + "/" + parts.reversed().joined(separator: "/")
    }

    mutating func appendNode(parent p: UInt32, name: UnsafeRawBufferPointer, size s: UInt64, flags f: Flags, modified m: UInt32) {
        parent.append(p)
        size.append(s)
        firstChild.append(0)
        childCount.append(0)
        flags.append(f)
        modified.append(m)
        nameStart.append(UInt32(nameBytes.count))
        nameLength.append(UInt16(min(name.count, Int(UInt16.max))))
        nameBytes.append(contentsOf: name.prefix(Int(UInt16.max)))
    }

    mutating func appendNode(parent p: UInt32, name: String, size s: UInt64, flags f: Flags, modified m: UInt32) {
        var n = name
        n.withUTF8 { appendNode(parent: p, name: UnsafeRawBufferPointer($0), size: s, flags: f, modified: m) }
    }

    /// i とその祖先すべての容量に delta を足す。
    mutating func addSize(_ delta: UInt64, from i: Int) {
        guard delta > 0 else { return }
        var p = i
        while true {
            size[p] &+= delta
            if p == 0 { break }
            p = Int(parent[p])
        }
    }
}

/// 走査中は複数のスレッドが書き足し、画面が途中経過を読むため、鍵をかけて共有する。
public final class Tree: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = TreeStorage()

    public init() {}

    init(storage: TreeStorage) { self.storage = storage }

    public func read<R>(_ body: (TreeStorage) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(storage)
    }

    func write<R>(_ body: (inout TreeStorage) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storage)
    }
}
