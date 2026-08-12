import Core
import Geometry
import XCTest
@testable import Guidance

private let start = Coordinate(latitude: 41.0082, longitude: 28.9784)
private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

/// Two 300 m legs: north, then right onto an east road.
private func straightRoute() -> Route {
    let corner = Geo.destination(from: start, bearing: 0, distance: 300)
    let end = Geo.destination(from: corner, bearing: 90, distance: 300)

    return ManeuverClassifier.annotated(
        Route(steps: [
            RouteStep(polyline: [start, corner], distance: 300, expectedTravelTime: 40, streetName: "First"),
            RouteStep(polyline: [corner, end], distance: 300, expectedTravelTime: 40, streetName: "Second"),
        ])
    )
}

private func fix(
    _ coordinate: Coordinate,
    accuracy: Double = 5,
    speed: Double = 12,
    at seconds: TimeInterval = 0
) -> LocationFix {
    LocationFix(
        coordinate: coordinate,
        horizontalAccuracy: accuracy,
        speed: speed,
        timestamp: epoch.addingTimeInterval(seconds)
    )
}

/// A point `meters` along the route, pushed `offset` meters to the east of it.
private func onRoute(_ route: Route, meters: Double, offsetEast offset: Double = 0) -> Coordinate {
    let point = Geo.coordinate(on: route.polyline, at: meters)!
    return offset == 0 ? point : Geo.destination(from: point, bearing: 90, distance: offset)
}

final class EngineStartupTests: XCTestCase {
    func testBeforeAnyFixThereIsNothingToReport() {
        let engine = GuidanceEngine(route: straightRoute())
        let state = engine.state(at: epoch)

        XCTAssertNil(state.progress)
        XCTAssertFalse(state.isOffRoute)
        XCTAssertFalse(state.isRerouting)
        XCTAssertEqual(state.speed, 0)
    }

    func testAnUnknownPositionCountsAsAWeakSignal() {
        let engine = GuidanceEngine(route: straightRoute())
        XCTAssertTrue(engine.state(at: epoch).hasWeakSignal)
    }

    func testTheFirstGoodFixPlacesTheRider() throws {
        var engine = GuidanceEngine(route: straightRoute())
        engine.receive(fix(onRoute(engine.index.route, meters: 100)))

        let state = engine.state(at: epoch)
        let progress = try XCTUnwrap(state.progress)

        XCTAssertEqual(progress.distanceTravelled, 100, accuracy: 0.5)
        XCTAssertEqual(progress.maneuver, .right)
        XCTAssertFalse(state.hasWeakSignal)
        XCTAssertEqual(state.speed, 12, accuracy: 1e-9)
    }
}

final class OffRouteDetectionTests: XCTestCase {
    private var engine = GuidanceEngine(route: straightRoute())

    override func setUp() {
        super.setUp()
        engine = GuidanceEngine(route: straightRoute())
    }

    func testStayingNearTheRouteIsNeverOffRoute() {
        for second in 0..<10 {
            let point = onRoute(engine.index.route, meters: Double(second) * 12, offsetEast: 8)
            engine.receive(fix(point, at: TimeInterval(second)))
            XCTAssertFalse(engine.isOffRoute, "at second \(second)")
        }
    }

    func testOneStrayFixIsNotEnough() {
        engine.receive(fix(onRoute(engine.index.route, meters: 100), at: 0))
        engine.receive(fix(onRoute(engine.index.route, meters: 110, offsetEast: 60), at: 1))

        XCTAssertFalse(engine.isOffRoute)
    }

    func testTwoStrayFixesAreStillNotEnough() {
        engine.receive(fix(onRoute(engine.index.route, meters: 100, offsetEast: 60), at: 0))
        engine.receive(fix(onRoute(engine.index.route, meters: 110, offsetEast: 60), at: 1))

        XCTAssertFalse(engine.isOffRoute)
    }

    func testThreeInARowDeclaresTheRouteLeft() {
        for second in 0..<3 {
            let point = onRoute(engine.index.route, meters: 100 + Double(second) * 10, offsetEast: 60)
            engine.receive(fix(point, at: TimeInterval(second)))
        }

        XCTAssertTrue(engine.isOffRoute)
        XCTAssertTrue(engine.state(at: epoch).isOffRoute)
    }

    func testComingBackToTheRouteClearsTheCount() {
        engine.receive(fix(onRoute(engine.index.route, meters: 100, offsetEast: 60), at: 0))
        engine.receive(fix(onRoute(engine.index.route, meters: 110, offsetEast: 60), at: 1))
        engine.receive(fix(onRoute(engine.index.route, meters: 120), at: 2))
        engine.receive(fix(onRoute(engine.index.route, meters: 130, offsetEast: 60), at: 3))

        XCTAssertFalse(engine.isOffRoute)
    }

    func testTheThresholdIsTheDistanceFromTheRouteNotFromTheStep() {
        // Exactly at the limit is still on route; past it is not.
        engine.receive(fix(onRoute(engine.index.route, meters: 100, offsetEast: 39), at: 0))
        engine.receive(fix(onRoute(engine.index.route, meters: 110, offsetEast: 39), at: 1))
        engine.receive(fix(onRoute(engine.index.route, meters: 120, offsetEast: 39), at: 2))

        XCTAssertFalse(engine.isOffRoute)
    }
}

final class WeakSignalTests: XCTestCase {
    func testAnImpreciseFixRaisesTheFlagButIsStillUsed() throws {
        var engine = GuidanceEngine(route: straightRoute())
        engine.receive(fix(onRoute(engine.index.route, meters: 150), accuracy: 90, at: 0))

        let state = engine.state(at: epoch)
        XCTAssertTrue(state.hasWeakSignal)
        XCTAssertEqual(try XCTUnwrap(state.progress).distanceTravelled, 150, accuracy: 0.5)
    }

    func testImpreciseFixesCannotDeclareTheRouteLeft() {
        var engine = GuidanceEngine(route: straightRoute())
        // Far enough off to trip the threshold, but each fix is uncertain by
        // more than the threshold itself, so none of them may vote.
        for second in 0..<5 {
            let point = onRoute(engine.index.route, meters: 100 + Double(second) * 10, offsetEast: 60)
            engine.receive(fix(point, accuracy: 90, at: TimeInterval(second)))
        }

        XCTAssertFalse(engine.isOffRoute)
        XCTAssertTrue(engine.state(at: epoch).hasWeakSignal)
    }

    func testImpreciseFixesDoNotClearAnExistingCountEither() {
        var engine = GuidanceEngine(route: straightRoute())
        engine.receive(fix(onRoute(engine.index.route, meters: 100, offsetEast: 60), at: 0))
        engine.receive(fix(onRoute(engine.index.route, meters: 110, offsetEast: 60), at: 1))
        // A wildly uncertain fix that happens to land on the route: it says
        // nothing either way, so the count survives it.
        engine.receive(fix(onRoute(engine.index.route, meters: 120), accuracy: 200, at: 2))
        engine.receive(fix(onRoute(engine.index.route, meters: 130, offsetEast: 60), at: 3))

        XCTAssertTrue(engine.isOffRoute)
    }

    func testAnInvalidFixIsIgnoredEntirely() {
        var engine = GuidanceEngine(route: straightRoute())
        engine.receive(fix(onRoute(engine.index.route, meters: 150), at: 0))
        let before = engine.state(at: epoch)

        engine.receive(fix(onRoute(engine.index.route, meters: 400), accuracy: -1, at: 1))

        XCTAssertEqual(engine.state(at: epoch), before)
    }

    func testTheSignalGoesWeakWhenFixesStopArriving() throws {
        var engine = GuidanceEngine(route: straightRoute())
        engine.receive(fix(onRoute(engine.index.route, meters: 150), at: 0))

        XCTAssertFalse(engine.state(at: epoch.addingTimeInterval(4)).hasWeakSignal)
        XCTAssertTrue(engine.state(at: epoch.addingTimeInterval(6)).hasWeakSignal)
    }

    func testALostSignalStillReportsThePositionRatherThanHidingIt() throws {
        var engine = GuidanceEngine(route: straightRoute())
        engine.receive(fix(onRoute(engine.index.route, meters: 150), at: 0))

        // A minute into a tunnel: the last known position is still there, and
        // it is marked as not to be trusted.
        let state = engine.state(at: epoch.addingTimeInterval(60))
        XCTAssertTrue(state.hasWeakSignal)
        XCTAssertEqual(try XCTUnwrap(state.progress).distanceTravelled, 150, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(state.progress).maneuver, .right)
    }
}

final class ReroutingTests: XCTestCase {
    private var engine = GuidanceEngine(route: straightRoute())

    override func setUp() {
        super.setUp()
        engine = GuidanceEngine(route: straightRoute())
        for second in 0..<3 {
            let point = onRoute(engine.index.route, meters: 100 + Double(second) * 10, offsetEast: 80)
            engine.receive(fix(point, at: TimeInterval(second)))
        }
    }

    func testStayingOnRouteNeverAsksForANewOne() {
        var onRouteEngine = GuidanceEngine(route: straightRoute())
        onRouteEngine.receive(fix(onRoute(onRouteEngine.index.route, meters: 100), at: 0))

        XCTAssertFalse(onRouteEngine.shouldRequestReroute(at: epoch))
    }

    func testLeavingTheRouteAsksForANewOne() {
        XCTAssertTrue(engine.shouldRequestReroute(at: epoch))
    }

    func testNoSecondRequestWhileOneIsInFlight() {
        engine.beginRerouting(at: epoch)

        XCTAssertTrue(engine.state(at: epoch).isRerouting)
        XCTAssertFalse(engine.shouldRequestReroute(at: epoch.addingTimeInterval(30)))
    }

    func testAFailedRequestBacksOffBeforeRetrying() {
        engine.beginRerouting(at: epoch)
        engine.cancelRerouting()

        XCTAssertFalse(engine.state(at: epoch).isRerouting)
        XCTAssertFalse(engine.shouldRequestReroute(at: epoch.addingTimeInterval(1)))
        XCTAssertTrue(engine.shouldRequestReroute(at: epoch.addingTimeInterval(6)))
    }

    func testANewRouteClearsEverythingPositional() throws {
        engine.beginRerouting(at: epoch)
        engine.adopt(straightRoute())

        let state = engine.state(at: epoch)
        XCTAssertFalse(state.isOffRoute)
        XCTAssertFalse(state.isRerouting)
        XCTAssertNil(state.progress)
        XCTAssertFalse(engine.shouldRequestReroute(at: epoch))
    }

    func testTheNewRouteIsTheOneBeingFollowed() throws {
        let detour = ManeuverClassifier.annotated(Route(steps: [
            RouteStep(
                polyline: [start, Geo.destination(from: start, bearing: 270, distance: 500)],
                distance: 500,
                expectedTravelTime: 60,
                streetName: "Detour"
            )
        ]))
        engine.adopt(detour)
        engine.receive(fix(Geo.destination(from: start, bearing: 270, distance: 200), at: 10))

        let progress = try XCTUnwrap(engine.state(at: epoch.addingTimeInterval(10)).progress)
        XCTAssertEqual(progress.distanceTravelled, 200, accuracy: 0.5)
        XCTAssertEqual(progress.streetName, "Detour")
        XCTAssertEqual(progress.maneuver, .arrive)
    }
}

final class DoublingBackTests: XCTestCase {
    /// Out and back: 400 m north, then back south on the other side of the
    /// road, 5 m across. Exactly the shape that makes a naive nearest-point
    /// search jump between the two legs.
    private func outAndBack() -> Route {
        let turnaround = Geo.destination(from: start, bearing: 0, distance: 400)
        let returnStart = Geo.destination(from: turnaround, bearing: 90, distance: 5)
        let returnEnd = Geo.destination(from: start, bearing: 90, distance: 5)

        return ManeuverClassifier.annotated(Route(steps: [
            RouteStep(polyline: [start, turnaround], distance: 400, expectedTravelTime: 60, streetName: "Out"),
            RouteStep(polyline: [returnStart, returnEnd], distance: 400, expectedTravelTime: 60, streetName: "Back"),
        ]))
    }

    func testTheRiderKeepsMovingForwardsAlongTheRoute() throws {
        let route = outAndBack()
        var engine = GuidanceEngine(route: route)
        var previous = -1.0

        for meters in stride(from: 0.0, through: 800.0, by: 20.0) {
            let point = try XCTUnwrap(Geo.coordinate(on: route.polyline, at: meters))
            engine.receive(fix(point, at: meters / 20))

            let progress = try XCTUnwrap(engine.state(at: epoch).progress)
            XCTAssertEqual(progress.distanceTravelled, meters, accuracy: 2, "at \(meters) m")
            XCTAssertGreaterThan(progress.distanceTravelled, previous, "at \(meters) m")
            previous = progress.distanceTravelled
        }
    }

    func testNoiseTowardsTheOppositeLegDoesNotThrowTheRiderBackwards() throws {
        let route = outAndBack()
        var engine = GuidanceEngine(route: route)

        // Ride out and turn around.
        for meters in stride(from: 0.0, through: 600.0, by: 20.0) {
            engine.receive(fix(try XCTUnwrap(Geo.coordinate(on: route.polyline, at: meters)), at: meters / 20))
        }

        // A fix on the return leg, pushed 8 m west by noise. It now sits closer
        // to the outbound leg than to the road actually being ridden.
        let onReturn = try XCTUnwrap(Geo.coordinate(on: route.polyline, at: 620))
        let noisy = Geo.destination(from: onReturn, bearing: 270, distance: 8)

        // Searching the whole route lands on the outbound leg, hundreds of
        // meters back: this is the mistake the window exists to prevent.
        let naive = try XCTUnwrap(RouteIndex(route).progress(at: noisy))
        XCTAssertLessThan(naive.distanceTravelled, 300)

        engine.receive(fix(noisy, at: 31))
        let progress = try XCTUnwrap(engine.state(at: epoch).progress)
        XCTAssertEqual(progress.distanceTravelled, 620, accuracy: 10)
        XCTAssertEqual(progress.streetName, "Back")
    }

    func testAPositionFarFromTheWindowIsFoundAgainAnyway() throws {
        let route = outAndBack()
        var engine = GuidanceEngine(route: route)
        engine.receive(fix(try XCTUnwrap(Geo.coordinate(on: route.polyline, at: 20)), at: 0))

        // Picked up again far past the search window, as after a long tunnel.
        let farAhead = try XCTUnwrap(Geo.coordinate(on: route.polyline, at: 700))
        engine.receive(fix(farAhead, at: 120))

        let progress = try XCTUnwrap(engine.state(at: epoch.addingTimeInterval(120)).progress)
        XCTAssertEqual(progress.distanceTravelled, 700, accuracy: 10)
    }
}
