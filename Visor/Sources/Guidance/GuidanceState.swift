import Core
import Foundation

/// What the engine currently believes, which is what gets sent to the HUD.
public struct GuidanceState: Hashable, Sendable {
    /// Where the rider is on the route, or `nil` before the first usable fix.
    public let progress: RouteProgress?
    /// The route has been left: several fixes in a row landed too far from it.
    public let isOffRoute: Bool
    /// A replacement route has been asked for and has not arrived yet.
    public let isRerouting: Bool
    /// The position being reported cannot be trusted, because the newest fix is
    /// either too imprecise or too old.
    ///
    /// The stale reading is still passed on rather than withheld, but it is
    /// passed on marked. A HUD that keeps showing "turn right in 200 m" from a
    /// fix taken a minute ago in a tunnel will walk a rider into a junction;
    /// one that knows the reading is stale can dim it or drop the distance.
    public let hasWeakSignal: Bool
    /// Ground speed in meters per second, `0` when never reported.
    public let speed: Double
}
