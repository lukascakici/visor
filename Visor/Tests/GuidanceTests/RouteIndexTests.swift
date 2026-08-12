import Core
import Geometry
import XCTest
@testable import Guidance

private let start = Coordinate(latitude: 41.0082, longitude: 28.9784)

/// Three 200 m legs, 30 seconds each: north, right onto an east road, left back
/// onto a north road. Long enough that the maneuvers classify unambiguously.
///
/// Each step is labelled with the road it leads onto, which is the convention:
/// a step's name belongs to the maneuver that ends it.
private func threeLegRoute() -> Route {
    let first = Geo.destination(from: start, bearing: 0, distance: 200)
    let second = Geo.destination(from: first, bearing: 90, distance: 200)
    let third = Geo.destination(from: second, bearing: 0, distance: 200)

    return ManeuverClassifier.annotated(
        Route(steps: [
            RouteStep(polyline: [start, first], distance: 200, expectedTravelTime: 30, streetName: "Second"),
            RouteStep(polyline: [first, second], distance: 200, expectedTravelTime: 30, streetName: "Third"),
            RouteStep(polyline: [second, third], distance: 200, expectedTravelTime: 30, streetName: "Destination"),
        ])
    )
}

final class RouteIndexMeasurementTests: XCTestCase {
    func testStepOffsetsFollowTheGeometry() {
        let index = RouteIndex(threeLegRoute())
        XCTAssertEqual(index.stepOffsets.count, 3)
        XCTAssertEqual(index.stepOffsets[0], 0, accuracy: 0.01)
        XCTAssertEqual(index.stepOffsets[1], 200, accuracy: 0.1)
        XCTAssertEqual(index.stepOffsets[2], 400, accuracy: 0.2)
        XCTAssertEqual(index.length, 600, accuracy: 0.3)
    }

    func testRemainingTimeIsAccumulatedFromTheEnd() {
        let index = RouteIndex(threeLegRoute())
        XCTAssertEqual(index.timeAfterStep, [60, 30, 0])
    }

    func testAGapBetweenStepsIsCountedInTheOffsets() {
        // Two legs that do not meet: 50 m of connector between them.
        let firstEnd = Geo.destination(from: start, bearing: 0, distance: 100)
        let secondStart = Geo.destination(from: firstEnd, bearing: 0, distance: 50)
        let secondEnd = Geo.destination(from: secondStart, bearing: 0, distance: 100)

        let index = RouteIndex(Route(steps: [
            RouteStep(polyline: [start, firstEnd], distance: 100, expectedTravelTime: 10),
            RouteStep(polyline: [secondStart, secondEnd], distance: 100, expectedTravelTime: 10),
        ]))

        XCTAssertEqual(index.stepOffsets[1], 150, accuracy: 0.1)
        XCTAssertEqual(index.length, 250, accuracy: 0.2)

        // The second step still starts exactly where its offset says it does.
        let progress = index.progress(at: secondStart)
        XCTAssertEqual(progress?.stepIndex, 1)
        XCTAssertEqual(progress?.distanceTravelled ?? .nan, 150, accuracy: 0.2)
    }
}

final class RouteProgressTests: XCTestCase {
    private let index = RouteIndex(threeLegRoute())

    func testAtTheStartTheWholeRouteIsAhead() throws {
        let progress = try XCTUnwrap(index.progress(at: start))

        XCTAssertEqual(progress.distanceTravelled, 0, accuracy: 0.05)
        XCTAssertEqual(progress.distanceRemaining, 600, accuracy: 0.3)
        XCTAssertEqual(progress.stepIndex, 0)
        XCTAssertEqual(progress.timeRemaining, 90, accuracy: 0.05)
    }

    func testTheManeuverAheadIsTheOneEndingTheCurrentStep() throws {
        let progress = try XCTUnwrap(index.progress(at: start))

        XCTAssertEqual(progress.maneuver, .right)
        XCTAssertEqual(progress.distanceToManeuver, 200, accuracy: 0.1)
    }

    func testTheStreetNameIsTheRoadBeingTurnedOnto() throws {
        let progress = try XCTUnwrap(index.progress(at: start))
        XCTAssertEqual(progress.streetName, "Second")
    }

    /// One junction, described by two steps: the shape of the turn comes from
    /// the step being entered, the words for it from the step being left. Map
    /// services put the words there, and the display has to read them from the
    /// same place or every instruction lands one junction out.
    func testTheLabelAndTheArrowDescribeTheSameJunction() throws {
        let progress = try XCTUnwrap(index.progress(at: start))

        XCTAssertEqual(progress.maneuver, index.route.steps[1].maneuver)
        XCTAssertEqual(progress.streetName, index.route.steps[0].streetName)
    }

    func testProgressPartwayThroughAStep() throws {
        let here = try XCTUnwrap(Geo.coordinate(on: index.route.polyline, at: 100))
        let progress = try XCTUnwrap(index.progress(at: here))

        XCTAssertEqual(progress.distanceTravelled, 100, accuracy: 0.2)
        XCTAssertEqual(progress.distanceRemaining, 500, accuracy: 0.3)
        XCTAssertEqual(progress.distanceToManeuver, 100, accuracy: 0.2)
        // Half of the current step's 30 seconds, plus 60 for the rest.
        XCTAssertEqual(progress.timeRemaining, 75, accuracy: 0.1)
    }

    func testCrossingIntoTheNextStep() throws {
        let here = try XCTUnwrap(Geo.coordinate(on: index.route.polyline, at: 250))
        let progress = try XCTUnwrap(index.progress(at: here))

        XCTAssertEqual(progress.stepIndex, 1)
        XCTAssertEqual(progress.maneuver, .left)
        XCTAssertEqual(progress.distanceToManeuver, 150, accuracy: 0.2)
        XCTAssertEqual(progress.streetName, "Third")
    }

    func testAStepBoundaryBelongsToTheStepBeingEntered() throws {
        let atJunction = try XCTUnwrap(Geo.coordinate(on: index.route.polyline, at: 200))
        let progress = try XCTUnwrap(index.progress(at: atJunction))

        XCTAssertEqual(progress.stepIndex, 1)
        XCTAssertEqual(progress.distanceToManeuver, 200, accuracy: 0.2)
    }

    func testTheFinalStepPointsAtTheDestination() throws {
        let here = try XCTUnwrap(Geo.coordinate(on: index.route.polyline, at: 500))
        let progress = try XCTUnwrap(index.progress(at: here))

        XCTAssertEqual(progress.stepIndex, 2)
        XCTAssertEqual(progress.maneuver, .arrive)
        XCTAssertEqual(progress.distanceToManeuver, 100, accuracy: 0.2)
        // The last step ends at the destination, so that is what it is called.
        XCTAssertEqual(progress.streetName, "Destination")
    }

    func testPastTheDestinationNothingGoesNegative() throws {
        let beyond = Geo.destination(from: index.route.polyline.last!, bearing: 0, distance: 80)
        let progress = try XCTUnwrap(index.progress(at: beyond))

        XCTAssertEqual(progress.distanceRemaining, 0, accuracy: 0.05)
        XCTAssertEqual(progress.distanceToManeuver, 0, accuracy: 0.05)
        XCTAssertEqual(progress.timeRemaining, 0, accuracy: 0.05)
        XCTAssertEqual(progress.maneuver, .arrive)
    }

    func testBeforeTheStartProgressClampsToZero() throws {
        let behind = Geo.destination(from: start, bearing: 180, distance: 60)
        let progress = try XCTUnwrap(index.progress(at: behind))

        XCTAssertEqual(progress.distanceTravelled, 0, accuracy: 0.05)
        XCTAssertEqual(progress.stepIndex, 0)
        XCTAssertEqual(progress.timeRemaining, 90, accuracy: 0.05)
    }

    func testBeingOffToTheSideDoesNotDisturbTheDistances() throws {
        let onRoute = try XCTUnwrap(Geo.coordinate(on: index.route.polyline, at: 100))
        let aside = Geo.destination(from: onRoute, bearing: 90, distance: 40)
        let progress = try XCTUnwrap(index.progress(at: aside))

        XCTAssertEqual(progress.distanceFromRoute, 40, accuracy: 0.2)
        XCTAssertEqual(progress.distanceTravelled, 100, accuracy: 0.3)
        XCTAssertEqual(progress.distanceToManeuver, 100, accuracy: 0.3)
    }

    func testDistancesShrinkAndNeverGrowAlongTheRoute() throws {
        var previousRemaining = Double.infinity
        var previousTime = Double.infinity

        for meters in stride(from: 0.0, through: 600.0, by: 25.0) {
            let here = try XCTUnwrap(Geo.coordinate(on: index.route.polyline, at: meters))
            let progress = try XCTUnwrap(index.progress(at: here))

            XCTAssertLessThan(progress.distanceRemaining, previousRemaining + 0.5, "at \(meters) m")
            XCTAssertLessThan(progress.timeRemaining, previousTime + 0.5, "at \(meters) m")
            previousRemaining = progress.distanceRemaining
            previousTime = progress.timeRemaining
        }
    }
}

final class DegenerateRouteProgressTests: XCTestCase {
    func testAnEmptyRouteHasNoProgress() {
        XCTAssertNil(RouteIndex(Route(steps: [])).progress(at: start))
    }

    func testASingleStepRouteIsAlwaysHeadingForArrival() throws {
        let end = Geo.destination(from: start, bearing: 0, distance: 300)
        let index = RouteIndex(ManeuverClassifier.annotated(
            Route(steps: [
                RouteStep(polyline: [start, end], distance: 300, expectedTravelTime: 45, streetName: "Only")
            ])
        ))

        let progress = try XCTUnwrap(index.progress(at: start))
        XCTAssertEqual(progress.maneuver, .arrive)
        XCTAssertEqual(progress.distanceToManeuver, 300, accuracy: 0.2)
        XCTAssertEqual(progress.streetName, "Only")
    }

    func testAZeroLengthStepDoesNotProduceNonsense() throws {
        let end = Geo.destination(from: start, bearing: 0, distance: 100)
        let index = RouteIndex(Route(steps: [
            RouteStep(polyline: [start, start], distance: 0, expectedTravelTime: 5),
            RouteStep(polyline: [start, end], distance: 100, expectedTravelTime: 20),
        ]))

        let progress = try XCTUnwrap(index.progress(at: start))
        XCTAssertFalse(progress.timeRemaining.isNaN)
        XCTAssertFalse(progress.distanceToManeuver.isNaN)
        XCTAssertEqual(progress.distanceRemaining, 100, accuracy: 0.1)
    }
}
