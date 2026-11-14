import AppKit
import LedgerCore
import SwiftUI

@main
struct DiskLedgerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = LedgerModel(launch: LaunchOptions.current)

    var body: some Scene {
        Window("Disk Ledger", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 560)
                .task { model.startIfPossible() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshPermission()
                }
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button("読み直す") { model.startScan() }
                    .keyboardShortcut("r")
                    .disabled(!model.canScan)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // swift run で .app にせず起動したときも、普通のアプリとして前面に出す。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// 確認用の起動引数。
/// --scan-root <パス>  ディスク全体ではなく指定した場所だけを読む（許可の画面を飛ばす）
/// --snapshot <PNG>    読み終えたらウィンドウを PNG に描き出して終了する
/// --focus <名前>      読み終えたら根の直下のその項目を中心にする
/// --permission-screen 許可の画面を描き出すために、許可がない状態として扱う
/// --load <ファイル>   ディスクを読まず、--dump で書き出した結果を見せる
/// --dump <ファイル>   読み終えたら走査結果をファイルに書き出して終了する（ledger-scan --load で読める）
struct LaunchOptions {
    var scanRoot: String?
    var snapshotPath: String?
    var focusName: String?
    var forcePermissionScreen = false
    var dumpPath: String?
    var loadPath: String?

    static var current: LaunchOptions {
        let args = CommandLine.arguments
        func value(_ key: String) -> String? {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        return LaunchOptions(scanRoot: value("--scan-root"), snapshotPath: value("--snapshot"),
                             focusName: value("--focus"), forcePermissionScreen: args.contains("--permission-screen"),
                             dumpPath: value("--dump"), loadPath: value("--load"))
    }
}
