import Core
import Foundation

/// Turns a stream of position fixes into the state the HUD is fed.
///
/// Positions arrive whenever the receiver has one; the HUD is written to on a
/// fixed 1 Hz beat. Those are two different clocks, so the engine separates
/// them: `receive(_:)` takes fixes as they come, `state(at:)` answers what is
/// true at the moment of asking. Whether the signal has gone stale is a
/// question only the second one can answer.
///
/// Nothing here talks to CoreLocation or CoreBluetooth. A test can ride a whole
/// route through it by hand.
public struct GuidanceEngine: Sendable {
    public private(set) var index: RouteIndex
    public var configuration: GuidanceConfiguration

    private var lastProgress: RouteProgress?
    private var lastFixTime: Date?
    private var lastAccuracy: Double?
    private var lastSpeed: Double = 0
    private var offRouteFixes = 0
    private var rerouting = false
    private var lastRerouteRequest: Date?

    public init(route: Route, configuration: GuidanceConfiguration = .default) {
        self.index = RouteIndex(route)
        self.configuration = configuration
    }

    // MARK: - Input

    /// Takes a position fix into account.
    ///
    /// Fixes with an invalid position are dropped outright: they carry no
    /// location at all, only the news that the receiver has nothing. Imprecise
    /// but valid fixes are kept, because a rough position beats a frozen one,
    /// but they are not allowed to vote on whether the route has been left.
    public mutating func receive(_ fix: LocationFix) {
        guard fix.isValid, let progress = locate(fix.coordinate, at: fix.timestamp) else { return }

        lastProgress = progress
        lastFixTime = fix.timestamp
        lastAccuracy = fix.horizontalAccuracy
        lastSpeed = max(0, fix.speed)

        // A fix whose uncertainty is wider than the off-route threshold cannot
        // tell the two apart, so it neither accuses nor exonerates.
        guard fix.horizontalAccuracy <= configuration.weakAccuracy else { return }

        if progress.distanceFromRoute > configuration.offRouteDistance {
            offRouteFixes += 1
        } else {
            offRouteFixes = 0
        }
    }

    /// Finds the position on the route, preferring the stretch around where the
    /// rider was last seen.
    ///
    /// The window rests on one assumption: the rider cannot have got far since
    /// the last fix. Two things void it, and either one sends the search back
    /// over the whole route. The position may have left the window, which shows
    /// up as a poor match against it. Or too much time may have passed for the
    /// assumption to mean anything, which no amount of geometry can detect
    /// afterwards: on a route that doubles back, a stale window will happily
    /// match the wrong leg from close range.
    private func locate(_ coordinate: Coordinate, at time: Date) -> RouteProgress? {
        if let travelled = lastProgress?.distanceTravelled,
           let previous = lastFixTime,
           abs(time.timeIntervalSince(previous)) <= configuration.staleFixAge,
           let windowed = index.progress(
               at: coordinate,
               around: travelled,
               back: configuration.searchBack,
               ahead: configuration.searchAhead
           ),
           windowed.distanceFromRoute <= configuration.reacquireDistance {
            return windowed
        }
        return index.progress(at: coordinate)
    }

    // MARK: - Output

    /// What is true at `now`.
    public func state(at now: Date) -> GuidanceState {
        let isStale = lastFixTime.map { now.timeIntervalSince($0) > configuration.staleFixAge } ?? true
        let isImprecise = lastAccuracy.map { $0 > configuration.weakAccuracy } ?? true

        return GuidanceState(
            progress: lastProgress,
            isOffRoute: isOffRoute,
            isRerouting: rerouting,
            hasWeakSignal: isStale || isImprecise,
            speed: lastSpeed
        )
    }

    public var isOffRoute: Bool { offRouteFixes >= configuration.offRouteFixes }

    // MARK: - Rerouting

    /// Whether a new route should be asked for now.
    ///
    /// False while one is already on its way, and false again for a while after
    /// a request, so a route service that is failing or throttling is not
    /// hammered once a second.
    public func shouldRequestReroute(at now: Date) -> Bool {
        guard isOffRoute, !rerouting else { return false }
        guard let last = lastRerouteRequest else { return true }
        return now.timeIntervalSince(last) >= configuration.rerouteBackoff
    }

    /// Records that a new route has been asked for.
    public mutating func beginRerouting(at now: Date) {
        rerouting = true
        lastRerouteRequest = now
    }

    /// Records that the request failed. The rider stays off route, and the
    /// backoff still applies before trying again.
    public mutating func cancelRerouting() {
        rerouting = false
    }

    /// Switches to a new route.
    ///
    /// Everything positional is dropped: distances measured along the old route
    /// mean nothing on this one, and the next fix has to find its place from
    /// scratch.
    public mutating func adopt(_ route: Route) {
        index = RouteIndex(route)
        lastProgress = nil
        offRouteFixes = 0
        rerouting = false
    }
}
