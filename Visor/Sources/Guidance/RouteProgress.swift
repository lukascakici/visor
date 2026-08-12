import Core
import Foundation

/// Everything the HUD needs to know about where the rider is on the route,
/// derived from one position fix.
///
/// This is a snapshot with no history in it: off-route detection and the other
/// judgements that need several fixes in a row are built on top of it.
public struct RouteProgress: Hashable, Sendable {
    /// The position pulled onto the route line.
    public let snapped: Coordinate
    /// How far the fix sits from the route, in meters. Off-route detection
    /// reads this; on a clean ride it stays within GPS noise.
    public let distanceFromRoute: Double
    /// Distance covered from the start of the route, in meters.
    public let distanceTravelled: Double
    /// Distance still to cover, in meters.
    public let distanceRemaining: Double
    /// Which step of the route the rider is currently on.
    public let stepIndex: Int
    /// The maneuver waiting at the end of the current step. On the final step
    /// this is `.arrive`, because the thing ahead is the destination.
    public let maneuver: ManeuverType
    /// Distance to that maneuver, in meters.
    public let distanceToManeuver: Double
    /// The road the maneuver leads onto, which is what a rider needs to read
    /// while approaching it. On the final step it is the road being arrived on.
    public let streetName: String?
    /// Expected time to the destination, in seconds.
    public let timeRemaining: TimeInterval
}
