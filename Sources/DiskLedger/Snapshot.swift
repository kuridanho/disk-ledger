import AppKit

/// 画面収録の許可なしに見た目を確かめるため、ウィンドウの中身を自分で PNG に描き出して終了する。
@MainActor
enum Snapshot {
    static func write(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView else {
            NSApp.terminate(nil)
            return
        }
        let bounds = view.bounds
        if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            view.cacheDisplay(in: bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}
