import SwiftUI

/// 最初に出す、フルディスクアクセスを求める画面。許可されるまで走査は始めない。
struct PermissionView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.accent)
            VStack(spacing: 8) {
                Text("フルディスクアクセスを許可してください")
                    .font(.title2.weight(.semibold))
                Text("ディスク全体の容量を正しく数えるには、すべてのフォルダを読む許可が要ります。読むのはファイルの名前と大きさだけで、中身は開きません。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            }
            VStack(alignment: .leading, spacing: 10) {
                step(1, "システム設定の「フルディスクアクセス」を開く")
                step(2, "Disk Ledger をオンにする。一覧にない場合は「＋」から追加する")
                step(3, "Disk Ledger を開き直す")
            }
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 12) {
                Button("システム設定を開く") { model.openPrivacySettings() }
                    .keyboardShortcut(.defaultAction)
                Button("開き直す") { model.relaunch() }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.accent)
                .frame(width: 16)
            Text(text)
        }
    }
}
