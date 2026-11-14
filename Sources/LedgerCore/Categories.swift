import Foundation

/// 消してよいかを判断するための目安。
public enum Verdict: String, Sendable, CaseIterable {
    case regenerable = "再生成可能"
    case redownload = "再取得可能"
    case reinstall = "再導入可能"
    case appData = "アプリ固有"
    case system = "システム管理"
    case irreplaceable = "復元不可"
    case unknown = "要確認"
    case trashed = "削除予定"
}

/// システム設定のストレージの画面に並ぶ項目。種類はこのどれかに属する。
public enum StorageArea: String, Sendable, CaseIterable, Identifiable {
    case applications = "アプリケーション"
    case documents = "書類"
    case icloud = "iCloud Drive"
    case photos = "写真"
    case music = "ミュージック"
    case musicCreation = "音楽制作"
    case mail = "メール"
    case messages = "メッセージ"
    case developer = "デベロッパ"
    case trash = "ゴミ箱"
    case otherUsers = "その他のユーザ・共有"
    case macOS = "macOS"
    case systemData = "システムデータ"

    public var id: String { rawValue }
}

/// システム設定で「システムデータ」にまとめられるものを、場所の決まりで種類に分ける。
/// パターンはデータボリュームの根からの相対パスで、~ は Users/*、* は任意の一階層、** は任意の深さ、.* は . で始まる名前。
/// 深い場所に当たる決まりほど優先する。たとえばアプリの補助データの中のキャッシュは、キャッシュとして数える。
public struct CategoryRule: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let verdict: Verdict
    public let summary: String
    public let area: StorageArea
    let patterns: [[String]]

    init(_ id: String, _ name: String, _ verdict: Verdict, _ summary: String, _ patterns: [String],
         area: StorageArea = .systemData) {
        self.id = id
        self.area = area
        self.name = name
        self.verdict = verdict
        self.summary = summary
        self.patterns = patterns.map { pattern in
            pattern.split(separator: "/").flatMap { $0 == "~" ? ["Users", "*"] : [String($0)] }
        }
    }
}

public enum Categories {
    public static let snapshotsID = "snapshots"
    public static let unclassifiedID = "unclassified"
    public static let appSupportID = "app-support"
    public static let homeOtherID = "home-other"
    public static let macOSVolumeID = "macos-volume"
    /// 走査が根に足す、ディスクにない項目のうち macOS に数えるもの。
    public static let macOSSyntheticNames: Set<String> = ["macOS 本体", "Preboot", "VM", "Update", "Recovery"]

    public static let rules: [CategoryRule] = [
        // システム設定でシステムデータ以外の項目に数えられるもの。同じ場所に当たるときはシステムデータの決まりより優先する。
        .init("apps", "アプリ本体", .reinstall,
              "インストール済みアプリの本体。削除はアプリのアンインストールに当たり、App Store や配布元から再導入できる。",
              ["Applications", "~/Applications"], area: .applications),
        .init(appSupportID, "アプリ補助データ", .appData,
              "インストール済みアプリに属する設定、キャッシュ、作業データ。システム設定はアプリ本体と合わせて計上する。アプリを使い続ける限り削除は推奨しない。",
              [], area: .applications),
        .init("documents-folder", "書類フォルダ", .irreplaceable,
              "利用者が作成、保存したファイル。削除すると復元できない。",
              ["~/Documents"], area: .documents),
        .init("desktop", "デスクトップ", .irreplaceable,
              "デスクトップに置いたファイル。",
              ["~/Desktop"], area: .documents),
        .init("downloads", "ダウンロード", .unknown,
              "ブラウザなどで取得したファイル。導入済みのインストーラなど、不要になったものが残りやすい。",
              ["~/Downloads"], area: .documents),
        .init("movies", "ムービー", .irreplaceable,
              "動画と、動画編集アプリの作業ファイル。編集アプリのキャッシュを含む場合がある。",
              ["~/Movies"], area: .documents),
        .init("ai-model-files", "AI モデル", .redownload,
              "LM Studio などで取得したモデル本体。システム設定は書類として計上する。削除後の使用には再取得が必要。",
              ["~/.lmstudio/models", "~/.ollama/models", "~/.cache/huggingface"], area: .documents),
        .init("cloud-storage", "クラウドストレージ", .redownload,
              "Google Drive や OneDrive などの同期フォルダのうち、手元に保持している分。システム設定はシステムデータに計上する。各サービスの設定で手元の複製を減らせる。",
              ["~/Library/CloudStorage"]),
        .init(homeOtherID, "ホームのその他", .unknown,
              "ホームフォルダ直下の、上記以外のフォルダとファイル。",
              [], area: .documents),
        .init("pictures", "ピクチャ", .irreplaceable,
              "写真ライブラリ以外の画像。",
              ["~/Pictures"], area: .documents),
        .init("photos-library", "写真ライブラリ", .irreplaceable,
              "写真アプリのライブラリ。iCloud 写真を使う場合、最適化の設定で手元の容量を減らせる。",
              ["~/Pictures/*.photoslibrary"], area: .photos),
        .init("icloud-drive", "iCloud Drive", .redownload,
              "iCloud Drive のうち手元に保持している分。Finder から「ダウンロードを削除」で手元の複製のみを外せる。",
              ["~/Library/Mobile Documents"], area: .icloud),
        .init("music-library", "ミュージック", .irreplaceable,
              "ミュージックアプリのライブラリと、その他の音楽ファイル。",
              ["~/Music"], area: .music),
        .init("music-creation", "GarageBand・Logic 音源", .redownload,
              "GarageBand と Logic Pro の音源とループ。各アプリの音源管理から削除、再取得できる。",
              ["Library/Application Support/GarageBand", "Library/Application Support/Logic", "Library/Audio/Apple Loops",
               "~/Library/Application Support/GarageBand", "~/Library/Application Support/Logic"], area: .musicCreation),
        .init("mail", "メール", .irreplaceable,
              "メールアプリが保持するメッセージと添付ファイル。",
              ["~/Library/Mail", "~/Library/Containers/com.apple.mail"], area: .mail),
        .init("messages", "メッセージ", .irreplaceable,
              "メッセージアプリの履歴と添付ファイル。",
              ["~/Library/Messages"], area: .messages),
        .init("trash", "ゴミ箱", .trashed,
              "ゴミ箱に入れたファイル。ゴミ箱を空にすると削除される。",
              ["~/.Trash"], area: .trash),
        .init("shared", "共有フォルダ", .unknown,
              "Mac の全利用者が使える共有フォルダ。",
              ["Users/Shared"], area: .otherUsers),
        .init(macOSVolumeID, "macOS ボリューム", .system,
              "macOS 本体の読取専用ボリュームと、起動、復旧、仮想メモリ用のボリューム。macOS の管理下にある。",
              [], area: .macOS),
        .init("caches", "キャッシュ", .regenerable,
              "アプリや macOS が高速化のために保持するデータ。削除しても必要時に再生成されるが、直後は起動や表示が遅くなる場合がある。",
              ["~/Library/Caches", "Library/Caches", "System/Library/Caches",
               "~/Library/Containers/*/Data/Library/Caches",
               "~/Library/Application Support/**/Cache", "~/Library/Application Support/**/Caches",
               "~/Library/Application Support/**/Code Cache", "~/Library/Application Support/**/GPUCache",
               "~/Library/Application Support/**/CacheStorage", "~/Library/Application Support/**/ShaderCache"]),
        .init("logs", "ログ・診断記録", .regenerable,
              "アプリや macOS の動作記録。不具合調査以外では不要で、古いものから macOS が自動整理する。",
              ["~/Library/Logs", "Library/Logs", "private/var/log", "private/var/logs",
               "private/var/db/diagnostics", "private/var/db/uuidtext", "cores"]),
        .init("temporary", "一時ファイル", .system,
              "アプリが作業中に使用するファイル。再起動時や定期的に macOS が整理する。手動削除は動作中のアプリに支障を来す場合がある。",
              ["private/var/folders", "private/tmp", "private/var/tmp"]),
        .init("vm", "仮想メモリ・スリープイメージ", .system,
              "メモリ不足時とスリープ時に macOS が使用する領域。",
              ["private/var/vm"]),
        .init("macos-data", "macOS 追加データ", .system,
              "Apple Intelligence のモデル、辞書、音声、フォントなど、macOS が追加取得したデータ。macOS の管理下にあり、手動削除は不可。",
              ["System"]),
        .init("updates", "macOS 更新ファイル", .system,
              "取得済みで未適用の macOS 更新ファイル。適用後に自動削除される。",
              ["Library/Updates"]),
        .init("spotlight", "検索索引", .regenerable,
              "Spotlight 検索用の索引。削除しても再生成されるが、再構築中は検索結果が不完全になる。",
              [".Spotlight-V100", "private/var/db/Spotlight-V100", "~/Library/Metadata/CoreSpotlight"]),
        .init("xcode-build", "Xcode 中間生成物", .regenerable,
              "Xcode のビルド中間生成物と、接続端末用のシンボル情報。削除しても次回のビルドや接続時に再生成される。",
              ["~/Library/Developer/Xcode/DerivedData", "~/Library/Developer/Xcode/iOS DeviceSupport",
               "~/Library/Developer/Xcode/macOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport",
               "~/Library/Developer/Xcode/tvOS DeviceSupport", "~/Library/Developer/Xcode/visionOS DeviceSupport",
               "~/Library/Developer/Xcode/Archives", "~/Library/Developer/Xcode/Products"], area: .developer),
        .init("simulators", "シミュレータ", .redownload,
              "iOS などのシミュレータ本体と端末データ。不要な OS 版は Xcode の設定から削除できる。",
              ["~/Library/Developer/CoreSimulator", "Library/Developer/CoreSimulator",
               "System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime",
               "System/Library/AssetsV2/com_apple_MobileAsset_watchOSSimulatorRuntime",
               "System/Library/AssetsV2/com_apple_MobileAsset_tvOSSimulatorRuntime",
               "System/Library/AssetsV2/com_apple_MobileAsset_xrOSSimulatorRuntime",
               "System/Library/AssetsV2/com_apple_MobileAsset_visionOSSimulatorRuntime"]),
        .init("dev-cache", "開発ツールキャッシュ", .regenerable,
              "npm、pip、Gradle、Cargo などが取得した部品の複製。削除しても次回必要時に再取得される。",
              ["~/.npm", "~/.cache", "~/.gradle", "~/.m2", "~/.pnpm-store", "~/Library/pnpm", "~/.yarn",
               "~/.cargo/registry", "~/.bun/install/cache", "~/Library/org.swift.swiftpm", "~/.swiftpm",
               "~/go/pkg", "~/.go/pkg"]),
        .init("dev-tools", "開発ツール", .reinstall,
              "Homebrew、Command Line Tools、言語処理系など、導入済み開発ツールの本体。削除すると依存する環境が動作しなくなる。",
              ["Library/Developer", "~/Library/Developer", "opt", "usr/local",
               "~/.rustup", "~/.cargo", "~/.pyenv", "~/.nvm", "~/.volta", "~/.bun", "~/.deno", "~/.local",
               "~/go", "~/.go", "~/.gem", "~/.rbenv", "~/.sdkman", "~/.zprezto", "~/.oh-my-zsh",
               "System/Library/AssetsV2/com_apple_MobileAsset_AppleDeveloperDocumentation"]),
        .init("ai-models", "ローカル AI モデル", .redownload,
              "LM Studio、Ollama、Hugging Face などで取得したモデル。削除後の使用には再取得が必要。",
              ["~/.lmstudio", "~/.ollama", "~/.cache/huggingface", "~/.cache/lm-studio"]),
        .init("vms", "仮想マシンディスク", .appData,
              "Docker や Claude などが使用する仮想マシンのディスク。内部環境ごと失われるため、未使用のものに限り削除対象とする。",
              ["~/Library/Containers/com.docker.docker", "~/Library/Group Containers/*.com.docker",
               "~/Library/Application Support/Claude/vm_bundles", "~/Library/Containers/com.utmapp.UTM",
               "~/.colima", "~/.orbstack"]),
        .init("device-backups", "iOS 端末バックアップ", .irreplaceable,
              "Finder で作成した iPhone などのバックアップ。削除すると当該時点への復元は不可。旧端末分は Finder の端末画面から削除できる。",
              ["~/Library/Application Support/MobileSync/Backup"]),
        .init("audio", "音源・プラグイン", .redownload,
              "音楽アプリの音源とプラグイン。大半は配布元のアプリから再導入できる。",
              ["~/Library/Audio", "Library/Audio", "~/Library/Application Support/Muse Hub",
               "~/Library/Application Support/MuseSampler", "Library/Application Support/Muse Hub",
               "~/Library/Application Support/Native Instruments", "Library/Application Support/Native Instruments",
               "~/Library/Application Support/Spitfire Audio", "Library/Application Support/Spitfire Audio"]),
        .init("macos-internal", "macOS 内部データ", .system,
              "学習、同期、セキュリティ、更新管理のために macOS が保持するデータ。キーチェーンを含む。macOS の管理下にあり、手動削除は不具合の原因となる。",
              ["private", ".fseventsd", ".DocumentRevisions-V100", ".PreviousSystemInformation", ".MobileBackups",
               "~/Library/Biome", "~/Library/DuetExpertCenter", "~/Library/IntelligencePlatform", "~/Library/Trial",
               "~/Library/PersonalizationPortrait", "~/Library/Suggestions", "~/Library/IdentityServices",
               "~/Library/Keychains", "~/Library/Daemon Containers", "~/Library/Metadata", "~/Library/Assistant",
               "~/Library/Accounts", "~/Library/Sharing", "~/Library/StatusKit", "~/Library/AppleMediaServices",
               "Library/Apple", "Library/Keychains", "Library/SystemMigration", "Library/Trial"]),
        .init("app-data", "アプリ補助データ", .appData,
              "アプリの設定と作業データ。アプリ削除後も残存する場合があり、使用しなくなったアプリの分は削除して差し支えない。行を開くと所属アプリを確認できる。",
              ["~/Library/Application Support", "~/Library/Containers", "~/Library/Group Containers",
               "Library/Application Support", "~/Library/WebKit", "~/Library/HTTPStorages",
               "~/Library/Preferences", "~/Library/Saved Application State", "Library/Preferences",
               // 上のどれにも当たらない ~/Library や /Library の直下と、ホームの隠しフォルダは、ほぼアプリや道具の置き場。
               "~/Library/*", "Library/*", "~/.*"]),

    ]

    public static let snapshotsRule = CategoryRule(
        snapshotsID, "スナップショット・読取不可領域", .system,
        "ボリューム使用量のうち、ファイルとして計上できなかった分。Time Machine のローカルスナップショット、管理者専用領域、スナップショットが保持する削除済みファイルなどを含む。スナップショットは空き容量の不足時に macOS が自動削除する。",
        [])

    public static let unclassifiedRule = CategoryRule(
        unclassifiedID, "未分類", .unknown,
        "システムデータに含まれるが、いずれの種類にも該当しなかった場所。行を開いて所属アプリを確認する。",
        [])

    /// システムデータとして数える範囲。ここに入らないもの（アプリ、書類、写真など）は数えない。
    static let scope: [[String]] = [
        ["Users", "*", "Library"], ["Users", "*", ".*"], ["Library"], ["private"], ["System"],
        ["usr"], ["opt"], [".*"], ["cores"],
    ]

    /// 数えないもの。別のボリュームの入口が並ぶ場所。
    static let excluded: [[String]] = [["Volumes"]]
}

/// 分類の結果。
public struct Classification: Sendable {
    public struct Group: Sendable, Identifiable {
        public var rule: CategoryRule
        /// この種類に当たったノード。中に別の種類が入れ子になっていることがある。
        public var nodes: [Int]
        /// 入れ子の別の種類を除いた容量。
        public var size: UInt64
        /// nodes のうち、中に別の種類が入れ子になっているものと、その容量。
        public var nested: [Int: UInt64] = [:]

        /// ノードの容量から入れ子の別の種類を除いた分。
        public func ownSize(of node: Int, in t: TreeStorage) -> UInt64 {
            t.size[node] - min(t.size[node], nested[node] ?? 0)
        }
        public var id: String { rule.id }
    }

    /// 容量の大きい順。
    public var groups: [Group]
    /// 空きが必要になれば macOS が消せる量。システム設定はこれを使用済みに含めない。
    public var purgeable: UInt64 = 0

    public func groups(in area: StorageArea) -> [Group] { groups.filter { $0.rule.area == area } }

    /// 項目の容量。システムデータはシステム設定に合わせ、パージ可能な分を除く。
    public func size(of area: StorageArea) -> UInt64 {
        let sum = groups(in: area).reduce(0) { $0 + $1.size }
        return area == .systemData ? sum - min(sum, purgeable) : sum
    }

    /// 中身のある項目。システム設定と同じく、macOS とシステムデータを最後に置き、ほかは容量の大きい順。
    public var areas: [StorageArea] {
        let present = StorageArea.allCases.filter { size(of: $0) > 0 }
        let tail: [StorageArea] = [.macOS, .systemData]
        return present.filter { !tail.contains($0) }.sorted { size(of: $0) > size(of: $1) } + tail.filter(present.contains)
    }

    /// システム設定の使用済みに当たる合計。
    public var usedTotal: UInt64 { StorageArea.allCases.reduce(0) { $0 + size(of: $1) } }
}

extension Categories {
    public static func classify(_ t: TreeStorage, purgeable: UInt64 = 0, apps: InstalledApps = .empty) -> Classification {
        let allRules = rules + [snapshotsRule, unclassifiedRule]
        var nodes = Array(repeating: [Int](), count: allRules.count)
        var sizes = Array(repeating: Int64(0), count: allRules.count)
        var nested = Array(repeating: [Int: UInt64](), count: allRules.count)
        let snapshotsIndex = rules.count
        let unclassifiedIndex = rules.count + 1
        let index = { (id: String) in rules.firstIndex { $0.id == id }! }
        let appSupportIndex = index(appSupportID)
        let homeOtherIndex = index(homeOtherID)
        let macOSIndex = index(macOSVolumeID)

        /// owner は (種類, その種類に当たった上のノード)。
        func assign(_ node: Int, to rule: Int, owner: (rule: Int, node: Int)?) {
            let size = Int64(t.size[node])
            nodes[rule].append(node)
            sizes[rule] += size
            if let owner {
                sizes[owner.rule] -= size
                nested[owner.rule][owner.node, default: 0] += t.size[node]
            }
        }

        var components: [String] = []
        func walk(_ node: Int, owner: (rule: Int, node: Int)?) {
            let rel = components
            if Glob.matchesAny(excluded, rel) { return }
            // システムデータ以外の項目に入ったら、その中ではシステムデータの決まりを当てない。
            // たとえばアプリ補助データの中のキャッシュは、システム設定と同じくアプリケーションに数える。
            let systemContext = owner.map { allRules[$0.rule].area == .systemData } ?? true
            func allowed(_ i: Int) -> Bool { systemContext || rules[i].area != .systemData }
            let canExtend = rules.indices.contains { i in allowed(i) && rules[i].patterns.contains { Glob.canExtend($0[...], rel[...]) } }
            let inScope = Glob.matchesAnyPrefix(scope, rel)
            var current = owner
            let hit: Int? = systemContext && isAppSupport(rel, apps: apps) ? appSupportIndex
                : rules.indices.first { i in allowed(i) && rules[i].patterns.contains { Glob.full($0[...], rel[...]) } }
            if let hit {
                assign(node, to: hit, owner: owner)
                current = (hit, node)
            } else if owner == nil, rel.count == 3, rel[0] == "Users", !canExtend {
                assign(node, to: homeOtherIndex, owner: nil)
                return
            } else if owner == nil, inScope, !canExtend {
                assign(node, to: unclassifiedIndex, owner: nil)
                return
            }
            let mayFindApp = current.map { allRules[$0.rule].area == .systemData } ?? true
                && perAppParents.contains { Glob.canExtend($0[...], rel[...]) }
            guard t.isDirectory(node),
                  canExtend || mayFindApp
                    || (current == nil && !inScope && couldEnterScope(rel)) || (current == nil && inScope)
            else { return }
            for child in t.children(node) {
                if t.flags[child].contains(.synthetic) { continue }
                components.append(t.name(child))
                walk(child, owner: current)
                components.removeLast()
            }
        }

        func couldEnterScope(_ rel: [String]) -> Bool {
            (scope + [["Users", "*", "*"]]).contains { Glob.canExtend($0[...], rel[...]) }
        }

        for child in t.children(0) {
            if t.flags[child].contains(.synthetic) {
                // 「その他」はスナップショットなど、ファイルとして数えられなかった分。
                let name = t.name(child)
                if name == "その他" { assign(child, to: snapshotsIndex, owner: nil) }
                if macOSSyntheticNames.contains(name) { assign(child, to: macOSIndex, owner: nil) }
                continue
            }
            components = [t.name(child)]
            walk(child, owner: nil)
        }

        let groups = allRules.indices.compactMap { i -> Classification.Group? in
            guard !nodes[i].isEmpty, sizes[i] > 0 else { return nil }
            var group = Classification.Group(rule: allRules[i], nodes: [], size: UInt64(max(0, sizes[i])), nested: nested[i])
            group.nodes = nodes[i].sorted { group.ownSize(of: $0, in: t) > group.ownSize(of: $1, in: t) }
            return group
        }
        return Classification(groups: groups.sorted { $0.size > $1.size }, purgeable: purgeable)
    }
}

enum Glob {
    static func component(_ pattern: String, _ name: String) -> Bool {
        if pattern == "*" { return true }
        if pattern == ".*" { return name.hasPrefix(".") }
        if pattern.hasPrefix("*.") { return name.hasSuffix(pattern.dropFirst()) }
        return pattern == name
    }

    /// パターン全体がパスに一致するか。
    static func full(_ p: ArraySlice<String>, _ r: ArraySlice<String>) -> Bool {
        guard let first = p.first else { return r.isEmpty }
        if first == "**" {
            if full(p.dropFirst(), r) { return true }
            return !r.isEmpty && full(p, r.dropFirst())
        }
        guard let head = r.first, component(first, head) else { return false }
        return full(p.dropFirst(), r.dropFirst())
    }

    /// パスの下に、パターンに一致する場所がありうるか（パス自体は含まない）。
    static func canExtend(_ p: ArraySlice<String>, _ r: ArraySlice<String>) -> Bool {
        guard let first = p.first else { return false }
        if first == "**" { return true }
        guard let head = r.first else { return true }
        guard component(first, head) else { return false }
        return canExtend(p.dropFirst(), r.dropFirst())
    }

    static func matchesAny(_ patterns: [[String]], _ rel: [String]) -> Bool {
        patterns.contains { full($0[...], rel[...]) }
    }

    /// パスがどれかのパターンの下（一致を含む）にあるか。
    static func matchesAnyPrefix(_ patterns: [[String]], _ rel: [String]) -> Bool {
        patterns.contains { p in p.count <= rel.count && full(p[...], rel.prefix(p.count)) }
    }
}
