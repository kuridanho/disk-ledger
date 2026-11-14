import Darwin

/// getattrlistbulk で一つのディレクトリの中身をまとめて読む。
/// FileManager の列挙より一回の呼び出しで多くの項目が取れ、名前、種類、割り当てサイズなどを一度に得られる。
struct DirectoryListing {
    struct Entry {
        var nameStart: Int
        var nameLength: Int
        var type: UInt32
        var device: Int32
        var fileFlags: UInt32
        var fileID: UInt64
        var linkCount: UInt32
        var allocatedSize: UInt64
        var modified: UInt32
    }

    var names: [UInt8] = []
    var entries: [Entry] = []

    mutating func removeAll() {
        names.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
    }
}

enum ObjectType {
    static let regular: UInt32 = 1   // VREG
    static let directory: UInt32 = 2 // VDIR
    static let symlink: UInt32 = 5   // VLNK
}

/// 中身がクラウドにだけあるもの（sys/stat.h の SF_DATALESS）。
let fileFlagDataless: UInt32 = 0x4000_0000

final class DirectoryReader {
    private static let bufferSize = 256 * 1024
    private let buffer = UnsafeMutableRawPointer.allocate(byteCount: DirectoryReader.bufferSize, alignment: 16)

    // sys/attr.h の値。Swift への取り込みで型がまちまちになるため数値で書く。
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnDevID: UInt32 = 0x0000_0002
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnModTime: UInt32 = 0x0000_0400
    private static let cmnFlags: UInt32 = 0x0004_0000
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let cmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004

    deinit { buffer.deallocate() }

    /// 読めたら 0、開けなかったら errno を返す。途中で失敗した場合も、読めた分は listing に残る。
    func read(path: String, into listing: inout DirectoryListing) -> Int32 {
        listing.removeAll()
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 { return errno }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = Self.cmnReturnedAttrs | Self.cmnName | Self.cmnDevID | Self.cmnObjType
            | Self.cmnModTime | Self.cmnFlags | Self.cmnFileID | Self.cmnError
        request.fileattr = Self.fileLinkCount | Self.fileAllocSize

        while true {
            let count = getattrlistbulk(fd, &request, buffer, Self.bufferSize, 0)
            if count < 0 { return errno }
            if count == 0 { return 0 }
            var record = UnsafeRawPointer(buffer)
            for _ in 0 ..< count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                parse(record: record, into: &listing)
                record += length
            }
        }
    }

    private func parse(record: UnsafeRawPointer, into listing: inout DirectoryListing) {
        // 先頭は長さ（4）、続いて返された属性の集合 attribute_set_t（common, vol, dir, file, fork の 4 バイトずつ）。
        let returnedCommon = (record + 4).loadUnaligned(as: UInt32.self)
        let returnedFile = (record + 16).loadUnaligned(as: UInt32.self)
        var field = record + 24

        var entry = DirectoryListing.Entry(nameStart: listing.names.count, nameLength: 0, type: 0, device: 0,
                                           fileFlags: 0, fileID: 0, linkCount: 1, allocatedSize: 0, modified: 0)
        // 属性はビットの小さい順に並び、返されたものだけが入っている。
        if returnedCommon & Self.cmnName != 0 {
            let offset = Int(field.loadUnaligned(as: Int32.self))
            let length = Int((field + 4).loadUnaligned(as: UInt32.self))
            let name = UnsafeRawBufferPointer(start: field + offset, count: max(0, length - 1)) // 末尾の NUL を除く
            listing.names.append(contentsOf: name)
            entry.nameLength = name.count
            field += 8
        }
        if returnedCommon & Self.cmnDevID != 0 {
            entry.device = field.loadUnaligned(as: Int32.self)
            field += 4
        }
        if returnedCommon & Self.cmnObjType != 0 {
            entry.type = field.loadUnaligned(as: UInt32.self)
            field += 4
        }
        if returnedCommon & Self.cmnModTime != 0 {
            let seconds = field.loadUnaligned(as: Int64.self)
            entry.modified = UInt32(clamping: seconds)
            field += 16 // struct timespec
        }
        if returnedCommon & Self.cmnFlags != 0 {
            entry.fileFlags = field.loadUnaligned(as: UInt32.self)
            field += 4
        }
        if returnedCommon & Self.cmnFileID != 0 {
            entry.fileID = field.loadUnaligned(as: UInt64.self)
            field += 8
        }
        if returnedCommon & Self.cmnError != 0 {
            field += 4
        }
        if returnedFile & Self.fileLinkCount != 0 {
            entry.linkCount = field.loadUnaligned(as: UInt32.self)
            field += 4
        }
        if returnedFile & Self.fileAllocSize != 0 {
            entry.allocatedSize = UInt64(clamping: field.loadUnaligned(as: Int64.self))
            field += 8
        }
        listing.entries.append(entry)
    }
}
