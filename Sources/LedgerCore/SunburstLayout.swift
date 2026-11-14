import Foundation

/// 円形の階層図の扇の並び。角度はラジアンで、真上から時計回りに測る。
public struct SunburstArc: Sendable, Equatable {
    /// 木のノード番号。小さな項目をまとめた扇では nil。
    public var node: Int?
    /// 1 が中心のすぐ外側の輪。
    public var depth: Int
    public var start: Double
    public var end: Double
    /// 中心の直下のどの枝に属するか。色分けに使う。
    public var branch: Int
    public var size: UInt64
}

public enum SunburstLayout {
    /// center を中心に maxDepth 段の扇を並べる。minAngle より小さい項目は、兄弟ごとに一つの扇にまとめる。
    public static func arcs(in tree: TreeStorage, center: Int, maxDepth: Int = 5, minAngle: Double = 0.012) -> [SunburstArc] {
        var result: [SunburstArc] = []
        let total = tree.size[center]
        guard total > 0, tree.count > center else { return result }

        func place(_ node: Int, depth: Int, start: Double, span: Double, branch: Int) {
            guard depth <= maxDepth, tree.isDirectory(node), tree.childCount[node] > 0 else { return }
            let nodeSize = Double(tree.size[node])
            guard nodeSize > 0 else { return }
            var angle = start
            var restSize: UInt64 = 0
            for (order, child) in tree.sortedChildren(node).enumerated() {
                let childSize = tree.size[child]
                if childSize == 0 { break }
                let childSpan = span * Double(childSize) / nodeSize
                if childSpan < minAngle {
                    restSize &+= childSize
                    continue
                }
                let childBranch = depth == 1 ? order : branch
                result.append(SunburstArc(node: child, depth: depth, start: angle, end: angle + childSpan,
                                          branch: childBranch, size: childSize))
                place(child, depth: depth + 1, start: angle, span: childSpan, branch: childBranch)
                angle += childSpan
            }
            let restSpan = span * Double(restSize) / nodeSize
            if restSpan >= minAngle {
                result.append(SunburstArc(node: nil, depth: depth, start: angle, end: angle + restSpan,
                                          branch: depth == 1 ? -1 : branch, size: restSize))
            }
        }

        place(center, depth: 1, start: 0, span: 2 * .pi, branch: 0)
        return result
    }
}
