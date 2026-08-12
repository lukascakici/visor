import Core
import Foundation
import Guidance
import MapKit

extension Route {
    /// Rebuilds a MapKit route as one of ours, with the maneuvers worked out
    /// from the geometry.
    ///
    /// Two things MapKit does not hand over have to be dealt with here.
    ///
    /// It gives no per-step travel time, only a total for the route, so the
    /// total is shared out in proportion to distance. That makes the ETA
    /// blind to a step being slower than its length suggests, which the quoted
    /// per-step times would have carried.
    ///
    /// It gives no road names either, only a written instruction per step in
    /// whatever language the device is set to. That sentence goes into
    /// `streetName`, for display only.
    ///
    /// The instruction belongs to the *end* of its step, which is worth stating
    /// because it is not what the property name suggests. On a real route out
    /// of Kadıköy, the junction between step 1 and step 2 turns 87 degrees to
    /// the left by the geometry, and the sentence calling it a left turn sits
    /// on step 1, not step 2. Every junction on that route agreed. So the
    /// instruction stays on the step MapKit put it on, and `streetName` is
    /// defined the same way: it describes the maneuver ending its step.
    public init(_ route: MKRoute) {
        let distances = route.steps.map(\.distance)
        let times = StepTiming.distribute(route.expectedTravelTime, across: distances)

        let steps = route.steps.enumerated().map { index, step in
            RouteStep(
                polyline: step.polyline.asCoordinates,
                distance: step.distance,
                expectedTravelTime: times[index],
                streetName: step.instructions.isEmpty ? nil : step.instructions
            )
        }

        self = ManeuverClassifier.annotated(
            Route(
                steps: steps,
                distance: route.distance,
                expectedTravelTime: route.expectedTravelTime
            )
        )
    }
}

/// Shares a route's total travel time out over its steps.
enum StepTiming {
    /// Splits `total` in proportion to `distances`.
    ///
    /// Steps with no length between them get an equal share instead: a route
    /// made entirely of zero length steps is nonsense, but returning a list of
    /// NaNs for it would spread that nonsense into every ETA downstream.
    static func distribute(_ total: TimeInterval, across distances: [Double]) -> [TimeInterval] {
        guard !distances.isEmpty else { return [] }

        let usable = distances.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        let sum = usable.reduce(0, +)

        guard sum > 0 else {
            return Array(repeating: total / Double(distances.count), count: distances.count)
        }
        return usable.map { total * ($0 / sum) }
    }
}
