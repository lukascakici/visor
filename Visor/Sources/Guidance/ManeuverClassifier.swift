import Core
import Geometry

/// Works out what the rider does at a junction from the shape of the road.
///
/// The classification never looks at an instruction string. Those strings are
/// localized prose: they change with the device language and with map data
/// updates, and matching on them breaks the moment someone rides with the phone
/// set to another language. The geometry says the same thing in every language.
public enum ManeuverClassifier {
    /// Maps a signed turn in degrees onto a maneuver.
    ///
    /// Positive is clockwise, so positive turns are to the right. The magnitude
    /// alone decides the band; the sign only picks the side.
    public static func classify(
        turn degrees: Double,
        thresholds: ManeuverThresholds = .default
    ) -> ManeuverType {
        let magnitude = abs(degrees)
        let isRight = degrees > 0

        switch magnitude {
        case ...thresholds.straight:
            return .straight
        case ...thresholds.slight:
            return isRight ? .slightRight : .slightLeft
        case ...thresholds.turn:
            return isRight ? .right : .left
        case ...thresholds.sharp:
            return isRight ? .sharpRight : .sharpLeft
        default:
            return .uTurn
        }
    }

    /// The turn, in signed degrees, between the road being left and the road
    /// being entered.
    ///
    /// Returns `nil` when either side has no usable direction, which happens
    /// with an empty polyline, a single vertex, or a run of identical points.
    public static func turn(
        leaving: [Coordinate],
        entering: [Coordinate],
        thresholds: ManeuverThresholds = .default
    ) -> Double? {
        guard
            let out = exitBearing(of: leaving, window: thresholds.bearingWindow),
            let into = entryBearing(of: entering, window: thresholds.bearingWindow)
        else { return nil }
        return Geo.bearingDelta(from: out, to: into)
    }

    /// The maneuver at the junction between two steps, or `.unknown` when the
    /// geometry cannot support a decision.
    public static func maneuver(
        leaving: [Coordinate],
        entering: [Coordinate],
        thresholds: ManeuverThresholds = .default
    ) -> ManeuverType {
        guard let degrees = turn(leaving: leaving, entering: entering, thresholds: thresholds) else {
            return .unknown
        }
        return classify(turn: degrees, thresholds: thresholds)
    }

    /// Returns the route with a maneuver filled in on every step.
    ///
    /// The first step is always `.depart`; every later step gets the maneuver
    /// that carries the rider from the previous step into it. Arrival is not a
    /// step: it is reported by the guidance engine when the destination becomes
    /// the next thing ahead.
    public static func annotated(
        _ route: Route,
        thresholds: ManeuverThresholds = .default
    ) -> Route {
        var steps = route.steps
        for index in steps.indices {
            steps[index].maneuver = index == 0
                ? .depart
                : maneuver(
                    leaving: steps[index - 1].polyline,
                    entering: steps[index].polyline,
                    thresholds: thresholds
                )
        }
        return Route(
            steps: steps,
            distance: route.distance,
            expectedTravelTime: route.expectedTravelTime
        )
    }

    /// Direction of travel over the last `window` meters of a polyline.
    ///
    /// Public because it is the number to look at when a classification is
    /// disputed: the maneuver is an opinion derived from these two bearings,
    /// and the bearings are the evidence.
    public static func exitBearing(of polyline: [Coordinate], window: Double) -> Double? {
        guard polyline.count > 1, let end = polyline.last else { return nil }
        let start = Geo.coordinate(on: polyline, at: max(0, Geo.length(of: polyline) - window))
        guard let start, Geo.distance(from: start, to: end) > 0 else { return nil }
        return Geo.initialBearing(from: start, to: end)
    }

    /// Direction of travel over the first `window` meters of a polyline.
    public static func entryBearing(of polyline: [Coordinate], window: Double) -> Double? {
        guard polyline.count > 1, let start = polyline.first else { return nil }
        let end = Geo.coordinate(on: polyline, at: min(window, Geo.length(of: polyline)))
        guard let end, Geo.distance(from: start, to: end) > 0 else { return nil }
        return Geo.initialBearing(from: start, to: end)
    }
}
