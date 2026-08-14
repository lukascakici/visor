import SwiftUI
import Transport

/// The road, drawn from the path packet and nothing else.
///
/// Nothing here knows where north is, what the route was, or where on earth any
/// of this happened. It is handed a list of offsets in decimeters and draws
/// them, which is exactly the position the firmware will be in.
struct PathView: View {
    let path: DecodedPath?
    let isOffRoute: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))

            if let path, path.points.count > 1 {
                Canvas { context, size in
                    draw(path, in: &context, size: size)
                }
                .padding(12)

                caption(path)
                    .padding(10)
            } else {
                Text("No road yet")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 210)
    }

    private var tint: Color { isOffRoute ? .red : .cyan }

    private func caption(_ path: DecodedPath) -> some View {
        // Both numbers are read back out of the packet, so a road drawn from
        // four points does not get to look like one drawn from forty.
        let ahead = (path.points.map(\.ahead).max() ?? 0) / 10
        return Text("\(path.points.count) points · \(ahead) m ahead")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private func draw(_ path: DecodedPath, in context: inout GraphicsContext, size: CGSize) {
        let road = path.points.map { CGPoint(x: Double($0.right) / 10, y: Double($0.ahead) / 10) }

        // The rider is at the origin and is never sent, so the origin has to be
        // folded into the bounds by hand or the rider ends up off the panel.
        var lower = CGPoint.zero
        var upper = CGPoint.zero
        for point in road {
            lower.x = min(lower.x, point.x)
            lower.y = min(lower.y, point.y)
            upper.x = max(upper.x, point.x)
            upper.y = max(upper.y, point.y)
        }

        // One scale for both axes. Stretching the picture to fill the panel
        // would turn a gentle bend into a hard one, which is the one thing a
        // map on a HUD must never do.
        let span = CGPoint(x: max(upper.x - lower.x, 1), y: max(upper.y - lower.y, 1))
        let scale = min(min(size.width / span.x, size.height / span.y), 4)
        let middle = CGPoint(x: (lower.x + upper.x) / 2, y: (lower.y + upper.y) / 2)

        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: size.width / 2 + (point.x - middle.x) * scale,
                // Flipped, because ahead is up the panel and down the pixels.
                y: size.height / 2 - (point.y - middle.y) * scale
            )
        }

        var line = Path()
        line.addLines(road.map(place))
        context.stroke(
            line,
            with: .color(tint),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )

        if let index = path.maneuverIndex, road.indices.contains(index) {
            let junction = place(road[index])
            context.fill(dot(at: junction, radius: 8), with: .color(.white))
            context.fill(dot(at: junction, radius: 4.5), with: .color(tint))
        }

        let rider = place(.zero)
        var arrow = Path()
        arrow.move(to: CGPoint(x: rider.x, y: rider.y - 9))
        arrow.addLine(to: CGPoint(x: rider.x - 7, y: rider.y + 7))
        arrow.addLine(to: CGPoint(x: rider.x + 7, y: rider.y + 7))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(.white))
    }

    private func dot(at centre: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(
            x: centre.x - radius,
            y: centre.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}
