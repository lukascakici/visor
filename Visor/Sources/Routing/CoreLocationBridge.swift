import Core
import CoreLocation
import MapKit

// Where Visor's own types meet Apple's. Everything below this layer works in
// plain numbers, which is what lets the guidance logic run in a unit test with
// no frameworks underneath it.

extension Coordinate {
    public var asCLCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension LocationFix {
    /// Translates a CoreLocation reading, invalid-value conventions and all.
    public init(_ location: CLLocation) {
        self.init(
            coordinate: Coordinate(location.coordinate),
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            course: location.course,
            timestamp: location.timestamp
        )
    }
}

extension MKPolyline {
    /// The vertices, copied out of the C buffer MapKit keeps them in.
    public var asCoordinates: [Coordinate] {
        var points = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: pointCount
        )
        getCoordinates(&points, range: NSRange(location: 0, length: pointCount))
        return points.map(Coordinate.init)
    }
}
