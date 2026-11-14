import Foundation

/// 消してよいかを判断するための目安。
public enum Verdict: String, Sendable, CaseIterable {
    case regenerable = "消しても作り直される"
    case redownload = "再ダウンロードが必要"
    case reinstall = "入れ直せる"
    case appData = "アプリのデータ"
    case system = "macOS が管理"
    case irreplaceable = "消すと戻せない"
    case unknown = "中身を見て判断"
}

/// システム設定で「システムデータ」にまとめられるものを、場所の決まりで種類に分ける。
/// パターンはデータボリュームの根からの相対パスで、~ は Users/*、* は任意の一階層、** は任意の深さ、.* は . で始まる名前。
/// 深い場所に当たる決まりほど優先する。たとえばアプリの補助データの中のキャッシュは、キャッシュとして数える。
public struct CategoryRule: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let verdict: Verdict
    public let summary: String
    let patterns: [[String]]

    init(_ id: String, _ name: String, _ verdict: Verdict, _ summary: String, _ patterns: [String]) {
        self.id = id
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

    public static let rules: [CategoryRule] = [
        .init("caches", "キャッシュ", .regenerable,
              "アプリや macOS が、次に速く動くために取っておいたデータです。消しても必要に応じて作り直されますが、直後はアプリの起動や表示が遅くなることがあります。",
              ["~/Library/Caches", "Library/Caches", "System/Library/Caches",
               "~/Library/Containers/*/Data/Library/Caches",
               "~/Library/Application Support/**/Cache", "~/Library/Application Support/**/Caches",
               "~/Library/Application Support/**/Code Cache", "~/Library/Application Support/**/GPUCache",
               "~/Library/Application Support/**/CacheStorage", "~/Library/Application Support/**/ShaderCache"]),
        .init("logs", "ログと診断の記録", .regenerable,
              "アプリや macOS の動作の記録です。不具合を調べるとき以外は使いません。macOS が古いものから整理します。",
              ["~/Library/Logs", "Library/Logs", "private/var/log", "private/var/logs",
               "private/var/db/diagnostics", "private/var/db/uuidtext", "cores"]),
        .init("temporary", "一時ファイル", .system,
              "アプリが作業中に使うファイルです。macOS が再起動のときや定期的に片づけます。手で消すと動作中のアプリが困ることがあります。",
              ["private/var/folders", "private/tmp", "private/var/tmp"]),
        .init("vm", "仮想メモリとスリープイメージ", .system,
              "メモリが足りないときやスリープのときに macOS が使う領域です。",
              ["private/var/vm"]),
        .init("macos-data", "macOS の追加データ", .system,
              "Apple Intelligence のモデル、辞書、音声、フォントなど、macOS が後から取り込んだデータです。macOS が管理しており、手では消せません。",
              ["System"]),
        .init("updates", "macOS のアップデート", .system,
              "ダウンロード済みで、まだ入れていないアップデートです。入れ終わると消えます。",
              ["Library/Updates"]),
        .init("spotlight", "検索の索引", .regenerable,
              "Spotlight の検索のための索引です。消しても作り直されますが、その間は検索が不完全になります。",
              [".Spotlight-V100", "private/var/db/Spotlight-V100", "~/Library/Metadata/CoreSpotlight"]),
        .init("xcode-build", "Xcode のビルドと端末のサポート", .regenerable,
              "Xcode がビルドの途中結果と、つないだ iPhone などのための記号情報を置く場所です。消しても次のビルドや接続で作り直されます。",
              ["~/Library/Developer/Xcode/DerivedData", "~/Library/Developer/Xcode/iOS DeviceSupport",
               "~/Library/Developer/Xcode/macOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport",
               "~/Library/Developer/Xcode/tvOS DeviceSupport", "~/Library/Developer/Xcode/visionOS DeviceSupport"]),
        .init("simulators", "シミュレータ", .redownload,
              "iOS などのシミュレータの本体と、その中の端末のデータです。使わない OS の版は Xcode の設定から消せます。",
              ["~/Library/Developer/CoreSimulator", "Library/Developer/CoreSimulator",
               "System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime",
               "System/Library/AssetsV2/com_apple_MobileAsset_watchOSSimulatorRuntime",
               "System/Library/AssetsV2/com_apple_MobileAsset_tvOSSimulatorRuntime",
               "System/Library/AssetsV2/com_apple_MobileAsset_xrOSSimulatorRuntime",
               "System/Library/AssetsV2/com_apple_MobileAsset_visionOSSimulatorRuntime"]),
        .init("dev-cache", "開発ツールのキャッシュ", .regenerable,
              "npm、pip、Gradle、Cargo などがダウンロードした部品の控えです。消しても次に必要になったときに取り直されます。",
              ["~/.npm", "~/.cache", "~/.gradle", "~/.m2", "~/.pnpm-store", "~/Library/pnpm", "~/.yarn",
               "~/.cargo/registry", "~/.bun/install/cache", "~/Library/org.swift.swiftpm", "~/.swiftpm",
               "~/go/pkg", "~/.go/pkg"]),
        .init("dev-tools", "開発ツール", .reinstall,
              "Homebrew、Command Line Tools、言語の処理系など、入れた開発ツールの本体です。消すとそれを使うものが動かなくなります。",
              ["Library/Developer", "~/Library/Developer", "opt", "usr/local",
               "~/.rustup", "~/.cargo", "~/.pyenv", "~/.nvm", "~/.volta", "~/.bun", "~/.deno", "~/.local",
               "~/go", "~/.go", "~/.gem", "~/.rbenv", "~/.sdkman", "~/.zprezto", "~/.oh-my-zsh",
               "System/Library/AssetsV2/com_apple_MobileAsset_AppleDeveloperDocumentation"]),
        .init("ai-models", "ローカル AI のモデル", .redownload,
              "LM Studio、Ollama、Hugging Face などで手元に落としたモデルです。消すと使うときにまたダウンロードが必要です。",
              ["~/.lmstudio", "~/.ollama", "~/.cache/huggingface", "~/.cache/lm-studio"]),
        .init("vms", "仮想マシンのディスク", .appData,
              "Docker や Claude などが使う仮想マシンのディスクです。中の環境ごと消えるので、使っていないものだけを対象にします。",
              ["~/Library/Containers/com.docker.docker", "~/Library/Group Containers/*.com.docker",
               "~/Library/Application Support/Claude/vm_bundles", "~/Library/Containers/com.utmapp.UTM",
               "~/.colima", "~/.orbstack"]),
        .init("device-backups", "iPhone と iPad のバックアップ", .irreplaceable,
              "Finder で取った iPhone などのバックアップです。消すとその時点の状態には戻せません。古い端末のものは、Finder の端末の画面から消せます。",
              ["~/Library/Application Support/MobileSync/Backup"]),
        .init("audio", "音源とプラグイン", .redownload,
              "音楽アプリの音源やプラグインです。多くは配布元のアプリからまた入れられます。",
              ["~/Library/Audio", "Library/Audio", "~/Library/Application Support/Muse Hub",
               "~/Library/Application Support/MuseSampler", "Library/Application Support/Muse Hub",
               "~/Library/Application Support/Native Instruments", "Library/Application Support/Native Instruments",
               "~/Library/Application Support/Spitfire Audio", "Library/Application Support/Spitfire Audio",
               "~/Library/Application Support/Logic", "Library/Application Support/Logic",
               "~/Library/Application Support/GarageBand", "Library/Application Support/GarageBand"]),
        .init("macos-internal", "macOS の内部データ", .system,
              "macOS が学習、同期、セキュリティ、更新の管理のために持っているデータです。キーチェーンもここに入ります。macOS が管理しており、手で消すと不具合の元になります。",
              ["private", ".fseventsd", ".DocumentRevisions-V100", ".PreviousSystemInformation", ".MobileBackups",
               "~/Library/Biome", "~/Library/DuetExpertCenter", "~/Library/IntelligencePlatform", "~/Library/Trial",
               "~/Library/PersonalizationPortrait", "~/Library/Suggestions", "~/Library/IdentityServices",
               "~/Library/Keychains", "~/Library/Daemon Containers", "~/Library/Metadata", "~/Library/Assistant",
               "~/Library/Accounts", "~/Library/Sharing", "~/Library/StatusKit", "~/Library/AppleMediaServices",
               "Library/Apple", "Library/Keychains", "Library/SystemMigration", "Library/Trial"]),
        .init("app-data", "アプリの補助データ", .appData,
              "アプリが設定や作業中のデータを置く場所です。アプリを消しても残ることがあり、使わなくなったアプリのものは消して構いません。行を開くと、どのアプリのものかが分かります。",
              ["~/Library/Application Support", "~/Library/Containers", "~/Library/Group Containers",
               "Library/Application Support", "~/Library/WebKit", "~/Library/HTTPStorages",
               "~/Library/Preferences", "~/Library/Saved Application State", "Library/Preferences",
               // 上のどれにも当たらない ~/Library や /Library の直下と、ホームの隠しフォルダは、ほぼアプリや道具の置き場。
               "~/Library/*", "Library/*", "~/.*"]),
    ]

    public static let snapshotsRule = CategoryRule(
        snapshotsID, "スナップショットと読めない場所", .system,
        "ボリュームの使用量のうち、ファイルとして数えられなかった分です。Time Machine のローカルスナップショット、管理者だけが読める場所、消したのにまだスナップショットが持っているファイルなどが含まれます。スナップショットは空きが減ると macOS が自動で消します。",
        [])

    public static let unclassifiedRule = CategoryRule(
        unclassifiedID, "分類できなかったデータ", .unknown,
        "システムデータに含まれるものの、どの種類にも当てはまらなかった場所です。中を開いて、何のアプリのものかを確かめてください。",
        [])

    /// システムデータとして数える範囲。ここに入らないもの（アプリ、書類、写真など）は数えない。
    static let scope: [[String]] = [
        ["Users", "*", "Library"], ["Users", "*", ".*"], ["Library"], ["private"], ["System"],
        ["usr"], ["opt"], [".*"], ["cores"],
    ]

    /// システム設定で別の項目として出るもの。
    static let excluded: [[String]] = [
        ["Users", "*", "Library", "Mail"], ["Users", "*", "Library", "Messages"],
        ["Users", "*", "Library", "Mobile Documents"], ["Users", "*", "Library", "CloudStorage"],
        ["Users", "*", ".Trash"], ["Applications"], ["Volumes"],
    ]
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

    public var groups: [Group]
    public var total: UInt64 { groups.reduce(0) { $0 + $1.size } }
}

extension Categories {
    public static func classify(_ t: TreeStorage) -> Classification {
        let allRules = rules + [snapshotsRule, unclassifiedRule]
        var nodes = Array(repeating: [Int](), count: allRules.count)
        var sizes = Array(repeating: Int64(0), count: allRules.count)
        var nested = Array(repeating: [Int: UInt64](), count: allRules.count)
        let snapshotsIndex = rules.count
        let unclassifiedIndex = rules.count + 1

        /// owner は (種類, その種類に当たった上のノード)。
        func assign(_ node: Int, to rule: Int, owner: (rule: Int, node: Int)?) {
            nodes[rule].append(node)
            sizes[rule] += Int64(t.size[node])
            if let owner {
                sizes[owner.rule] -= Int64(t.size[node])
                nested[owner.rule][owner.node, default: 0] += t.size[node]
            }
        }

        var components: [String] = []
        func walk(_ node: Int, owner: (rule: Int, node: Int)?) {
            let rel = components
            if Glob.matchesAny(excluded, rel) { return }
            let inScope = Glob.matchesAnyPrefix(scope, rel)
            var current = owner
            if let hit = rules.indices.first(where: { i in rules[i].patterns.contains { Glob.full($0[...], rel[...]) } }) {
                assign(node, to: hit, owner: owner)
                current = (hit, node)
            } else if owner == nil, inScope, !t.flags[node].contains(.synthetic),
                      !rules.contains(where: { $0.patterns.contains { Glob.canExtend($0[...], rel[...]) } }) {
                assign(node, to: unclassifiedIndex, owner: nil)
                return
            }
            guard t.isDirectory(node),
                  rules.contains(where: { $0.patterns.contains { Glob.canExtend($0[...], rel[...]) } })
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
            scope.contains { Glob.canExtend($0[...], rel[...]) }
        }

        for child in t.children(0) {
            if t.flags[child].contains(.synthetic) {
                // 「その他」はスナップショットなど。「macOS 本体」はシステム設定でも別に出るので数えない。
                if t.name(child) == "その他" { assign(child, to: snapshotsIndex, owner: nil) }
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
        return Classification(groups: groups.sorted { $0.size > $1.size })
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
