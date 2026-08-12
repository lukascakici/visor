import Core
import Foundation
import Geometry

/// What the rider does, beyond simply following the route.
enum Scenario: String, CaseIterable {
    /// Rides the route from end to end.
    case ride
    /// Leaves the route partway along and keeps going.
    case detour
    /// Loses the signal for half a minute, then gets it back badly.
    case tunnel

    var summary: String {
        switch self {
        case .ride: "follows the route to the end"
        case .detour: "leaves the route halfway and keeps riding"
        case .tunnel: "loses the signal for 30 s, then reacquires it poorly"
        }
    }
}

/// Generates the second-by-second position fixes a ride would produce.
///
/// Everything is derived from the tick number, so a run is reproducible: the
/// same scenario always produces the same fixes, which is what makes the output
/// worth comparing against a previous run.
struct Ride {
    let route: Route
    let scenario: Scenario
    /// Ground speed in meters per second, near enough to 50 km/h.
    let speed = 14.0

    private var length: Double { Geo.length(of: route.polyline) }
    private var whereItGoesWrong: Double { length * 0.45 }

    /// How many seconds the ride lasts.
    var duration: Int { Int(length / speed) + 15 }

    /// The fix for a given second, or `nil` when the receiver has nothing to
    /// report.
    func fix(atSecond second: Int, now: Date) -> LocationFix? {
        let travelled = Double(second) * speed

        switch scenario {
        case .ride:
            return report(at: onRoute(travelled), accuracy: 5, now: now)

        case .detour:
            guard travelled > whereItGoesWrong else {
                return report(at: onRoute(travelled), accuracy: 5, now: now)
            }
            // Peels off at a shallow angle, the way a missed turn looks.
            let left = onRoute(whereItGoesWrong)
            let heading = Geo.initialBearing(from: onRoute(whereItGoesWrong - 20), to: left)
            let strayed = Geo.destination(
                from: left,
                bearing: heading + 35,
                distance: travelled - whereItGoesWrong
            )
            return report(at: strayed, accuracy: 5, now: now)

        case .tunnel:
            let secondsIn = (travelled - whereItGoesWrong) / speed
            // No sky, no fixes.
            if secondsIn > 0, secondsIn < 30 { return nil }
            // The first fixes after coming out are wide open.
            let accuracy = secondsIn >= 30 && secondsIn < 38 ? 70.0 : 5.0
            return report(at: onRoute(travelled), accuracy: accuracy, now: now)
        }
    }

    /// A point on the route, nudged by a couple of meters of receiver noise.
    ///
    /// The wobble is deliberate: a threshold that a parked motorcycle can trip
    /// is the wrong threshold, and this is what proves it does not.
    private func onRoute(_ travelled: Double) -> Coordinate {
        let point = Geo.coordinate(on: route.polyline, at: min(travelled, length)) ?? DemoRoute.origin
        let wobble = sin(travelled / 37) * 4
        return Geo.destination(from: point, bearing: wobble < 0 ? 270 : 90, distance: abs(wobble))
    }

    private func report(at coordinate: Coordinate, accuracy: Double, now: Date) -> LocationFix {
        LocationFix(coordinate: coordinate, horizontalAccuracy: accuracy, speed: speed, timestamp: now)
    }
}
