import LedgerCore
import SwiftUI

/// 図の色。彩度を抑えた8色を、中心の直下の枝ごとに順に割り当てる。
/// 隣り合う色は明るさも変えてあるので、色の見分けにくい人でも境目が分かる。赤系は使わない。
enum Palette {
    static let branches: [Color] = [
        Color(red: 0.25, green: 0.40, blue: 0.62), // 紺青
        Color(red: 0.42, green: 0.62, blue: 0.60), // 青緑
        Color(red: 0.55, green: 0.50, blue: 0.70), // 藤
        Color(red: 0.74, green: 0.64, blue: 0.40), // 砂
        Color(red: 0.36, green: 0.52, blue: 0.40), // 深緑
        Color(red: 0.55, green: 0.68, blue: 0.82), // 空
        Color(red: 0.50, green: 0.44, blue: 0.38), // 灰茶
        Color(red: 0.62, green: 0.70, blue: 0.48), // 若草
    ]

    /// 強調に使う一色。
    static let accent = Color(red: 0.16, green: 0.30, blue: 0.52)

    static let neutral = Color(white: 0.55)

    static func color(for arc: SunburstArc, synthetic: Bool) -> Color {
        let base: Color
        if arc.node == nil || arc.branch < 0 || synthetic {
            base = neutral
        } else {
            base = branches[arc.branch % branches.count]
        }
        // 外側の輪ほど薄くする。
        return base.opacity(max(0.38, 1 - 0.14 * Double(arc.depth - 1)))
    }

    static func color(forBranch branch: Int) -> Color {
        branch < 0 ? neutral : branches[branch % branches.count]
    }
}
