import LedgerCore
import SwiftUI

struct ContentView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        Group {
            if model.phase == .needsPermission {
                PermissionView()
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                } detail: {
                    VStack(spacing: 0) {
                        if model.phase == .done {
                            DetailHeader()
                            Divider()
                            ItemTable()
                        } else {
                            ScanningView()
                        }
                        Divider()
                        FooterView()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.goUp() } label: { Label("上位階層へ", systemImage: "chevron.left") }
                    .disabled(model.path.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.startScan() } label: { Label("再走査", systemImage: "arrow.clockwise") }
                    .disabled(!model.canScan)
                    .help("ディスクを再走査")
            }
        }
    }
}

/// 左の一覧。システムデータの合計と、種類を容量の大きい順に並べる。
struct SidebarView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            if let classification = model.classification {
                SummaryBlock(classification: classification)
                    .listRowSeparator(.hidden)
                Section("内訳") {
                    ForEach(classification.groups) { group in
                        CategoryRow(group: group)
                            .tag(SidebarItem.category(group.id))
                    }
                }
            }
            Section("表示") {
                Label("フォルダ階層", systemImage: "folder")
                    .tag(SidebarItem.allFolders)
            }
        }
        .listStyle(.sidebar)
    }
}

/// 一覧の先頭。システム設定の数え方に近づけた合計と、除外した分。
struct SummaryBlock: View {
    var classification: Classification

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("システムデータ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.bytes(classification.settingsTotal))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            let excluded = [("パージ可能", classification.purgeable)]
                + SettingsBucket.allCases.map { ($0.rawValue, classification.elsewhere[$0] ?? 0) }
            if excluded.contains(where: { $0.1 > 0 }) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                    ForEach(excluded.filter { $0.1 > 0 }, id: \.0) { label, size in
                        GridRow {
                            Text(label)
                            Text(Format.bytes(size))
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("システム設定のシステムデータに含まれないため、合計から除外")
            }
        }
        .padding(.vertical, 6)
    }
}

/// 判断の目安の札。
struct VerdictTag: View {
    var verdict: Verdict

    var body: some View {
        let color = Palette.color(for: verdict)
        Text(verdict.rawValue)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct CategoryRow: View {
    var group: Classification.Group

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.rule.name).lineLimit(1)
                VerdictTag(verdict: group.rule.verdict)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.bytes(group.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                ForEach(group.elsewhere.sorted { $0.value > $1.value }, id: \.key) { bucket, size in
                    Text("\(bucket.rawValue) \(Format.bytes(size))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// 右側の見出し。種類の名前と容量、判断の目安、説明。
struct DetailHeader: View {
    @Environment(LedgerModel.self) private var model
    @State private var showsInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(Format.bytes(model.listSize))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            if let group = model.selectedGroup {
                HStack(spacing: 8) {
                    VerdictTag(verdict: group.rule.verdict)
                    ForEach(group.elsewhere.sorted { $0.value > $1.value }, id: \.key) { bucket, size in
                        Text("うち\(bucket.rawValue) \(Format.bytes(size))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Button { showsInfo.toggle() } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("説明")
                        .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
                            Text(group.rule.summary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 320)
                                .padding(14)
                        }
                }
            }
            if !model.path.isEmpty {
                HStack(spacing: 4) {
                    Button(model.title) { model.goBack(to: -1) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    ForEach(model.breadcrumb, id: \.index) { item in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Button(item.name) { model.goBack(to: item.index) }
                            .buttonStyle(.plain)
                            .foregroundStyle(item.index == model.path.count - 1 ? .primary : .secondary)
                    }
                }
                .lineLimit(1)
                .font(.callout)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

struct ScanningView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("走査中")
                .font(.headline)
            Text("\(Format.count(model.progress.files)) 件・\(Format.bytes(model.progress.bytes))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FooterView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .scanning:
                Text(displayPath(model.progress.currentPath))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            case .done:
                Text("\(Format.count(model.progress.files)) 件・\(model.progress.elapsed.formatted(.number.precision(.fractionLength(1)))) 秒で走査完了")
                    .monospacedDigit()
                if let volume = model.volume, volume.capacity > 0 {
                    Text("空き \(Format.bytes(volume.available))／\(Format.bytes(volume.capacity))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
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
