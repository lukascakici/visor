import Foundation

/// The thresholds the guidance engine judges by.
public struct GuidanceConfiguration: Hashable, Sendable {
    /// How far off the route a position has to be before it counts against the
    /// rider, in meters.
    public var offRouteDistance: Double
    /// How many such positions in a row it takes to declare the route left.
    ///
    /// A single bad fix is normal: a reflection off a building, a lane change
    /// where the map geometry sits on the other carriageway. Rerouting on one
    /// measurement means rerouting constantly in a city.
    public var offRouteFixes: Int
    /// Above this accuracy radius a fix is treated as weak, in meters.
    public var weakAccuracy: Double
    /// How old the newest fix may get before the signal counts as lost, in
    /// seconds.
    public var staleFixAge: TimeInterval
    /// Minimum spacing between reroute requests, in seconds. Map services
    /// throttle callers, so a failed reroute must not turn into a retry storm.
    public var rerouteBackoff: TimeInterval
    /// How far behind the last known position to keep looking, in meters.
    ///
    /// Deliberately short. It only has to cover fix-to-fix jitter, and every
    /// meter of it is a meter of already-ridden road that a doubling-back route
    /// could snap onto by mistake.
    public var searchBack: Double
    /// How far ahead of the last known position to keep looking, in meters.
    /// Wide enough to survive a tunnel or a stretch of missed fixes.
    public var searchAhead: Double
    /// Past this distance from the windowed match the window is abandoned and
    /// the whole route is searched again, in meters. This is how a position
    /// that has genuinely left the window is recovered.
    public var reacquireDistance: Double

    public init(
        offRouteDistance: Double = 40,
        offRouteFixes: Int = 3,
        weakAccuracy: Double = 40,
        staleFixAge: TimeInterval = 5,
        rerouteBackoff: TimeInterval = 5,
        searchBack: Double = 50,
        searchAhead: Double = 500,
        reacquireDistance: Double = 100
    ) {
        self.offRouteDistance = offRouteDistance
        self.offRouteFixes = offRouteFixes
        self.weakAccuracy = weakAccuracy
        self.staleFixAge = staleFixAge
        self.rerouteBackoff = rerouteBackoff
        self.searchBack = searchBack
        self.searchAhead = searchAhead
        self.reacquireDistance = reacquireDistance
    }

    public static let `default` = GuidanceConfiguration()
}
