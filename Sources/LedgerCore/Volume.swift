import Foundation

/// 起動ディスクの容量。APFS では起動ディスクが読み取り専用のシステムと、書き込めるデータの二つのボリュームに分かれている。
public struct VolumeInfo: Sendable {
    public var name: String
    /// ディスク全体の容量。
    public var capacity: UInt64
    /// 空き容量（パージ可能な領域を含まない、今すぐ使える量）。
    public var available: UInt64
    /// データボリュームが使っている量。
    public var dataUsed: UInt64
    /// システムボリュームが使っている量。
    public var systemUsed: UInt64
    /// 空きが必要になれば macOS が消せる量（ローカルスナップショット、iCloud の控えなど）。
    /// システム設定の使用済みはこれを除いた量で、空きはこれを含めた量になる。
    public var purgeable: UInt64 = 0

    public static let dataVolumePath = "/System/Volumes/Data"

    public static func current() -> VolumeInfo {
        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey])
        let available = UInt64(values?.volumeAvailableCapacity ?? 0)
        let important = UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
        return VolumeInfo(
            name: values?.volumeLocalizedName ?? "Macintosh HD",
            capacity: UInt64(values?.volumeTotalCapacity ?? 0),
            available: available,
            dataUsed: used(at: dataVolumePath),
            systemUsed: used(at: "/"),
            purgeable: important > available ? important - available : 0
        )
    }

    /// ボリュームごとの使用量。APFS の statfs はコンテナ全体の使用量を返すので使えず、df と同じく ATTR_VOL_SPACEUSED を読む。
    static func used(at path: String) -> UInt64 {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = 0x8000_0000 | 0x0080_0000 // ATTR_VOL_INFO | ATTR_VOL_SPACEUSED
        var buffer = (UInt32(0), Int64(0))
        let status = withUnsafeMutableBytes(of: &buffer) { raw in
            getattrlist(path, &request, raw.baseAddress, raw.count, 0)
        }
        guard status == 0 else { return 0 }
        return withUnsafeBytes(of: &buffer) { UInt64(clamping: $0.loadUnaligned(fromByteOffset: 4, as: Int64.self)) }
    }

    /// 起動ディスクのデータボリュームの場所。古い構成でなければ /System/Volumes/Data。
    public static var defaultScanRoot: String {
        FileManager.default.fileExists(atPath: dataVolumePath) ? dataVolumePath : "/"
    }
}

public enum FullDiskAccess {
    /// フルディスクアクセスがあれば読める TCC のデータベースを開いて確かめる。
    public static var isGranted: Bool {
        let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        return false
    }

    /// フルディスクアクセスがないと、開くたびに許可を求める窓が出る場所。ホームからの相対パス。
    /// 許可がないときはここに入らず、「許可が必要」として残す。すべてを網羅できている保証はない。
    public static let promptingHomePaths: Set<String> = [
        "Desktop", "Documents", "Downloads",
        "Pictures/Photos Library.photoslibrary",
        "Library/Mobile Documents", "Library/CloudStorage",
        "Library/Containers", "Library/Group Containers", "Library/Daemon Containers",
        "Library/Mail", "Library/Messages", "Library/Safari", "Library/Cookies",
        "Library/Calendars", "Library/Reminders", "Library/HomeKit", "Library/Biome",
        "Library/IdentityServices", "Library/Suggestions", "Library/Metadata/CoreSpotlight",
        "Library/Application Support/AddressBook", "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CallHistoryTransactions", "Library/Application Support/com.apple.TCC",
        "Library/Application Support/FaceTime", "Library/Application Support/Knowledge",
        "Library/Application Support/com.apple.sharedfilelist", "Library/Autosave Information",
        "Library/Accounts", "Library/Sharing", "Library/Shortcuts", "Library/Trial",
        "Library/Application Support/MobileSync", ".Trash",
    ]

    /// /Users/<名前>/ の下で、promptingHomePaths に当たるかどうか。
    public static func prompts(path: String, scanRoot: String) -> Bool {
        var relative = path
        if relative.hasPrefix(scanRoot) && scanRoot != "/" { relative.removeFirst(scanRoot.count) }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "Users" else {
            return relative == "/Library/Application Support/com.apple.TCC"
        }
        return promptingHomePaths.contains(parts[2...].joined(separator: "/"))
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
}
