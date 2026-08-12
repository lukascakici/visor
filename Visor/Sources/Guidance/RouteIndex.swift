import Core
import Foundation
import Geometry

/// A route with the measurements that answering "where am I?" needs, worked out
/// once instead of on every position fix.
///
/// A fix arrives every second and the route can carry thousands of vertices, so
/// the per-step lengths, their offsets along the stitched line, and the running
/// time to the destination are all precomputed here. What is left per fix is one
/// projection and a lookup.
public struct RouteIndex: Sendable {
    public let route: Route
    /// Geometric length of each step, in meters.
    public let stepLengths: [Double]
    /// Distance along the route where each step begins, in meters.
    public let stepOffsets: [Double]
    /// Geometric length of the whole route, in meters.
    public let length: Double
    /// Expected time from the end of each step to the destination, in seconds.
    public let timeAfterStep: [TimeInterval]

    public init(_ route: Route) {
        self.route = route

        // Lengths come from the geometry rather than from `step.distance`: the
        // map service's numbers are rounded, and these have to line up exactly
        // with distances measured along the polyline we project onto.
        let lengths = route.steps.map { Geo.length(of: $0.polyline) }

        var offsets: [Double] = []
        var travelled = 0.0
        for index in route.steps.indices {
            offsets.append(travelled)
            travelled += lengths[index]

            // Steps normally meet exactly, and stitching drops the repeated
            // vertex. When they do not meet, stitching leaves a connector
            // segment between them, and it has to be counted here or every
            // later offset drifts.
            if index + 1 < route.steps.count,
               let end = route.steps[index].polyline.last,
               let next = route.steps[index + 1].polyline.first,
               end != next {
                travelled += Geo.distance(from: end, to: next)
            }
        }

        var remainingTime = [TimeInterval](repeating: 0, count: route.steps.count)
        var accumulated = 0.0
        for index in route.steps.indices.reversed() {
            remainingTime[index] = accumulated
            accumulated += route.steps[index].expectedTravelTime
        }

        self.stepLengths = lengths
        self.stepOffsets = offsets
        self.length = travelled
        self.timeAfterStep = remainingTime
    }

    /// Locates a position on the route.
    ///
    /// The position is taken as-is, however far off the route it may be: the
    /// result reports that distance rather than rejecting the fix, because
    /// deciding whether the rider has actually left the route takes more than
    /// one measurement.
    ///
    /// Returns `nil` for a route with no geometry to snap to.
    public func progress(at coordinate: Coordinate) -> RouteProgress? {
        guard let projection = Geo.project(coordinate, onto: route.polyline) else { return nil }
        return progress(
            travelled: projection.distanceAlongPolyline,
            snapped: projection.point,
            distanceFromRoute: projection.distance
        )
    }

    /// Locates a position, considering only the stretch of route from `back`
    /// meters behind `travelled` to `ahead` meters in front of it.
    ///
    /// A route that doubles back on itself passes close to where it has already
    /// been, and the globally closest point can then be on the wrong leg: the
    /// rider appears to teleport back to a stretch ridden ten minutes ago. A
    /// position only has to be judged against the road the rider could
    /// plausibly have reached since the last fix, which is what this does.
    public func progress(
        at coordinate: Coordinate,
        around travelled: Double,
        back: Double,
        ahead: Double
    ) -> RouteProgress? {
        let from = max(0, travelled - back)
        let window = Geo.slice(route.polyline, from: from, to: travelled + ahead)

        guard let projection = Geo.project(coordinate, onto: window) else { return nil }
        return progress(
            travelled: from + projection.distanceAlongPolyline,
            snapped: projection.point,
            distanceFromRoute: projection.distance
        )
    }

    private func progress(
        travelled: Double,
        snapped: Coordinate,
        distanceFromRoute: Double
    ) -> RouteProgress? {
        guard !route.steps.isEmpty else { return nil }

        let stepIndex = stepOffsets.lastIndex { $0 <= travelled } ?? 0
        let isFinalStep = stepIndex == route.steps.count - 1

        let stepEnd = stepOffsets[stepIndex] + stepLengths[stepIndex]
        let toManeuver = max(0, stepEnd - travelled)

        // The current step is credited pro rata by distance, everything after
        // it at the time the map service quoted. Riding faster or slower than
        // that quote is not corrected for yet.
        let fractionLeft = stepLengths[stepIndex] > 0 ? toManeuver / stepLengths[stepIndex] : 0
        let timeRemaining = fractionLeft * route.steps[stepIndex].expectedTravelTime
            + timeAfterStep[stepIndex]

        return RouteProgress(
            snapped: snapped,
            distanceFromRoute: distanceFromRoute,
            distanceTravelled: travelled,
            distanceRemaining: max(0, length - travelled),
            stepIndex: stepIndex,
            maneuver: isFinalStep ? .arrive : route.steps[stepIndex + 1].maneuver,
            distanceToManeuver: toManeuver,
            streetName: isFinalStep
                ? route.steps[stepIndex].streetName
                : route.steps[stepIndex + 1].streetName,
            timeRemaining: timeRemaining
        )
    }
}
