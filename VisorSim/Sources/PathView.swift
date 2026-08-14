import SwiftUI
import Transport

/// The road, drawn from the path packet and nothing else.
///
/// Nothing here knows where north is, what the route was, or where on earth any
/// of this happened. It is handed a list of offsets in decimeters and draws
/// them, which is exactly the position the firmware will be in.
///
/// Two things keep it from lurching once a second, and both belong on this side
/// of the link rather than the phone's.
///
/// The frame is fixed: a set number of meters of road fills the panel and the
/// rider sits at a set place in it, always. Sizing the drawing to fit whatever
/// happened to arrive means every packet that reaches a little further redraws
/// the world at a new scale, which reads as violent motion where there was
/// none.
///
/// And the road is moved between packets rather than replaced by them. The
/// phone sends the truth once a second; making that look like motion is the
/// display's job, because only the display knows its own frame rate. The cost
/// is that the picture trails the truth by up to one packet, which for a map is
/// nothing — and the distance to the turn, the number a rider acts on, comes
/// from the other packet and is never smoothed.
struct PathView: View {
    let feed: PeripheralServer.PathFeed
    let isOffRoute: Bool

    /// How much road the panel holds. Fixed, so the scale never moves.
    private let metersAhead = 300.0
    private let metersBehind = 60.0

    /// Points to redraw the road with. Both packets are resampled to the same
    /// count so they can be crossed between; the wire's own points are
    /// unevenly spaced and there is no sensible pairing otherwise.
    private let samples = 64

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.04))

            if let latest = feed.latest, latest.points.count > 1 {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(at: timeline.date, in: &context, size: size)
                    }
                }
                .padding(12)

                caption(latest)
                    .padding(10)
            } else {
                Text("No road yet")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var tint: Color { isOffRoute ? .red : .cyan }

    private func caption(_ path: DecodedPath) -> some View {
        // Read back out of the packet, so a road drawn from four points does
        // not get to look like one drawn from forty however smoothly it moves.
        let ahead = (path.points.map(\.ahead).max() ?? 0) / 10
        return Text("\(path.points.count) points · \(ahead) m ahead")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    // MARK: - Drawing

    private func draw(at date: Date, in context: inout GraphicsContext, size: CGSize) {
        guard let latest = feed.latest else { return }

        let crossing = crossing(at: date)
        let current = resample(meters(latest))
        let earlier = feed.previous.map { resample(meters($0)) } ?? current
        let road = zip(earlier, current).map { between($0, $1, crossing) }

        let scale = size.height / (metersAhead + metersBehind)
        let riderY = size.height * metersAhead / (metersAhead + metersBehind)

        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: size.width / 2 + point.x * scale, y: riderY - point.y * scale)
        }

        var line = Path()
        line.addLines(road.map(place))
        context.stroke(
            line,
            with: .color(tint),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )

        if let junction = junction(at: crossing) {
            let at = place(junction)
            context.fill(dot(at: at, radius: 8), with: .color(.white))
            context.fill(dot(at: at, radius: 4.5), with: .color(tint))
        }

        // The rider never moves. That is the whole point of a fixed frame: the
        // road flows past a still rider, the way it does through a visor.
        let rider = CGPoint(x: size.width / 2, y: riderY)
        var arrow = Path()
        arrow.move(to: CGPoint(x: rider.x, y: rider.y - 9))
        arrow.addLine(to: CGPoint(x: rider.x - 7, y: rider.y + 7))
        arrow.addLine(to: CGPoint(x: rider.x + 7, y: rider.y + 7))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(.white))
    }

    /// How far between the previous road and the newest one to draw, `0` to `1`.
    private func crossing(at date: Date) -> Double {
        guard let arrivedAt = feed.arrivedAt else { return 1 }
        let elapsed = date.timeIntervalSince(arrivedAt)
        return min(1, max(0, elapsed / max(0.1, feed.interval)))
    }

    /// Where to draw the junction marker, crossed between packets like the road.
    private func junction(at crossing: Double) -> CGPoint? {
        guard let now = feed.latest.flatMap(marker) else { return nil }
        guard let before = feed.previous.flatMap(marker) else { return now }

        // A junction that has moved this far is not the same junction: the last
        // one has been ridden through and this is the next one, several hundred
        // meters on. Sliding the marker up the road would be a lie about a turn.
        guard hypot(now.x - before.x, now.y - before.y) < 100 else { return now }
        return between(before, now, crossing)
    }

    private func marker(_ path: DecodedPath) -> CGPoint? {
        guard let index = path.maneuverIndex, path.points.indices.contains(index) else { return nil }
        return meters(path)[index]
    }

    private func meters(_ path: DecodedPath) -> [CGPoint] {
        path.points.map { CGPoint(x: Double($0.right) / 10, y: Double($0.ahead) / 10) }
    }

    // MARK: - Points

    /// The same road as `samples` points spread evenly along its length.
    private func resample(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 1 else {
            return Array(repeating: points.first ?? .zero, count: samples)
        }

        var travelled = [0.0]
        for index in 1..<points.count {
            let step = hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            travelled.append(travelled[index - 1] + step)
        }

        guard let total = travelled.last, total > 0 else {
            return Array(repeating: points[0], count: samples)
        }

        var spread: [CGPoint] = []
        spread.reserveCapacity(samples)
        var segment = 1

        for step in 0..<samples {
            let target = total * Double(step) / Double(samples - 1)
            while segment < points.count - 1, travelled[segment] < target { segment += 1 }

            let span = travelled[segment] - travelled[segment - 1]
            let fraction = span > 0 ? (target - travelled[segment - 1]) / span : 0
            spread.append(between(points[segment - 1], points[segment], fraction))
        }

        return spread
    }

    private func between(_ a: CGPoint, _ b: CGPoint, _ fraction: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
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
