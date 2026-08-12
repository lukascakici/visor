import Core
import Geometry
import XCTest
@testable import Guidance

private let junction = Coordinate(latitude: 41.0082, longitude: 28.9784)

/// A straight stretch of road `meters` long, running along `bearing` and
/// *ending* at `end`. This is the road being left behind at a junction.
private func approach(to end: Coordinate, bearing: Double, meters: Double = 120) -> [Coordinate] {
    let start = Geo.destination(from: end, bearing: Geo.normalizedBearing(bearing + 180), distance: meters)
    return [start, end]
}

/// A straight stretch of road `meters` long, running along `bearing` and
/// *starting* at `start`. This is the road being entered.
private func exit(from start: Coordinate, bearing: Double, meters: Double = 120) -> [Coordinate] {
    [start, Geo.destination(from: start, bearing: bearing, distance: meters)]
}

final class TurnClassificationTests: XCTestCase {
    func testSmallWobblesAreStraight() {
        XCTAssertEqual(ManeuverClassifier.classify(turn: 0), .straight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 14), .straight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: -14), .straight)
    }

    func testBandBoundariesAreInclusive() {
        XCTAssertEqual(ManeuverClassifier.classify(turn: 15), .straight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 45), .slightRight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 135), .right)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 160), .sharpRight)
    }

    func testJustPastEachBoundary() {
        XCTAssertEqual(ManeuverClassifier.classify(turn: 15.01), .slightRight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 45.01), .right)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 135.01), .sharpRight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 160.01), .uTurn)
    }

    func testSignPicksTheSide() {
        XCTAssertEqual(ManeuverClassifier.classify(turn: 30), .slightRight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: -30), .slightLeft)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 90), .right)
        XCTAssertEqual(ManeuverClassifier.classify(turn: -90), .left)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 150), .sharpRight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: -150), .sharpLeft)
    }

    func testReversalIsAUTurnFromEitherSide() {
        XCTAssertEqual(ManeuverClassifier.classify(turn: 180), .uTurn)
        XCTAssertEqual(ManeuverClassifier.classify(turn: -180), .uTurn)
    }

    func testThresholdsAreConfigurable() {
        // A tighter straight band turns a 12 degree drift into a slight turn.
        let strict = ManeuverThresholds(straight: 5)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 12), .straight)
        XCTAssertEqual(ManeuverClassifier.classify(turn: 12, thresholds: strict), .slightRight)
    }
}

final class ManeuverFromGeometryTests: XCTestCase {
    func testDrivingStraightOn() {
        let maneuver = ManeuverClassifier.maneuver(
            leaving: approach(to: junction, bearing: 0),
            entering: exit(from: junction, bearing: 0)
        )
        XCTAssertEqual(maneuver, .straight)
    }

    func testRightAngleTurns() {
        XCTAssertEqual(
            ManeuverClassifier.maneuver(
                leaving: approach(to: junction, bearing: 0),
                entering: exit(from: junction, bearing: 90)
            ),
            .right
        )
        XCTAssertEqual(
            ManeuverClassifier.maneuver(
                leaving: approach(to: junction, bearing: 0),
                entering: exit(from: junction, bearing: 270)
            ),
            .left
        )
    }

    func testDoublingBackIsAUTurn() {
        let maneuver = ManeuverClassifier.maneuver(
            leaving: approach(to: junction, bearing: 0),
            entering: exit(from: junction, bearing: 180)
        )
        XCTAssertEqual(maneuver, .uTurn)
    }

    func testTurnIsMeasuredAcrossNorthWithoutWrapping() {
        // Heading 350, leaving on 10: a 20 degree nudge, not a 340 degree swerve.
        let maneuver = ManeuverClassifier.maneuver(
            leaving: approach(to: junction, bearing: 350),
            entering: exit(from: junction, bearing: 10)
        )
        XCTAssertEqual(maneuver, .slightRight)
    }

    func testTurnIsSignedClockwise() throws {
        let degrees = try XCTUnwrap(
            ManeuverClassifier.turn(
                leaving: approach(to: junction, bearing: 0),
                entering: exit(from: junction, bearing: 90)
            )
        )
        XCTAssertEqual(degrees, 90, accuracy: 0.5)
    }

    func testOnlyTheEndOfTheApproachCounts() {
        // 300 m due east, then the last 30 m curving to due north. What matters
        // at the junction is where the road points on arrival, not the overall
        // direction of the step.
        let beforeJunction = Geo.destination(from: junction, bearing: 180, distance: 30)
        let stepStart = Geo.destination(from: beforeJunction, bearing: 270, distance: 300)
        let leaving = [stepStart, beforeJunction, junction]

        let maneuver = ManeuverClassifier.maneuver(
            leaving: leaving,
            entering: exit(from: junction, bearing: 0)
        )
        XCTAssertEqual(maneuver, .straight)
    }

    func testShortNoiseSegmentAtTheEndDoesNotDecideTheTurn() {
        // A 1 m tail pointing hard left, on a road that is otherwise dead
        // straight. Taken alone that tail would read as a sharp left.
        let approachStart = Geo.destination(from: junction, bearing: 180, distance: 120)
        let noise = Geo.destination(from: junction, bearing: 300, distance: 1)
        let leaving = [approachStart, junction, noise]

        let maneuver = ManeuverClassifier.maneuver(
            leaving: leaving,
            entering: exit(from: noise, bearing: 0)
        )
        XCTAssertEqual(maneuver, .straight)
    }
}

final class DegenerateGeometryTests: XCTestCase {
    func testEmptyGeometryIsUnknown() {
        XCTAssertEqual(
            ManeuverClassifier.maneuver(leaving: [], entering: exit(from: junction, bearing: 0)),
            .unknown
        )
        XCTAssertEqual(
            ManeuverClassifier.maneuver(leaving: approach(to: junction, bearing: 0), entering: []),
            .unknown
        )
    }

    func testSingleVertexIsUnknown() {
        XCTAssertEqual(
            ManeuverClassifier.maneuver(leaving: [junction], entering: exit(from: junction, bearing: 90)),
            .unknown
        )
    }

    func testRepeatedPointsAreUnknown() {
        XCTAssertEqual(
            ManeuverClassifier.maneuver(
                leaving: [junction, junction, junction],
                entering: exit(from: junction, bearing: 90)
            ),
            .unknown
        )
    }

    func testUnknownIsReturnedRatherThanAGuess() {
        XCTAssertNil(ManeuverClassifier.turn(leaving: [junction], entering: [junction]))
    }
}

final class RouteAnnotationTests: XCTestCase {
    /// Three legs: north, then right onto an east road, then left back to north.
    private func threeLegRoute() -> Route {
        let firstEnd = Geo.destination(from: junction, bearing: 0, distance: 200)
        let secondEnd = Geo.destination(from: firstEnd, bearing: 90, distance: 200)
        let thirdEnd = Geo.destination(from: secondEnd, bearing: 0, distance: 200)

        return Route(steps: [
            RouteStep(polyline: [junction, firstEnd], distance: 200, expectedTravelTime: 30, streetName: "First"),
            RouteStep(polyline: [firstEnd, secondEnd], distance: 200, expectedTravelTime: 30, streetName: "Second"),
            RouteStep(polyline: [secondEnd, thirdEnd], distance: 200, expectedTravelTime: 30, streetName: "Third"),
        ])
    }

    func testFirstStepIsAlwaysDeparture() {
        let annotated = ManeuverClassifier.annotated(threeLegRoute())
        XCTAssertEqual(annotated.steps[0].maneuver, .depart)
    }

    func testEachStepGetsTheTurnThatEntersIt() {
        let annotated = ManeuverClassifier.annotated(threeLegRoute())
        XCTAssertEqual(annotated.steps.map(\.maneuver), [.depart, .right, .left])
    }

    func testAnnotationKeepsEverythingElse() {
        let route = threeLegRoute()
        let annotated = ManeuverClassifier.annotated(route)

        XCTAssertEqual(annotated.steps.map(\.streetName), ["First", "Second", "Third"])
        XCTAssertEqual(annotated.distance, route.distance)
        XCTAssertEqual(annotated.expectedTravelTime, route.expectedTravelTime)
        XCTAssertEqual(annotated.polyline, route.polyline)
    }

    func testSingleStepRouteIsJustADeparture() {
        let route = Route(steps: [
            RouteStep(polyline: approach(to: junction, bearing: 0), distance: 120, expectedTravelTime: 20)
        ])
        XCTAssertEqual(ManeuverClassifier.annotated(route).steps.map(\.maneuver), [.depart])
    }

    func testEmptyRouteAnnotatesToNothing() {
        let annotated = ManeuverClassifier.annotated(Route(steps: []))
        XCTAssertTrue(annotated.steps.isEmpty)
    }
}

final class RouteStitchingTests: XCTestCase {
    func testJunctionVerticesAreNotDuplicated() {
        let middle = Geo.destination(from: junction, bearing: 0, distance: 100)
        let end = Geo.destination(from: middle, bearing: 90, distance: 100)

        let route = Route(steps: [
            RouteStep(polyline: [junction, middle], distance: 100, expectedTravelTime: 10),
            RouteStep(polyline: [middle, end], distance: 100, expectedTravelTime: 10),
        ])

        XCTAssertEqual(route.polyline, [junction, middle, end])
    }

    func testTotalsDefaultToTheSumOfTheSteps() {
        let route = Route(steps: [
            RouteStep(polyline: [junction], distance: 120, expectedTravelTime: 15),
            RouteStep(polyline: [junction], distance: 80, expectedTravelTime: 25),
        ])

        XCTAssertEqual(route.distance, 200, accuracy: 1e-9)
        XCTAssertEqual(route.expectedTravelTime, 40, accuracy: 1e-9)
    }

    func testReportedTotalsWinOverTheSum() {
        let route = Route(
            steps: [RouteStep(polyline: [junction], distance: 120, expectedTravelTime: 15)],
            distance: 999,
            expectedTravelTime: 111
        )

        XCTAssertEqual(route.distance, 999, accuracy: 1e-9)
        XCTAssertEqual(route.expectedTravelTime, 111, accuracy: 1e-9)
    }
}
