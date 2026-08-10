import Core
import Foundation

/// Spherical-earth geometry, as pure functions.
///
/// Angles are degrees, distances are meters. The earth is treated as a sphere:
/// over the segment lengths a route is made of, the error against an
/// ellipsoidal model stays far below the GPS noise we already tolerate.
public enum Geo {
    /// IUGG mean earth radius, in meters.
    public static let earthRadius = 6_371_008.8

    /// Great-circle distance between two points, in meters.
    public static func distance(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude.inRadians
        let lat2 = b.latitude.inRadians
        let halfDeltaLat = (lat2 - lat1) / 2
        let halfDeltaLon = (b.longitude - a.longitude).inRadians / 2

        let h = sin(halfDeltaLat) * sin(halfDeltaLat)
            + cos(lat1) * cos(lat2) * sin(halfDeltaLon) * sin(halfDeltaLon)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }

    /// Compass bearing at `a` when heading towards `b`, in `0..<360` degrees,
    /// clockwise from true north.
    ///
    /// This is the *initial* bearing: along a long great circle the bearing
    /// keeps changing, so only the value at the starting point is meaningful.
    /// Route segments are short enough that the distinction does not matter.
    public static func initialBearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude.inRadians
        let lat2 = b.latitude.inRadians
        let deltaLon = (b.longitude - a.longitude).inRadians

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return normalizedBearing(atan2(y, x).inDegrees)
    }

    /// The point reached by travelling `distance` meters from `origin` along
    /// `bearing`.
    ///
    /// Mostly a fixture builder for tests and simulated tracks, but it is exact
    /// enough to be used anywhere.
    public static func destination(
        from origin: Coordinate,
        bearing: Double,
        distance: Double
    ) -> Coordinate {
        let lat1 = origin.latitude.inRadians
        let lon1 = origin.longitude.inRadians
        let course = bearing.inRadians
        let angular = distance / earthRadius

        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(course))
        let lon2 = lon1 + atan2(
            sin(course) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )

        return Coordinate(
            latitude: lat2.inDegrees,
            longitude: normalizedLongitude(lon2.inDegrees)
        )
    }

    /// Folds an arbitrary angle into `0..<360` degrees.
    public static func normalizedBearing(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// The shortest turn from one bearing to another, in `-180...180` degrees.
    /// Positive is clockwise (a right turn), negative is counter-clockwise.
    ///
    /// This is the primitive the maneuver classifier is built on: it is what
    /// makes 350 degrees to 10 degrees read as a 20 degree nudge rather than a
    /// 340 degree swerve. A perfect reversal reports `+180` from either side,
    /// since neither direction is shorter.
    public static func bearingDelta(from: Double, to: Double) -> Double {
        let difference = normalizedBearing(to - from)
        return difference > 180 ? difference - 360 : difference
    }

    /// Folds a longitude into `-180..<180` degrees.
    static func normalizedLongitude(_ degrees: Double) -> Double {
        let wrapped = (degrees + 180).truncatingRemainder(dividingBy: 360)
        return (wrapped < 0 ? wrapped + 360 : wrapped) - 180
    }
}

extension Double {
    var inRadians: Double { self * .pi / 180 }
    var inDegrees: Double { self * 180 / .pi }
}
