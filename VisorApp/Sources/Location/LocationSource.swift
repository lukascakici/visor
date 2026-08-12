import Core
import CoreLocation
import Foundation
import Simulation

/// Where position fixes come from.
///
/// The session drives one clock at 1 Hz and asks the source for whatever it has
/// each time, rather than each source running a timer of its own. That keeps
/// the replayed ride and the real one on identical footing, and it means the
/// source also owns the answer to "what time is it": a replayed ride runs on
/// its own clock, and the engine's staleness rules have to be measured against
/// the same one.
protocol LocationSource: AnyObject {
    /// This source's notion of the current moment.
    var now: Date { get }
    /// The newest fix, if one has arrived since the last call.
    func tick() -> LocationFix?
    /// Starts over from the beginning.
    func reset()
}

/// Replays a scripted ride, with no receiver involved.
final class ReplaySource: LocationSource {
    private let ride: Ride
    private let departure = Date(timeIntervalSince1970: 1_700_000_000)
    private var second = -1

    init(route: Route, scenario: Scenario) {
        self.ride = Ride(route: route, scenario: scenario)
    }

    var now: Date { departure.addingTimeInterval(Double(max(0, second))) }

    /// Whether the scripted ride has played out.
    var hasFinished: Bool { second >= ride.duration }

    func tick() -> LocationFix? {
        second += 1
        return ride.fix(atSecond: second, now: now)
    }

    func reset() {
        second = -1
    }
}

/// The real receiver.
///
/// Configured for a motorcycle mounted phone: precise updates, delivered while
/// the screen is off and the app is in the background, and never downgraded to
/// significant-change updates, which are far too coarse to guide a turn.
final class DeviceLocationSource: NSObject, LocationSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: LocationFix?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    var now: Date { Date() }

    func tick() -> LocationFix? {
        defer { pending = nil }
        return pending
    }

    func reset() {
        pending = nil
    }

    func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        pending = LocationFix(newest)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Background updates can only be switched on once the always
        // authorization is actually granted; asking earlier throws.
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Nothing to do: a failed update simply means no new fix, and the
        // engine already treats silence as a weakening signal.
    }
}
