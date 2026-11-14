import Foundation

/// システム設定のストレージの画面が、システムデータではなく別の項目に数えていると思われるもの。
/// Apple は振り分けの決まりを公開していないので、2026-11-14 に実機の数値と突き合わせて推測した。
public enum SettingsBucket: String, Sendable, CaseIterable {
    /// 入っているアプリの補助データ。設定では「アプリケーション」に入る。
    case applications = "アプリケーション"
    /// 手元に落としたローカル AI のモデル。設定では「書類」に入る。
    case documents = "書類"
}

/// 入っているアプリの名前とバンドル ID。アプリの補助データがどのアプリのものかを決めるのに使う。
public struct InstalledApps: Sendable {
    var names: Set<String> = []
    var bundleIDs: Set<String> = []

    public static let empty = InstalledApps()

    public init() {}

    init(names: [String], bundleIDs: [String]) {
        self.names = Set(names.map { $0.lowercased() })
        self.bundleIDs = Set(bundleIDs.map { $0.lowercased() })
    }

    /// /Applications、~/Applications と、その一つ下のフォルダにあるアプリを読む。
    public static func current() -> InstalledApps {
        let fm = FileManager.default
        var names: [String] = []
        var ids: [String] = []
        func add(_ url: URL) {
            names.append(url.deletingPathExtension().lastPathComponent)
            if let id = Bundle(url: url)?.bundleIdentifier { ids.append(id) }
        }
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"].map { URL(fileURLWithPath: $0) }
        for root in roots {
            for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                if item.pathExtension == "app" {
                    add(item)
                } else {
                    for inner in (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? [] where inner.pathExtension == "app" {
                        add(inner)
                    }
                }
            }
        }
        return InstalledApps(names: names, bundleIDs: ids)
    }

    /// Application Support などの直下のフォルダ名が、入っているアプリのものか。
    func owns(_ folder: String, in parent: String) -> Bool {
        let f = folder.lowercased()
        switch parent {
        case "Containers":
            return bundleIDs.contains { f == $0 || f.hasPrefix($0 + ".") }
        case "Group Containers":
            // group.<ID> や <チーム ID>.<ID> の形。
            var rest = f
            if rest.hasPrefix("group.") { rest.removeFirst(6) } else if let dot = rest.firstIndex(of: "."), rest.distance(from: rest.startIndex, to: dot) == 10 {
                rest = String(rest[rest.index(after: dot)...])
            }
            return bundleIDs.contains { rest == $0 || rest.hasPrefix($0 + ".") }
        default:
            if bundleIDs.contains(f) { return true }
            // 「Google」と「Google Chrome」、「iStat Menus 7」と「iStat Menus」のように、語の切れ目で前方が一致するものも含める。
            return names.contains { f == $0 || $0.hasPrefix(f + " ") || f.hasPrefix($0 + " ") }
        }
    }
}

extension Categories {
    /// 入っているアプリの補助データを置く場所。直下のフォルダをアプリと照らし合わせる。
    static let perAppParents: [[String]] = [
        ["Users", "*", "Library", "Application Support"], ["Users", "*", "Library", "Containers"],
        ["Users", "*", "Library", "Group Containers"],
    ]

    /// 設定では書類に数えられているらしい場所。
    static let documentPatterns: [[String]] = [
        ["Users", "*", ".lmstudio", "models"], ["Users", "*", ".ollama", "models"],
        ["Users", "*", ".cache", "huggingface"],
    ]

    static func settingsBucket(_ rel: [String], apps: InstalledApps) -> SettingsBucket? {
        if Glob.matchesAny(documentPatterns, rel) { return .documents }
        if rel.count >= 5, Glob.matchesAny(perAppParents, Array(rel.dropLast())), apps.owns(rel.last!, in: rel[rel.count - 2]) {
            return .applications
        }
        return nil
    }
}
