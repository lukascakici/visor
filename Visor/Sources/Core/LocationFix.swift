import Foundation

/// One position report from the device.
///
/// The invalid-value conventions are CoreLocation's, so the iOS layer can map a
/// `CLLocation` across field by field without deciding anything on the way: a
/// negative accuracy means the position is unusable, and a negative speed or
/// course means that reading is unavailable.
public struct LocationFix: Hashable, Sendable {
    public var coordinate: Coordinate
    /// Radius of uncertainty around the position, in meters. Negative when the
    /// position itself is invalid.
    public var horizontalAccuracy: Double
    /// Ground speed in meters per second, or negative when unknown.
    public var speed: Double
    /// Direction of travel in degrees from true north, or negative when unknown.
    public var course: Double
    /// When the position was determined, which is not when it was delivered.
    public var timestamp: Date

    public init(
        coordinate: Coordinate,
        horizontalAccuracy: Double,
        speed: Double = -1,
        course: Double = -1,
        timestamp: Date
    ) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }

    /// Whether the position is worth using at all.
    public var isValid: Bool { horizontalAccuracy >= 0 }
}
