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
                Button { model.goUp() } label: { Label("一つ上へ", systemImage: "chevron.left") }
                    .disabled(model.path.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.startScan() } label: { Label("読み直す", systemImage: "arrow.clockwise") }
                    .disabled(!model.canScan)
                    .help("ディスクを読み直す")
            }
        }
    }
}

/// 左の一覧。システムデータの種類を容量の大きい順に並べる。
struct SidebarView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            if let classification = model.classification {
                Section {
                    ForEach(classification.groups) { group in
                        CategoryRow(group: group)
                            .tag(SidebarItem.category(group.id))
                    }
                } header: {
                    HStack {
                        Text("システムデータ")
                        Spacer()
                        Text(Format.bytes(classification.total)).monospacedDigit()
                    }
                }
            }
            Section("ほかの見方") {
                Label("フォルダで見る", systemImage: "folder")
                    .tag(SidebarItem.allFolders)
            }
        }
        .listStyle(.sidebar)
    }
}

struct CategoryRow: View {
    var group: Classification.Group

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.rule.name).lineLimit(1)
                Spacer(minLength: 8)
                Text(Format.bytes(group.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(group.rule.verdict.rawValue)
                .font(.caption)
                .foregroundStyle(Palette.color(for: group.rule.verdict))
        }
        .padding(.vertical, 2)
    }
}

/// 右側の見出し。種類の名前、容量、判断の目安と、その説明。
struct DetailHeader: View {
    @Environment(LedgerModel.self) private var model
    @State private var showsInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.title)
                    .font(.title2.weight(.semibold))
                if let group = model.selectedGroup {
                    Text(group.rule.verdict.rawValue)
                        .font(.callout)
                        .foregroundStyle(Palette.color(for: group.rule.verdict))
                    Button { showsInfo.toggle() } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless)
                        .help("この種類について")
                        .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
                            Text(group.rule.summary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 320)
                                .padding(14)
                        }
                }
                Spacer()
                Text(Format.bytes(model.listSize))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ScanningView: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("ディスクを読んでいます")
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
                Text("\(Format.count(model.progress.files)) 件を \(model.progress.elapsed.formatted(.number.precision(.fractionLength(1)))) 秒で読みました")
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
