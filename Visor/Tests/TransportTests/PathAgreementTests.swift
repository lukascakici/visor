import Core
import Foundation
import Geometry
import Guidance
import XCTest
@testable import Transport

private let start = Coordinate(latitude: 41.0082, longitude: 28.9784)
private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

/// Two 300 m legs, north then right onto an east road, with a vertex every 10 m
/// so the geometry has detail to lose on the way to the wire.
private func route() -> Route {
    let corner = Geo.destination(from: start, bearing: 0, distance: 300)
    let up = (0...30).map { Geo.destination(from: start, bearing: 0, distance: Double($0) * 10) }
    let across = (0...30).map { Geo.destination(from: corner, bearing: 90, distance: Double($0) * 10) }

    return ManeuverClassifier.annotated(Route(steps: [
        RouteStep(polyline: up, distance: 300, expectedTravelTime: 40, streetName: "Second"),
        RouteStep(polyline: across, distance: 300, expectedTravelTime: 40, streetName: "Destination"),
    ]))
}

/// A rider 200 m up the first leg, 100 m short of the turn.
private func engineNearTheTurn() -> GuidanceEngine {
    var engine = GuidanceEngine(route: route())
    let here = Geo.destination(from: start, bearing: 0, distance: 200)
    engine.receive(LocationFix(coordinate: here, horizontalAccuracy: 5, speed: 12, timestamp: epoch))
    return engine
}

/// What the two packets say about the same junction has to match. They travel
/// on different characteristics and are built by different code, and a device
/// told "turn right in 100 m" while being handed a map with the turn 300 m out
/// is worse than a device with no map at all.
final class PathAgreementTests: XCTestCase {
    func testTheDrawnJunctionIsWhereTheInstructionSaysItIs() throws {
        let engine = engineNearTheTurn()
        let state = engine.state(at: epoch)
        let progress = try XCTUnwrap(state.progress)

        let instruction = try XCTUnwrap(DecodedPacket(HUDPacket(state).encoded(maximumSize: 200)))
        let map = try XCTUnwrap(DecodedPath(
            PathPacket(engine.index.path(at: progress, points: 40)).encoded(maximumSize: 512)
        ))

        XCTAssertEqual(instruction.maneuver, .right)
        XCTAssertEqual(instruction.distanceToManeuver, 100, accuracy: 1)

        let junction = map.points[try XCTUnwrap(map.maneuverIndex)]
        let range = Double(junction.right * junction.right + junction.ahead * junction.ahead).squareRoot() / 10
        XCTAssertEqual(range, Double(instruction.distanceToManeuver), accuracy: 1)
    }

    func testTheRoadRunsAwayFromTheRiderAndTurnsTheRightWay() throws {
        let engine = engineNearTheTurn()
        let progress = try XCTUnwrap(engine.state(at: epoch).progress)
        let map = try XCTUnwrap(DecodedPath(
            PathPacket(engine.index.path(at: progress, points: 40)).encoded(maximumSize: 512)
        ))

        // Straight ahead up to the junction, then away to the right. A sign
        // error anywhere between the projection and the wire lands here.
        let junction = try XCTUnwrap(map.maneuverIndex)
        XCTAssertEqual(map.points[junction].right, 0, accuracy: 10)
        XCTAssertGreaterThan(map.points[junction].ahead, 0)
        XCTAssertGreaterThan(try XCTUnwrap(map.points.last).right, 1_000)
        XCTAssertLessThan(try XCTUnwrap(map.points.first).ahead, 0)
    }

    func testAStraightRoadCostsAlmostNothingToDraw() throws {
        let engine = engineNearTheTurn()
        let progress = try XCTUnwrap(engine.state(at: epoch).progress)
        let data = PathPacket(engine.index.path(at: progress, points: 40)).encoded(maximumSize: 512)

        // Sixty-one vertices of road went in. Two straights and a corner came
        // out, which is the whole argument for sending shape instead of pixels.
        XCTAssertLessThanOrEqual(data.count, 40)
    }

    func testTheSmallestLinkStillGetsAUsableRoad() throws {
        let engine = engineNearTheTurn()
        let progress = try XCTUnwrap(engine.state(at: epoch).progress)

        let budget = PathPacket.points(fitting: PathPacket.guaranteedSize)
        let data = PathPacket(engine.index.path(at: progress, points: budget)).encoded(
            maximumSize: PathPacket.guaranteedSize
        )
        let map = try XCTUnwrap(DecodedPath(data))

        XCTAssertLessThanOrEqual(data.count, PathPacket.guaranteedSize)
        XCTAssertGreaterThan(map.points.count, 1)
        // Even on the floor of what Bluetooth guarantees, the turn is still
        // marked and still in front of the rider.
        let junction = map.points[try XCTUnwrap(map.maneuverIndex)]
        XCTAssertEqual(Double(junction.ahead) / 10, 100, accuracy: 2)
    }
}
