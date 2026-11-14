import LedgerCore
import SwiftUI

/// 円形の階層図。中心がいま見ているフォルダで、外へ向かって階層が深くなる。
struct SunburstView: View {
    @Environment(LedgerModel.self) private var model
    private let maxDepth = 5

    var body: some View {
        GeometryReader { proxy in
            let geometry = Geometry(size: proxy.size, maxDepth: maxDepth)
            let synthetic = syntheticNodes()
            ZStack {
                Canvas { context, _ in
                    for arc in model.arcs {
                        let path = geometry.path(for: arc)
                        context.fill(path, with: .color(Palette.color(for: arc, synthetic: arc.node.map(synthetic.contains) ?? false)))
                        context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1)
                    }
                    for node in [model.hovered, model.selection].compactMap({ $0 }) {
                        if let arc = model.arcs.first(where: { $0.node == node }) {
                            context.stroke(geometry.path(for: arc), with: .color(.primary.opacity(0.85)), lineWidth: 2)
                        }
                    }
                }
                centerLabel
                    .frame(width: geometry.innerRadius * 1.7)
                    .position(geometry.center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): model.hovered = geometry.arc(at: point, in: model.arcs)?.node
                case .ended: model.hovered = nil
                }
            }
            .onTapGesture { point in
                if geometry.isInCenter(point) {
                    model.focusParent()
                } else if let node = geometry.arc(at: point, in: model.arcs)?.node {
                    model.open(node)
                }
            }
        }
        .padding(16)
    }

    private func syntheticNodes() -> Set<Int> {
        guard let tree = model.tree else { return [] }
        return tree.read { t in Set(t.children(model.focus).filter { t.flags[$0].contains(.synthetic) }) }
    }

    private var centerLabel: some View {
        let node = model.hovered ?? model.focus
        let size = model.hovered.map(model.size(of:)) ?? model.focusSize
        return VStack(spacing: 4) {
            Text(model.name(of: node))
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(Format.bytes(size))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            if model.hovered == nil, model.focus != 0 {
                Text("中心を押すと一つ上へ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 角度は真上から時計回りに測る。画面の y は下向き。
    struct Geometry {
        var center: CGPoint
        var radius: CGFloat
        var innerRadius: CGFloat
        var ringWidth: CGFloat

        init(size: CGSize, maxDepth: Int) {
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            radius = max(10, min(size.width, size.height) / 2)
            innerRadius = radius * 0.27
            ringWidth = (radius - innerRadius) / CGFloat(maxDepth)
        }

        func path(for arc: SunburstArc) -> Path {
            let inner = innerRadius + CGFloat(arc.depth - 1) * ringWidth + 1
            let outer = inner + ringWidth - 1
            let start = Angle(radians: arc.start - .pi / 2)
            let end = Angle(radians: arc.end - .pi / 2)
            var path = Path()
            path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
            path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
            path.closeSubpath()
            return path
        }

        func isInCenter(_ point: CGPoint) -> Bool {
            hypot(point.x - center.x, point.y - center.y) < innerRadius
        }

        func arc(at point: CGPoint, in arcs: [SunburstArc]) -> SunburstArc? {
            let dx = point.x - center.x, dy = point.y - center.y
            let distance = hypot(dx, dy)
            guard distance >= innerRadius, distance <= radius else { return nil }
            let depth = Int((distance - innerRadius) / ringWidth) + 1
            var angle = atan2(dy, dx) + .pi / 2
            if angle < 0 { angle += 2 * .pi }
            return arcs.first { $0.depth == depth && $0.start <= angle && angle < $0.end }
        }
    }
}
