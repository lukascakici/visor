import Core
import Geometry
import Guidance

/// A hand-built route through Kadıköy, standing in for one a map service would
/// return.
///
/// The street names are real Turkish ones on purpose: they carry multi-byte
/// characters, so anything that mishandles UTF-8 further down the line shows up
/// here rather than on the device.
enum DemoRoute {
    static let origin = Coordinate(latitude: 40.9785, longitude: 29.0640)

    /// (bearing to travel, meters, street being entered)
    /// Turned so the route exercises a different maneuver band at every
    /// junction: right, slight left, sharp right, left.
    private static let legs: [(bearing: Double, meters: Double, street: String)] = [
        (0, 420, "Bağdat Caddesi"),
        (88, 310, "Şemsettin Günaltay Caddesi"),
        (62, 260, "Tütüncü Mehmet Efendi Caddesi"),
        (205, 180, "Çamlık Sokak"),
        (118, 540, "Bostancı Yolu"),
    ]

    /// Roughly 40 km/h, which is what the travel times are quoted at.
    private static let quotedSpeed = 11.0

    static func make() -> Route {
        var here = origin
        var steps: [RouteStep] = []

        for leg in legs {
            // Two vertices per leg is enough to carry a direction; real route
            // geometry is denser, and the engine does not care either way.
            let end = Geo.destination(from: here, bearing: leg.bearing, distance: leg.meters)
            steps.append(
                RouteStep(
                    polyline: [here, end],
                    distance: leg.meters,
                    expectedTravelTime: leg.meters / quotedSpeed,
                    streetName: leg.street
                )
            )
            here = end
        }

        return ManeuverClassifier.annotated(Route(steps: steps))
    }
}
