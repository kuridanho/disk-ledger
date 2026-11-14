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
                Text("フルディスクアクセスが必要です")
                    .font(.title2.weight(.semibold))
                Text("ディスク全体を正確に集計するため、全フォルダの読取許可が必要です。読み取るのはファイル名と容量のみで、内容は開きません。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            }
            VStack(alignment: .leading, spacing: 10) {
                step(1, "システム設定の「フルディスクアクセス」を開く")
                step(2, "Disk Ledger を有効化する。一覧になければ「＋」で追加する")
                step(3, "Disk Ledger を再起動する")
            }
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 12) {
                Button("システム設定を開く") { model.openPrivacySettings() }
                    .keyboardShortcut(.defaultAction)
                Button("再起動") { model.relaunch() }
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
