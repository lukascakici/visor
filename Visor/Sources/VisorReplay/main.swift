import Core
import Foundation
import Geometry
import Guidance
import Simulation

// Rides a synthetic track through the guidance engine and prints what would be
// sent to the HUD, one line per second. Nothing here touches CoreLocation,
// CoreBluetooth or a map service, so it runs anywhere Swift does.
//
//   swift run visor-replay              a clean ride
//   swift run visor-replay detour       the rider misses a turn
//   swift run visor-replay tunnel       the signal drops out
//   swift run visor-replay ride --fast  no pause between seconds

let arguments = CommandLine.arguments.dropFirst()
let scenario = arguments.compactMap(Scenario.init(rawValue:)).first ?? .ride
let pause = arguments.contains("--fast") ? 0 : 0.12

let route = DemoRoute.make()
let ride = Ride(route: route, scenario: scenario)
var engine = GuidanceEngine(route: route)

// A fixed starting point, so two runs of the same scenario are comparable.
let departure = Date(timeIntervalSince1970: 1_700_000_000)

print("")
print("  Visor replay — \(scenario.rawValue): \(scenario.summary)")
print("")
print("  Route: \(String(format: "%.1f km", Geo.length(of: route.polyline) / 1000)), \(route.steps.count) steps")
for (index, step) in route.steps.enumerated() {
    let maneuver = String(describing: step.maneuver).padding(toLength: 13, withPad: " ", startingAt: 0)
    print("    \(index + 1). \(maneuver) \(step.streetName ?? "—")")
}
print("")
print(HUDLine.header)

for second in 0...ride.duration {
    let now = departure.addingTimeInterval(Double(second))

    if let fix = ride.fix(atSecond: second, now: now) {
        engine.receive(fix)
    }

    let state = engine.state(at: now)
    print(HUDLine.render(state, atSecond: second))

    // What the app will do for real once MKDirections is wired up. Here it just
    // announces itself and stays in the rerouting state, which is enough to see
    // the backoff and the flag behave.
    if engine.shouldRequestReroute(at: now) {
        engine.beginRerouting(at: now)
        print("        ↳ off route — asking the map service for a new one")
    }

    if pause > 0 {
        Thread.sleep(forTimeInterval: pause)
    }
}

print("")
