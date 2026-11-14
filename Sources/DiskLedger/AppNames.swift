import AppKit

/// Application Support や Containers のフォルダ名（多くはバンドル ID）から、どのアプリのものかを引く。
@MainActor
enum AppNames {
    private static var cache: [String: String?] = [:]

    /// アプリ別のフォルダが並ぶ場所の名前。
    static let perAppParents: Set<String> = [
        "Application Support", "Containers", "Group Containers", "Caches", "Preferences",
        "Saved Application State", "HTTPStorages", "WebKit", "Logs",
    ]

    static func name(forFolder folder: String) -> String? {
        if let hit = cache[folder] { return hit }
        let resolved = resolve(folder)
        cache[folder] = resolved
        return resolved
    }

    private static func resolve(_ folder: String) -> String? {
        var id = folder
        for suffix in [".savedState", ".plist", ".binarycookies"] where id.hasSuffix(suffix) {
            id.removeLast(suffix.count)
        }
        // Group Containers は「チーム ID.」や「group.」が頭に付く。
        if id.hasPrefix("group.") { id.removeFirst(6) }
        let parts = id.split(separator: ".")
        if parts.count > 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            id = parts.dropFirst().joined(separator: ".")
        }
        guard id.contains(".") else { return nil }
        var candidate = id
        while candidate.split(separator: ".").count >= 2 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) {
                let name = FileManager.default.displayName(atPath: url.path)
                return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
            }
            guard let dot = candidate.lastIndex(of: ".") else { break }
            candidate = String(candidate[..<dot])
            if candidate.split(separator: ".").count < 3 { break }
        }
        return nil
    }
}
