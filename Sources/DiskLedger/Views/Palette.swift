import AppKit
import LedgerCore
import SwiftUI

enum Palette {
    /// 強調に使う一色（落ち着いた紺青）。ダークモードでは見えるよう明るくする。
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.52, green: 0.66, blue: 0.88, alpha: 1)
            : NSColor(red: 0.16, green: 0.30, blue: 0.52, alpha: 1)
    })

    /// 判断の目安の文字色。赤はゴミ箱へ移す確認だけに取っておくので、ここでは使わない。
    static func color(for verdict: Verdict) -> Color {
        switch verdict {
        case .regenerable: Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.47, green: 0.74, blue: 0.62, alpha: 1)
                : NSColor(red: 0.20, green: 0.44, blue: 0.36, alpha: 1)
        })
        case .redownload, .reinstall: accent
        case .appData, .system, .unknown: .secondary
        case .irreplaceable: Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.86, green: 0.68, blue: 0.38, alpha: 1)
                : NSColor(red: 0.58, green: 0.40, blue: 0.12, alpha: 1)
        })
        }
    }
}
