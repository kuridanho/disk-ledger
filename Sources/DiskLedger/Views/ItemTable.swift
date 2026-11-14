import LedgerCore
import SwiftUI

/// いま中心にあるフォルダの中身を、大きい順に並べる。
struct ItemTable: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.rows, selection: $model.selection) {
            TableColumn("名前") { row in
                Label {
                    Text(row.name).lineLimit(1).truncationMode(.middle)
                } icon: {
                    Image(systemName: icon(for: row))
                        .foregroundStyle(row.isDirectory ? Palette.accent : .secondary)
                }
                .help(row.name)
            }
            .width(min: 140, ideal: 210)
            TableColumn("サイズ") { row in
                Group {
                    if let status = row.status, row.size == 0 {
                        Text(status).foregroundStyle(.secondary)
                    } else {
                        Text(Format.bytes(row.size)).monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72, ideal: 80, max: 110)
            TableColumn("割合") { row in
                ShareBar(share: row.share)
            }
            .width(min: 90, ideal: 110, max: 150)
            TableColumn("更新日") { row in
                Text(Format.date(row.modified))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 76, ideal: 84, max: 100)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            if let id = ids.first {
                Button("Finder に表示") { model.revealInFinder(id) }
                    .disabled(model.displayPath(of: id) == nil)
                Button("パスをコピー") { model.copyPath(id) }
                    .disabled(model.displayPath(of: id) == nil)
            }
        } primaryAction: { ids in
            if let id = ids.first { model.open(id) }
        }
    }

    private func icon(for row: ItemRow) -> String {
        if row.flags.contains(.synthetic) { return "internaldrive" }
        if row.flags.contains(.needsPermission) || row.flags.contains(.unreadable) { return "lock" }
        if row.flags.contains(.dataless) { return "icloud" }
        if row.flags.contains(.mountPoint) { return "externaldrive" }
        if row.flags.contains(.symlink) { return "arrow.turn.up.right" }
        return row.isDirectory ? "folder" : "doc"
    }
}

/// 割合の細い棒と数字。
struct ShareBar: View {
    var share: Double

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Palette.accent.opacity(0.75))
                        .frame(width: max(share > 0 ? 2 : 0, proxy.size.width * min(share, 1)))
                }
            }
            .frame(height: 4)
            Text(Format.percent(share))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
