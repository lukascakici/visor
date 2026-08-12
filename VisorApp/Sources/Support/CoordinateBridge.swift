import Core
import CoreLocation

// The only place where Visor's own coordinate type meets Apple's. Keeping the
// conversion here is what allows every layer below the app to stay free of
// CoreLocation.

extension Coordinate {
    var asCLCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension LocationFix {
    /// Translates a CoreLocation reading, invalid-value conventions and all.
    init(_ location: CLLocation) {
        self.init(
            coordinate: Coordinate(location.coordinate),
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            course: location.course,
            timestamp: location.timestamp
        )
    }
}
