import Core
import Geometry
import XCTest
@testable import Guidance

private let start = Coordinate(latitude: 41.0082, longitude: 28.9784)

/// North for 300 m, then right onto a road running east for 300 m. A vertex
/// every 10 m, so there is redundant detail to throw away.
private func cornerRoute() -> Route {
    let turn = Geo.destination(from: start, bearing: 0, distance: 300)
    let up = (0...30).map { Geo.destination(from: start, bearing: 0, distance: Double($0) * 10) }
    let across = (0...30).map { Geo.destination(from: turn, bearing: 90, distance: Double($0) * 10) }

    return ManeuverClassifier.annotated(Route(steps: [
        RouteStep(polyline: up, distance: 300, expectedTravelTime: 40, streetName: "Second"),
        RouteStep(polyline: across, distance: 300, expectedTravelTime: 40, streetName: "Destination"),
    ]))
}

/// A quarter circle of radius 200 m as a single step, a vertex every 5 m or so.
/// Curving the whole way, so no vertex is redundant and a budget has to be paid
/// for in shape.
private func curvedRoute() -> Route {
    let polyline = (0...62).map {
        Geo.destination(from: start, bearing: Double($0) * 90 / 62, distance: 200)
    }
    return Route(steps: [
        RouteStep(polyline: polyline, distance: 314, expectedTravelTime: 40, streetName: "Destination"),
    ])
}

private func progress(_ index: RouteIndex, at travelled: Double) throws -> RouteProgress {
    let point = try XCTUnwrap(Geo.coordinate(on: index.route.polyline, at: travelled))
    return try XCTUnwrap(index.progress(at: point))
}

final class RouteHeadingTests: XCTestCase {
    func testTheHeadingFollowsTheRoad() throws {
        let index = RouteIndex(cornerRoute())

        XCTAssertEqual(Geo.bearingDelta(from: index.heading(at: 0), to: 0), 0, accuracy: 0.5)
        XCTAssertEqual(Geo.bearingDelta(from: index.heading(at: 150), to: 0), 0, accuracy: 0.5)
        XCTAssertEqual(Geo.bearingDelta(from: index.heading(at: 400), to: 90), 0, accuracy: 0.5)
    }

    func testTheHeadingAtTheDestinationIsTheRoadArrivedOn() throws {
        // Nothing left to look ahead at, so it reads the last 20 m instead of
        // collapsing to a meaningless zero.
        let index = RouteIndex(cornerRoute())
        XCTAssertEqual(Geo.bearingDelta(from: index.heading(at: 600), to: 90), 0, accuracy: 0.5)
    }

    /// The reason the frame is not read off a short chord.
    ///
    /// A road that wanders a couple of metres either side of straight, which is
    /// what ordinary route geometry looks like. Read over twenty metres this
    /// wander is worth eight degrees and the map shakes; the frame has to sit
    /// still through it.
    func testAWanderingRoadDoesNotSwingTheFrame() {
        let wobbly = (0...60).map { index -> Coordinate in
            let along = Geo.destination(from: start, bearing: 0, distance: Double(index) * 10)
            let sway = sin(Double(index) * 0.9) * 2.5
            return Geo.destination(from: along, bearing: 90, distance: sway)
        }
        let index = RouteIndex(Route(steps: [
            RouteStep(polyline: wobbly, distance: 600, expectedTravelTime: 60, streetName: "Destination"),
        ]))

        /// What reading the frame off a short chord used to give, for comparison.
        func chord(at travelled: Double) -> Double {
            let from = min(max(0, travelled), max(0, index.length - 20))
            guard
                let start = Geo.coordinate(on: index.route.polyline, at: from),
                let end = Geo.coordinate(on: index.route.polyline, at: from + 20)
            else { return 0 }
            return Geo.initialBearing(from: start, to: end)
        }

        var worstSwing = 0.0
        var worstChordSwing = 0.0
        var furthestOff = 0.0

        var previous = index.heading(at: 0)
        var previousChord = chord(at: 0)

        for metre in stride(from: 5.0, through: 400.0, by: 5) {
            let heading = index.heading(at: metre)
            let naive = chord(at: metre)

            worstSwing = max(worstSwing, abs(Geo.bearingDelta(from: previous, to: heading)))
            worstChordSwing = max(worstChordSwing, abs(Geo.bearingDelta(from: previousChord, to: naive)))
            furthestOff = max(furthestOff, abs(Geo.bearingDelta(from: heading, to: 0)))

            previous = heading
            previousChord = naive
        }

        // Measured against what it replaces rather than against a number picked
        // out of the air: the frame has to be several times steadier than a
        // short chord, or there was no point widening it.
        XCTAssertLessThan(worstSwing * 3, worstChordSwing)
        // And still pointing down the road it is on.
        XCTAssertLessThan(furthestOff, 4.0)
    }

    func testARouteWithNoGeometryHasNoHeading() {
        let index = RouteIndex(Route(steps: [
            RouteStep(polyline: [start], distance: 0, expectedTravelTime: 0),
        ]))
        XCTAssertEqual(index.heading(at: 0), 0)
    }
}

final class RoutePathTests: XCTestCase {
    // MARK: - The frame

    func testTheLineRunsFromBehindTheRiderToInFrontOfThem() throws {
        let index = RouteIndex(cornerRoute())
        let path = index.path(at: try progress(index, at: 200), behind: 100, ahead: 50)

        XCTAssertEqual(try XCTUnwrap(path.points.first).ahead, -100, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(path.points.last).ahead, 50, accuracy: 0.5)
    }

    func testAStraightRoadRunsStraightUp() throws {
        let index = RouteIndex(cornerRoute())
        let path = index.path(at: try progress(index, at: 200), behind: 100, ahead: 50)

        for point in path.points {
            XCTAssertEqual(point.right, 0, accuracy: 0.5)
        }
    }

    func testARoadTurningRightLeavesToTheRight() throws {
        let index = RouteIndex(cornerRoute())
        // 100 m short of the corner, with the whole east leg in view.
        let path = index.path(at: try progress(index, at: 200), behind: 100, ahead: 500)

        let end = try XCTUnwrap(path.points.last)
        XCTAssertEqual(end.right, 300, accuracy: 1)
        XCTAssertEqual(end.ahead, 100, accuracy: 1)
    }

    func testTheFrameTurnsWithTheRider() throws {
        let index = RouteIndex(cornerRoute())
        // Same corner, ridden through: the east leg is now dead ahead rather
        // than off to the right. Same road, different frame.
        let path = index.path(at: try progress(index, at: 400), behind: 100, ahead: 150)

        for point in path.points {
            XCTAssertEqual(point.right, 0, accuracy: 0.5)
        }
        XCTAssertEqual(try XCTUnwrap(path.points.first).ahead, -100, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(path.points.last).ahead, 150, accuracy: 0.5)
    }

    // MARK: - The junction

    func testTheManeuverIsOneOfThePoints() throws {
        let index = RouteIndex(cornerRoute())
        let here = try progress(index, at: 200)
        let path = index.path(at: here, behind: 100, ahead: 500)

        let marked = try XCTUnwrap(path.maneuverIndex)
        let junction = path.points[marked]

        // Where the packet says the turn is has to be where the guidance says
        // it is, or the picture and the instruction disagree.
        let range = (junction.right * junction.right + junction.ahead * junction.ahead).squareRoot()
        XCTAssertEqual(range, here.distanceToManeuver, accuracy: 1)
        XCTAssertEqual(junction.ahead, 100, accuracy: 1)
        XCTAssertEqual(junction.right, 0, accuracy: 1)
    }

    func testTheCornerSurvivesEvenOnATightBudget() throws {
        let index = RouteIndex(cornerRoute())
        let path = index.path(at: try progress(index, at: 200), behind: 100, ahead: 500, points: 4)

        let junction = try XCTUnwrap(path.maneuverIndex).self
        XCTAssertEqual(path.points[junction].ahead, 100, accuracy: 1)
        XCTAssertEqual(path.points[junction].right, 0, accuracy: 1)
    }

    func testAManeuverOutOfSightIsNotMarked() throws {
        let index = RouteIndex(cornerRoute())
        // The corner is 100 m away and only 50 m of road is being drawn.
        let path = index.path(at: try progress(index, at: 200), behind: 100, ahead: 50)

        XCTAssertNil(path.maneuverIndex)
    }

    func testNoRoomToSplitMeansNoMarker() throws {
        let index = RouteIndex(cornerRoute())
        let path = index.path(at: try progress(index, at: 200), behind: 100, ahead: 500, points: 3)

        XCTAssertNil(path.maneuverIndex)
        XCTAssertLessThanOrEqual(path.points.count, 3)
    }

    // MARK: - The budget

    func testTheBudgetIsNeverExceeded() throws {
        let index = RouteIndex(curvedRoute())
        let here = try progress(index, at: 150)

        for limit in [2, 4, 8, 20, 40] {
            XCTAssertLessThanOrEqual(index.path(at: here, points: limit).points.count, limit)
        }
    }

    func testABiggerBudgetDrawsMoreOfTheCurve() throws {
        let index = RouteIndex(curvedRoute())
        let here = try progress(index, at: 150)

        XCTAssertGreaterThan(
            index.path(at: here, points: 30).points.count,
            index.path(at: here, points: 6).points.count
        )
    }

    func testAStraightStretchSpendsAlmostNothing() throws {
        let index = RouteIndex(cornerRoute())
        // Thirty vertices of dead straight road, and none of them worth a byte.
        let path = index.path(at: try progress(index, at: 150), behind: 100, ahead: 100)

        XCTAssertEqual(path.points.count, 2)
    }

    // MARK: - Reach

    func testThePathReachesFurtherThanAnyDisplayDraws() throws {
        // Two kilometres of straight road, ridden from 500 m in.
        let polyline = (0...200).map { Geo.destination(from: start, bearing: 0, distance: Double($0) * 10) }
        let index = RouteIndex(Route(steps: [
            RouteStep(polyline: polyline, distance: 2000, expectedTravelTime: 120, streetName: "Destination"),
        ]))
        let path = index.path(at: try progress(index, at: 500))

        // The display draws 450 m of this. Sending less than it draws is what
        // makes a road stop inside the panel, and a road that stops on screen
        // reads as a turn or an ending rather than as one that carries on.
        XCTAssertGreaterThan(try XCTUnwrap(path.points.map(\.ahead).max()), 900)

        // And it costs two points, because a straight kilometre is two points.
        XCTAssertEqual(path.points.count, 2)
    }

    // MARK: - Edges

    func testThePathStopsAtTheDestination() throws {
        let index = RouteIndex(cornerRoute())
        let path = index.path(at: try progress(index, at: 550), behind: 50, ahead: 500)

        XCTAssertEqual(try XCTUnwrap(path.points.last).ahead, 50, accuracy: 1)
    }

    func testThePathStartsAtTheOriginOfTheRoute() throws {
        let index = RouteIndex(cornerRoute())
        let path = index.path(at: try progress(index, at: 20), behind: 100, ahead: 100)

        XCTAssertEqual(try XCTUnwrap(path.points.first).ahead, -20, accuracy: 0.5)
    }

    func testARouteWithNoGeometryDrawsNothing() throws {
        let index = RouteIndex(Route(steps: [
            RouteStep(polyline: [start], distance: 0, expectedTravelTime: 0),
        ]))
        let here = try XCTUnwrap(index.progress(at: start))

        XCTAssertEqual(index.path(at: here).points, [])
        XCTAssertNil(index.path(at: here).maneuverIndex)
    }
}
