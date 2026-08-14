import Core
import Foundation
import Geometry
import Guidance
import Routing
import Simulation
import Transport

// Rides a synthetic track through the guidance engine and prints what would be
// sent to the HUD, one line per second. No receiver and no Bluetooth are
// involved; the map service is only asked for anything when a destination is
// named with --to.
//
//   swift run visor-replay              a clean ride
//   swift run visor-replay detour       the rider misses a turn
//   swift run visor-replay tunnel       the signal drops out
//   swift run visor-replay ride --fast  no pause between seconds
//   swift run visor-replay --bytes      show both packets that would be written
//   swift run visor-replay --map        draw the road the HUD would draw
//   swift run visor-replay --mtu 23     squeeze both packets onto the floor of
//                                       what Bluetooth guarantees
//   swift run visor-replay --to Bostanci
//                                       ride a real route from the map service
//                                       instead of the hand-built one

let arguments = Array(CommandLine.arguments.dropFirst())
let scenario = arguments.compactMap(Scenario.init(rawValue:)).first ?? .ride
let pause = arguments.contains("--fast") ? 0 : 0.12
let showBytes = arguments.contains("--bytes")
let showMap = arguments.contains("--map")
let query = arguments.firstIndex(of: "--to").map { arguments[arguments.index(after: $0)...].first } ?? nil

/// What one write will carry, which is the ATT MTU less its three byte header.
///
/// Defaulted to what iOS actually negotiates rather than to the floor, because
/// that is what a rider's packets will be sized to. `--mtu 23` puts it back on
/// the floor, which is where truncation and a four point road can be seen.
let mtu = arguments.firstIndex(of: "--mtu")
    .flatMap { arguments[arguments.index(after: $0)...].first }
    .flatMap(Int.init) ?? 185
let writeSize = max(HUDPacket.headerSize, mtu - 3)
let pathBudget = PathPacket.points(fitting: writeSize)

/// Either the hand-built route or a real one, searched for by name from the
/// demo route's starting point. Riding a real route is the only way to find out
/// what the map service's geometry actually does to the maneuver classifier.
func makeRoute() async -> Route {
    guard let query else { return DemoRoute.make() }

    do {
        let places = try await PlaceSearch().find(query, near: DemoRoute.origin)
        guard let place = places.first else {
            print("  Nothing found for \"\(query)\"")
            exit(1)
        }
        print("  Destination: \(place.name)\(place.address.map { " — \($0)" } ?? "")")
        return try await RoutePlanner().route(from: DemoRoute.origin, to: place.coordinate)
    } catch {
        print("  Could not plan a route: \(error)")
        exit(1)
    }
}

let route = await makeRoute()
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
if arguments.contains("--steps") {
    StepReport.print(route)
    exit(0)
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

    // The road, built to what this link would carry, exactly as the phone
    // builds it. Nothing here is drawn from the route directly: if the packet
    // cannot say it, the map cannot show it.
    let path = state.progress.map { engine.index.path(at: $0, points: pathBudget) } ?? .empty

    if showBytes {
        print(HUDLine.bytes(HUDPacket(state).encoded(maximumSize: writeSize)))
        print(HUDLine.pathBytes(PathPacket(path).encoded(maximumSize: writeSize), points: path.points.count))
    }

    if showMap {
        print("")
        for row in PathMap.render(path) {
            print(row)
        }
        print("")
    }

    // What the app will do for real once MKDirections is wired up. Here it just
    // announces itself and stays in the rerouting state, which is enough to see
    // the backoff and the flag behave.
    if engine.shouldRequestReroute(at: now) {
        engine.beginRerouting(at: now)
        print("        ↳ off route — asking the map service for a new one")
    }

    if pause > 0 {
        try? await Task.sleep(for: .seconds(pause))
    }
}

print("")
