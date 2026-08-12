import Foundation

/// One leg of a route: the stretch of road between two junctions.
///
/// `maneuver` is what the rider does to *enter* this step, so it belongs to the
/// step's first vertex. The first step of a route therefore carries `.depart`.
public struct RouteStep: Hashable, Sendable {
    /// The geometry of the step, from the junction that starts it to the one
    /// that ends it.
    public var polyline: [Coordinate]
    /// Length of the step in meters.
    public var distance: Double
    /// How long the step is expected to take, in seconds.
    public var expectedTravelTime: TimeInterval
    /// Name of the road this step runs along, in whatever language the map data
    /// came in. Display only: nothing in Guidance ever reads it.
    public var streetName: String?
    /// The maneuver entering this step. Filled in by the maneuver classifier
    /// from the geometry, never parsed out of an instruction string.
    public var maneuver: ManeuverType

    public init(
        polyline: [Coordinate],
        distance: Double,
        expectedTravelTime: TimeInterval,
        streetName: String? = nil,
        maneuver: ManeuverType = .unknown
    ) {
        self.polyline = polyline
        self.distance = distance
        self.expectedTravelTime = expectedTravelTime
        self.streetName = streetName
        self.maneuver = maneuver
    }
}

/// A computed route, in a form no Apple framework is needed to build.
///
/// `Routing` produces one of these from an `MKRoute`; `Guidance` consumes it.
/// Keeping the model here is what lets the guidance logic be exercised with
/// hand-written geometry in a unit test.
public struct Route: Hashable, Sendable {
    public var steps: [RouteStep]
    /// Every step stitched together, with the duplicated vertex at each
    /// junction removed. This is the line positions are snapped against.
    public var polyline: [Coordinate]
    /// Total length in meters.
    public var distance: Double
    /// Total expected travel time in seconds.
    public var expectedTravelTime: TimeInterval

    /// Builds a route from its steps.
    ///
    /// `distance` and `expectedTravelTime` default to the sum over the steps.
    /// Pass them explicitly to keep the totals the map service reported, which
    /// can differ slightly from the sum of the parts.
    public init(steps: [RouteStep], distance: Double? = nil, expectedTravelTime: TimeInterval? = nil) {
        self.steps = steps
        self.polyline = Route.stitch(steps)
        self.distance = distance ?? steps.reduce(0) { $0 + $1.distance }
        self.expectedTravelTime = expectedTravelTime ?? steps.reduce(0) { $0 + $1.expectedTravelTime }
    }

    /// Concatenates step geometry, dropping a step's first vertex when it
    /// repeats the last vertex of the step before it.
    private static func stitch(_ steps: [RouteStep]) -> [Coordinate] {
        var stitched: [Coordinate] = []
        for step in steps {
            var vertices = step.polyline[...]
            if let last = stitched.last, vertices.first == last {
                vertices = vertices.dropFirst()
            }
            stitched.append(contentsOf: vertices)
        }
        return stitched
    }
}
