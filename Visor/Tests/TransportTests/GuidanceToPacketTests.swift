import Core
import Foundation
import Geometry
import Guidance
import XCTest
@testable import Transport

private let start = Coordinate(latitude: 41.0082, longitude: 28.9784)
private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

/// Two 300 m legs, north then right onto an east road.
private func route() -> Route {
    let corner = Geo.destination(from: start, bearing: 0, distance: 300)
    let end = Geo.destination(from: corner, bearing: 90, distance: 300)

    return ManeuverClassifier.annotated(Route(steps: [
        RouteStep(polyline: [start, corner], distance: 300, expectedTravelTime: 40, streetName: "First"),
        RouteStep(polyline: [corner, end], distance: 300, expectedTravelTime: 40, streetName: "Second"),
    ]))
}

private func engineAtStart() -> GuidanceEngine {
    var engine = GuidanceEngine(route: route())
    engine.receive(LocationFix(coordinate: start, horizontalAccuracy: 5, speed: 15, timestamp: epoch))
    return engine
}

final class GuidanceToPacketTests: XCTestCase {
    func testThePacketCarriesTheManeuverAhead() {
        let packet = HUDPacket(engineAtStart().state(at: epoch))

        XCTAssertEqual(packet.maneuver, .right)
        XCTAssertEqual(packet.distanceToManeuver, 300, accuracy: 1)
        XCTAssertEqual(packet.distanceRemaining, 600, accuracy: 1)
        XCTAssertEqual(packet.streetName, "Second")
        XCTAssertEqual(packet.speed, 15, accuracy: 1e-9)
    }

    func testWithNoPositionThereIsNothingToInstruct() {
        let packet = HUDPacket(GuidanceEngine(route: route()).state(at: epoch))

        XCTAssertEqual(packet.maneuver, .unknown)
        XCTAssertEqual(packet.distanceToManeuver, 0)
        XCTAssertEqual(packet.distanceRemaining, 0)
        XCTAssertEqual(packet.timeRemaining, 0)
        XCTAssertNil(packet.streetName)
    }

    func testAStaleFixRaisesTheWeakSignalFlag() {
        let packet = HUDPacket(engineAtStart().state(at: epoch.addingTimeInterval(60)))

        XCTAssertTrue(packet.flags.contains(.weakSignal))
        XCTAssertFalse(packet.flags.contains(.offRoute))
        // The last known instruction still goes out, marked rather than hidden.
        XCTAssertEqual(packet.maneuver, .right)
    }

    func testLeavingTheRouteRaisesItsFlag() {
        var engine = GuidanceEngine(route: route())
        for second in 0..<3 {
            let onRoute = Geo.coordinate(on: engine.index.route.polyline, at: 100 + Double(second) * 10)!
            let aside = Geo.destination(from: onRoute, bearing: 90, distance: 70)
            engine.receive(LocationFix(
                coordinate: aside,
                horizontalAccuracy: 5,
                speed: 15,
                timestamp: epoch.addingTimeInterval(Double(second))
            ))
        }
        engine.beginRerouting(at: epoch)

        let packet = HUDPacket(engine.state(at: epoch.addingTimeInterval(2)))
        XCTAssertTrue(packet.flags.contains(.offRoute))
        XCTAssertTrue(packet.flags.contains(.rerouting))
    }

    func testTheWholeChainReachesTheWire() throws {
        let packet = HUDPacket(engineAtStart().state(at: epoch))
        let decoded = try XCTUnwrap(DecodedPacket(packet.encoded(maximumSize: 40)))

        XCTAssertEqual(decoded.maneuver, .right)
        XCTAssertEqual(decoded.distanceToManeuver, 300, accuracy: 1)
        XCTAssertEqual(decoded.speed, 54)
        XCTAssertEqual(decoded.streetName, "Second")
    }
}
