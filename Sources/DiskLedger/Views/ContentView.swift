import LedgerCore
import SwiftUI

struct ContentView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        Group {
            if model.phase == .needsPermission {
                PermissionView()
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    HSplitView {
                        SunburstView()
                            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        ItemTable()
                            .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Divider()
                    footer
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.focusParent() } label: { Label("一つ上へ", systemImage: "chevron.left") }
                    .disabled(model.focus == 0 || model.phase == .needsPermission)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.startScan() } label: { Label("読み直す", systemImage: "arrow.clockwise") }
                    .disabled(!model.canScan)
                    .help("ディスクを読み直す")
            }
        }
    }

    /// いま見ている場所までの道筋。
    private var header: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button(item.name) { model.focus(on: item.node) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == model.breadcrumb.count - 1 ? .primary : .secondary)
                    .fontWeight(index == model.breadcrumb.count - 1 ? .semibold : .regular)
            }
            Spacer()
            Text(Format.bytes(model.focusSize))
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .scanning:
                ProgressView().controlSize(.small)
                Text("\(Format.count(model.progress.files)) 件・\(Format.bytes(model.progress.bytes))")
                    .monospacedDigit()
                Text(displayPath(model.progress.currentPath))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            case .done:
                Text("\(Format.count(model.progress.files)) 件を \(model.progress.elapsed.formatted(.number.precision(.fractionLength(1)))) 秒で読みました")
                    .monospacedDigit()
                if let volume = model.volume, volume.capacity > 0 {
                    Text("空き \(Format.bytes(volume.available))／\(Format.bytes(volume.capacity))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if model.unreadableCount > 0 {
                    Label("読めなかったフォルダ \(Format.count(model.unreadableCount))", systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .help("管理者だけが読める場所などです。これらの容量は「その他」に含まれます。")
                }
            default:
                EmptyView()
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    private func displayPath(_ path: String) -> String {
        path.hasPrefix(VolumeInfo.dataVolumePath + "/") ? String(path.dropFirst(VolumeInfo.dataVolumePath.count)) : path
    }
}
