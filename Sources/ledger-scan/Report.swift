import Foundation
import LedgerCore

/// 書き出した走査結果から、分類の内訳と、確かめるべき箇所を文字で出す。
enum ClassificationReport {
    static func fmt(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    static func short(_ t: TreeStorage, _ i: Int) -> String {
        guard var p = t.path(i) else { return t.name(i) }
        if p.hasPrefix(VolumeInfo.dataVolumePath + "/") { p.removeFirst(VolumeInfo.dataVolumePath.count) }
        if let r = p.range(of: #"^/Users/[^/]+"#, options: .regularExpression) { p.replaceSubrange(r, with: "~") }
        return p
    }

    static func print(_ t: TreeStorage, volume: VolumeInfo?) {
        let out = { (s: String) in Swift.print(s) }
        if let v = volume {
            out("容量 \(fmt(v.capacity))  空き \(fmt(v.available))  データ使用 \(fmt(v.dataUsed))  システム使用 \(fmt(v.systemUsed))")
        }
        out("木の合計 \(fmt(t.size[0]))  ノード \(t.count)")
        for c in t.children(0) where t.flags[c].contains(.synthetic) { out("  \(t.name(c)) \(fmt(t.size[c]))") }

        // 古い書き出しにはパージ可能な量がないので、調べものでは環境変数で渡せるようにする。
        let purgeable = (volume?.purgeable).flatMap { $0 > 0 ? $0 : nil }
            ?? ProcessInfo.processInfo.environment["PURGEABLE"].flatMap(UInt64.init) ?? 0
        let c = Categories.classify(t, purgeable: purgeable, apps: .current())
        out("\n== 使用済み \(fmt(c.usedTotal))  パージ可能 \(fmt(c.purgeable)) を除く")
        for area in c.areas { out("  \(area.rawValue)  \(fmt(c.size(of: area)))") }
        for area in c.areas {
            out("\n# \(area.rawValue)  \(fmt(c.size(of: area)))")
            for g in c.groups(in: area) {
                out("\n## \(g.rule.name)  \(fmt(g.size))  (\(g.nodes.count) 箇所)")
                for n in g.nodes.prefix(g.rule.id == Categories.unclassifiedID ? 40 : 8) {
                    let own = g.ownSize(of: n, in: t)
                    guard own >= 1_000_000 else { continue }
                    out("  \(fmt(own).padding(toLength: 10, withPad: " ", startingAt: 0)) \(short(t, n))")
                }
            }
        }

        // 種類に入らなかった範囲のうち大きいもの（アプリ、書類など、システムデータに数えない場所）を確かめる。
        out("\n== 根の直下")
        for n in t.sortedChildren(0).prefix(20) { out("  \(fmt(t.size[n]).padding(toLength: 10, withPad: " ", startingAt: 0)) \(t.name(n))") }

        var unreadable: [Int] = []
        var permission: [Int] = []
        var dataless: UInt64 = 0
        var datalessCount = 0
        var mounts: [Int] = []
        for i in 0 ..< t.count {
            let f = t.flags[i]
            if f.contains(.unreadable) { unreadable.append(i) }
            if f.contains(.needsPermission) { permission.append(i) }
            if f.contains(.mountPoint) { mounts.append(i) }
            if f.contains(.dataless) { datalessCount += 1; dataless += t.size[i] }
        }
        out("\n== 読めなかったフォルダ \(unreadable.count) 件")
        for i in unreadable.prefix(80) { out("  \(short(t, i))") }
        out("\n== 許可がなく読まなかった場所 \(permission.count) 件")
        for i in permission.prefix(20) { out("  \(short(t, i))") }
        out("\n== 別のボリューム \(mounts.count) 件")
        for i in mounts.prefix(20) { out("  \(short(t, i))") }
        out("\n== iCloud のみの項目 \(datalessCount) 件")
    }

    /// 根からの相対パス（~ は自分のホーム）の中を大きい順に出す。
    static func listChildren(_ t: TreeStorage, path: String) {
        var parts = path.split(separator: "/").map(String.init)
        if parts.first == "~" { parts = ["Users", NSUserName()] + parts.dropFirst() }
        var node = 0
        for part in parts {
            guard let next = t.children(node).first(where: { t.name($0) == part }) else {
                Swift.print("見つかりません: \(path)"); return
            }
            node = next
        }
        Swift.print("\n# \(path)  \(fmt(t.size[node]))")
        for c in t.sortedChildren(node).prefix(25) where t.size[c] >= 50_000_000 {
            Swift.print("  \(fmt(t.size[c]).padding(toLength: 10, withPad: " ", startingAt: 0)) \(t.name(c))")
        }
    }

    static func find(_ t: TreeStorage, _ path: String) -> Int? {
        var parts = path.split(separator: "/").map(String.init)
        if parts.first == "~" { parts = ["Users", NSUserName()] + parts.dropFirst() }
        var node = 0
        for part in parts {
            guard let next = t.children(node).first(where: { t.name($0) == part }) else { return nil }
            node = next
        }
        return node
    }

    static func bigFiles(_ t: TreeStorage, path: String, min: UInt64) {
        guard let start = find(t, path) else { Swift.print("見つかりません"); return }
        var total: UInt64 = 0
        var stack = [start]
        while let n = stack.popLast() {
            if t.isDirectory(n) { stack.append(contentsOf: t.children(n)) } else if t.size[n] >= min { total += t.size[n] }
        }
        Swift.print("\(path) \(fmt(total))")
    }
}
