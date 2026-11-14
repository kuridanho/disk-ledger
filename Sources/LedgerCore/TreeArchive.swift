import Foundation

/// 走査結果の木と容量の情報をファイルに書き出し、読み戻す。
/// フルディスクアクセスのあるアプリで一度だけ読み、分類の決まりの手直しはこのファイルを相手に行うために使う。
public enum TreeArchive {
    struct Header: Codable {
        var version = 1
        var rootPath: String
        var count: Int
        var nameBytes: Int
        var volume: VolumeRecord?
    }

    struct VolumeRecord: Codable {
        var name: String
        var capacity: UInt64
        var available: UInt64
        var dataUsed: UInt64
        var systemUsed: UInt64
        var purgeable: UInt64?
    }

    public static func write(_ t: TreeStorage, volume: VolumeInfo?, to url: URL) throws {
        let header = Header(rootPath: t.rootPath, count: t.count, nameBytes: t.nameBytes.count,
                            volume: volume.map { VolumeRecord(name: $0.name, capacity: $0.capacity, available: $0.available,
                                                              dataUsed: $0.dataUsed, systemUsed: $0.systemUsed, purgeable: $0.purgeable) })
        var data = try JSONEncoder().encode(header)
        data.append(0x0A)
        func append<T>(_ array: [T]) { array.withUnsafeBytes { data.append(contentsOf: $0) } }
        append(t.parent)
        append(t.size)
        append(t.firstChild)
        append(t.childCount)
        append(t.flags.map(\.rawValue))
        append(t.modified)
        append(t.nameStart)
        append(t.nameLength)
        append(t.nameBytes)
        try data.write(to: url)
    }

    public static func read(from url: URL) throws -> (TreeStorage, VolumeInfo?) {
        let data = try Data(contentsOf: url)
        guard let newline = data.firstIndex(of: 0x0A) else { throw CocoaError(.fileReadCorruptFile) }
        let header = try JSONDecoder().decode(Header.self, from: data[..<newline])
        var offset = newline + 1
        func take<T>(_ n: Int, as _: T.Type) throws -> [T] {
            let length = n * MemoryLayout<T>.stride
            guard offset + length <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            let slice = data[offset ..< offset + length]
            offset += length
            return [T](unsafeUninitializedCapacity: n) { buffer, initialized in
                _ = slice.copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
                initialized = n
            }
        }
        var t = TreeStorage()
        let n = header.count
        t.rootPath = header.rootPath
        t.parent = try take(n, as: UInt32.self)
        t.size = try take(n, as: UInt64.self)
        t.firstChild = try take(n, as: UInt32.self)
        t.childCount = try take(n, as: UInt32.self)
        t.flags = try take(n, as: UInt8.self).map(TreeStorage.Flags.init(rawValue:))
        t.modified = try take(n, as: UInt32.self)
        t.nameStart = try take(n, as: UInt32.self)
        t.nameLength = try take(n, as: UInt16.self)
        t.nameBytes = try take(header.nameBytes, as: UInt8.self)
        let volume = header.volume.map {
            VolumeInfo(name: $0.name, capacity: $0.capacity, available: $0.available, dataUsed: $0.dataUsed, systemUsed: $0.systemUsed, purgeable: $0.purgeable ?? 0)
        }
        return (t, volume)
    }
}
