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

    public init(points: [Point], maneuverIndex: Int?) {
        self.points = points
        self.maneuverIndex = maneuverIndex
    }

    public static let empty = RoutePath(points: [], maneuverIndex: nil)
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

    /// Which way the road runs at a point along the route, in compass degrees.
    ///
    /// Measured over the next 20 m rather than off the segment underfoot. Route
    /// geometry ends steps with tails a meter or two long, and reading the
    /// direction off one of those would swing the whole picture around for a
    /// second at every junction.
    public func heading(at travelled: Double) -> Double {
        let lookahead = 20.0
        let from = min(max(0, travelled), max(0, length - lookahead))

        guard
            let start = Geo.coordinate(on: route.polyline, at: from),
            let end = Geo.coordinate(on: route.polyline, at: from + lookahead),
            start != end
        else { return 0 }

        return Geo.initialBearing(from: start, to: end)
    }

    /// The stretch of road around the rider, in the rider's own frame.
    ///
    /// `behind` is short on purpose. A line that only runs forward loses the
    /// sense of which way the rider came from, and a short tail restores it
    /// without spending bytes on road nobody is going to ride again.
    ///
    /// `points` is the whole budget, junction marker included: whatever comes
    /// back fits in it.
    public func path(
        at progress: RouteProgress,
        behind: Double = 100,
        ahead: Double = 500,
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
            let whole = thinned(from: from, to: to, toAtMost: limit)
            return RoutePath(
                points: whole.map { local($0, origin: origin, rotation: rotation) },
                maneuverIndex: nil
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

        let joined = before + after.dropFirst()
        return RoutePath(
            points: joined.map { local($0, origin: origin, rotation: rotation) },
            maneuverIndex: before.count - 1
        )
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
