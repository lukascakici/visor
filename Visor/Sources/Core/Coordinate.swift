/// A geographic point in WGS-84 degrees.
///
/// Deliberately independent of CoreLocation: every layer built on top of this
/// type stays testable on any platform, with no device or simulator involved.
public struct Coordinate: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
