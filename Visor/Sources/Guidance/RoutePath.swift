import Core
import Foundation
import Geometry

/// The road around the rider, in meters, ready to be drawn.
///
/// The frame is the rider's own: the origin is where they are on the route, and
/// straight up is the way they are heading. A device drawing this needs no map,
/// no projection and no idea where north is. It draws what it is handed and the
/// picture comes out the right way round.
///
/// The rider is always at the origin, so the rider is never sent.
public struct RoutePath: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        /// Meters to the rider's right; negative is to the left.
        public let right: Double
        /// Meters in front of the rider; negative is behind.
        public let ahead: Double

        public init(right: Double, ahead: Double) {
            self.right = right
            self.ahead = ahead
        }
    }

    public let points: [Point]
    /// Which point the next maneuver happens at, when that junction falls
    /// inside the drawn stretch and there is room to mark it.
    ///
    /// Worth its byte: a line showing where the road goes, with nothing on it
    /// saying where the turn is, leaves the rider to guess which bend is theirs.
    public let maneuverIndex: Int?

    /// How far along `points` the rider is: `0` at the first, `1` at the last.
    ///
    /// Told rather than left to be worked out. A display can only guess at this
    /// by looking for the point nearest to itself, and on a sharp turn the road
    /// beyond the corner comes back past the rider and wins that comparison,
    /// which paints the road ahead as road already ridden. The phone knows the
    /// answer exactly and it costs one byte to say it.
    public let riderFraction: Double

    public init(points: [Point], maneuverIndex: Int?, riderFraction: Double = 0) {
        self.points = points
        self.maneuverIndex = maneuverIndex
        self.riderFraction = riderFraction
    }

    public static let empty = RoutePath(points: [], maneuverIndex: nil, riderFraction: 0)
}

extension RouteIndex {
    /// Shape finer than this is dropped before the budget is even looked at, in
    /// meters.
    ///
    /// Fitting a budget only cuts when the budget is exceeded, so without a
    /// floor a straight road under budget would be sent vertex by vertex, every
    /// one of them on the same line. At a meter, nothing is lost that a display
    /// a few centimeters wide could have drawn, or that GPS could have placed
    /// the rider to.
    static let detailFloor = 1.0

    /// How far ahead the frame reads the road to decide which way is up.
    ///
    /// This one number decides how steady the picture is. A road wanders by a
    /// meter or two as a matter of course, and over a short baseline that is
    /// degrees: three meters across twenty is eight degrees, and eight degrees
    /// swings the far end of the drawn road clear across the panel. Across
    /// eighty the same wander is two, and it takes several seconds to get
    /// there rather than arriving between one packet and the next.
    ///
    /// Spread either side of the rider, so it is forty metres each way.
    static let headingWindow = 80.0

    /// Which way the road runs at a point along the route, in compass degrees.
    ///
    /// Not the chord from here to there. A chord is decided entirely by its two
    /// ends, so a meter of wander at either one turns the whole map. This takes
    /// the direction from the near half of the window to the far half, which
    /// averages the wander out instead of being steered by it.
    public func heading(at travelled: Double) -> Double {
        let samples = 9
        let half = samples / 2

        // Centred on the rider rather than reaching out in front of them.
        // Looking only forward means that a whole window before a corner the
        // frame is already round it, and the map comes about while the rider is
        // still going straight; from behind the glass that is
        // indistinguishable from having turned early. Spread either side, the
        // turn lands on the corner: halfway round as the rider reaches it, and
        // finished as they leave.
        //
        // It costs nothing on a curve. A window centred on a constant bend
        // averages to the direction at its middle, so unlike a forward window
        // it neither leads nor lags.
        let window = Self.headingWindow
        let from = min(max(0, travelled - window / 2), max(0, length - window))
        guard let origin = Geo.coordinate(on: route.polyline, at: from) else { return 0 }

        // Degrees of longitude are shorter than degrees of latitude everywhere
        // but the equator, and a direction taken without correcting for that is
        // wrong by the same amount everywhere in Istanbul.
        let scale = cos(origin.latitude * .pi / 180)
        var near = (east: 0.0, north: 0.0)
        var far = (east: 0.0, north: 0.0)

        for step in 0..<samples {
            let along = from + window * Double(step) / Double(samples - 1)
            guard let point = Geo.coordinate(on: route.polyline, at: along) else { continue }

            let east = (point.longitude - origin.longitude) * scale
            let north = point.latitude - origin.latitude

            if step < half {
                near.east += east
                near.north += north
            } else if step >= samples - half {
                far.east += east
                far.north += north
            }
        }

        let east = (far.east - near.east) / Double(half)
        let north = (far.north - near.north) / Double(half)
        guard east * east + north * north > 0 else { return 0 }

        return Geo.normalizedBearing(atan2(east, north) * 180 / .pi)
    }

    /// The stretch of road around the rider, in the rider's own frame.
    ///
    /// `behind` is short on purpose. A line that only runs forward loses the
    /// sense of which way the rider came from, and a short tail restores it
    /// without spending bytes on road nobody is going to ride again.
    ///
    /// `ahead` is deliberately further than any display will draw. A road that
    /// stops inside the panel reads as a road that ends, or worse as a turn,
    /// and a rider cannot tell that from a road the packet simply ran out of.
    /// Sent long, the line always leaves the edge of the screen, and stopping
    /// short then means what it should: the destination is that close.
    ///
    /// It costs almost nothing. Detail below a meter is dropped before the
    /// budget is counted, so an extra half kilometre of ordinary road is a
    /// handful of points.
    ///
    /// `points` is the whole budget, junction marker included: whatever comes
    /// back fits in it.
    public func path(
        at progress: RouteProgress,
        behind: Double = 100,
        ahead: Double = 1000,
        points limit: Int = 40
    ) -> RoutePath {
        guard limit > 1, route.polyline.count > 1 else { return .empty }

        let from = max(0, progress.distanceTravelled - behind)
        let to = min(length, progress.distanceTravelled + ahead)
        guard to > from else { return .empty }

        let origin = progress.snapped
        let rotation = heading(at: progress.distanceTravelled)
        let maneuverAt = progress.distanceTravelled + progress.distanceToManeuver

        // Simplifying across the junction and simplifying up to it are two
        // different pictures: the first is free to round the corner off, the
        // second cannot. Cutting the line at the maneuver makes the junction a
        // vertex by construction rather than by luck, which is what lets its
        // index be reported at all.
        //
        // Below four points there is nothing to split; a line that short is
        // barely a line.
        let margin = 1.0
        guard limit >= 4, maneuverAt > from + margin, maneuverAt < to - margin else {
            let drawn = whole(from: from, to: to, toAtMost: limit, origin: origin, rotation: rotation)
            return RoutePath(
                points: drawn,
                maneuverIndex: nil,
                riderFraction: Self.riderPosition(along: drawn)
            )
        }

        // The two halves share the budget by how much road each of them covers,
        // and one extra point is allowed for because they meet on a vertex that
        // is only sent once.
        let share = (maneuverAt - from) / (to - from)
        let budgetBefore = min(limit - 1, max(2, Int((Double(limit + 1) * share).rounded())))
        let budgetAfter = limit + 1 - budgetBefore

        let before = thinned(from: from, to: maneuverAt, toAtMost: budgetBefore)
        let after = thinned(from: maneuverAt, to: to, toAtMost: budgetAfter)

        let joined = (before + after.dropFirst()).map { local($0, origin: origin, rotation: rotation) }
        return RoutePath(
            points: joined,
            maneuverIndex: before.count - 1,
            riderFraction: Self.riderPosition(along: joined)
        )
    }

    private func whole(
        from: Double,
        to: Double,
        toAtMost limit: Int,
        origin: Coordinate,
        rotation: Double
    ) -> [RoutePath.Point] {
        thinned(from: from, to: to, toAtMost: limit).map { local($0, origin: origin, rotation: rotation) }
    }

    /// Where the rider falls along a drawn line, as a fraction of its length.
    ///
    /// Found by projection rather than by counting route metres, because the
    /// line that gets sent is the simplified one and its corners are cut. This
    /// measures the line the display will actually receive.
    static func riderPosition(along points: [RoutePath.Point]) -> Double {
        guard points.count > 1 else { return 0 }

        var travelled = [0.0]
        for index in 1..<points.count {
            let step = (points[index].right - points[index - 1].right,
                        points[index].ahead - points[index - 1].ahead)
            travelled.append(travelled[index - 1] + (step.0 * step.0 + step.1 * step.1).squareRoot())
        }

        guard let total = travelled.last, total > 0 else { return 0 }

        var closest = Double.infinity
        var at = 0.0

        for index in 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            let run = (right: b.right - a.right, ahead: b.ahead - a.ahead)
            let square = run.right * run.right + run.ahead * run.ahead
            guard square > 0 else { continue }

            // The rider is the origin of this frame, so projecting onto the
            // segment is just how far along it the foot of the perpendicular
            // from nothing falls.
            let fraction = min(1, max(0, -(a.right * run.right + a.ahead * run.ahead) / square))
            let point = (right: a.right + fraction * run.right, ahead: a.ahead + fraction * run.ahead)
            let away = point.right * point.right + point.ahead * point.ahead

            if away < closest {
                closest = away
                at = travelled[index - 1] + fraction * square.squareRoot()
            }
        }

        return min(1, max(0, at / total))
    }

    /// A stretch of the route, stripped of detail nobody can see and then cut
    /// down to what the link will carry.
    private func thinned(from: Double, to: Double, toAtMost limit: Int) -> [Coordinate] {
        let stretch = Geo.slice(route.polyline, from: from, to: to)
        return Geo.simplify(Geo.simplify(stretch, tolerance: Self.detailFloor), toAtMost: limit)
    }

    /// A coordinate in meters right of and ahead of the rider.
    private func local(_ coordinate: Coordinate, origin: Coordinate, rotation: Double) -> RoutePath.Point {
        let scale = cos(origin.latitude * .pi / 180)
        let east = Geo.earthRadius * (coordinate.longitude - origin.longitude) * .pi / 180 * scale
        let north = Geo.earthRadius * (coordinate.latitude - origin.latitude) * .pi / 180

        // Turning the frame until the heading points up. Compass bearings run
        // clockwise from north while the frame runs counter-clockwise from
        // east, which is why the sines land where they do.
        let angle = rotation * .pi / 180
        return RoutePath.Point(
            right: east * cos(angle) - north * sin(angle),
            ahead: east * sin(angle) + north * cos(angle)
        )
    }
}
