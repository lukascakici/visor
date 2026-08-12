import Core
import CoreLocation
import Foundation
import MapKit
import XCTest
@testable import Routing

// What can be tested here is everything except the network call: MKRoute has no
// public initializer, so the conversion is exercised through the pieces it is
// built from. Asking MapKit for a real route is a thing to try by hand, not in
// a unit test that has to pass on a train.

private let istanbul = Coordinate(latitude: 41.0082, longitude: 28.9784)

final class CoordinateBridgeTests: XCTestCase {
    func testCoordinatesSurviveTheRoundTrip() {
        let there = Coordinate(istanbul.asCLCoordinate)

        XCTAssertEqual(there.latitude, istanbul.latitude, accuracy: 1e-12)
        XCTAssertEqual(there.longitude, istanbul.longitude, accuracy: 1e-12)
    }

    func testAReadingKeepsCoreLocationsInvalidValueConventions() {
        let location = CLLocation(
            coordinate: istanbul.asCLCoordinate,
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let fix = LocationFix(location)

        XCTAssertFalse(fix.isValid)
        XCTAssertEqual(fix.speed, -1)
        XCTAssertEqual(fix.course, -1)
    }

    func testAUsableReadingComesAcrossIntact() {
        let location = CLLocation(
            coordinate: istanbul.asCLCoordinate,
            altitude: 40,
            horizontalAccuracy: 6,
            verticalAccuracy: 3,
            course: 217,
            speed: 13.5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let fix = LocationFix(location)

        XCTAssertTrue(fix.isValid)
        XCTAssertEqual(fix.coordinate, istanbul)
        XCTAssertEqual(fix.speed, 13.5, accuracy: 1e-9)
        XCTAssertEqual(fix.course, 217, accuracy: 1e-9)
        XCTAssertEqual(fix.horizontalAccuracy, 6, accuracy: 1e-9)
    }
}

final class PolylineBridgeTests: XCTestCase {
    func testVerticesComeOutInOrder() {
        let points = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.1, longitude: 29.1),
            CLLocationCoordinate2D(latitude: 41.2, longitude: 29.2),
        ]
        let coordinates = MKPolyline(coordinates: points, count: points.count).asCoordinates

        XCTAssertEqual(coordinates.count, 3)
        XCTAssertEqual(coordinates.first?.latitude ?? .nan, 41.0, accuracy: 1e-6)
        XCTAssertEqual(coordinates.last?.longitude ?? .nan, 29.2, accuracy: 1e-6)
    }

    func testAnEmptyPolylineGivesNoVertices() {
        XCTAssertTrue(MKPolyline(coordinates: [], count: 0).asCoordinates.isEmpty)
    }
}

final class StepTimingTests: XCTestCase {
    func testTimeIsSharedOutByDistance() {
        let times = StepTiming.distribute(100, across: [100, 300])

        XCTAssertEqual(times[0], 25, accuracy: 1e-9)
        XCTAssertEqual(times[1], 75, accuracy: 1e-9)
    }

    func testTheSharesAddUpToTheWhole() {
        let times = StepTiming.distribute(937, across: [12, 480, 33, 2_100, 7])
        XCTAssertEqual(times.reduce(0, +), 937, accuracy: 1e-6)
    }

    func testStepsWithNoLengthGetNoTime() {
        let times = StepTiming.distribute(60, across: [0, 100, 0])

        XCTAssertEqual(times[0], 0, accuracy: 1e-9)
        XCTAssertEqual(times[1], 60, accuracy: 1e-9)
        XCTAssertEqual(times[2], 0, accuracy: 1e-9)
    }

    func testARouteWithNoLengthAtAllSplitsEvenly() {
        // Nonsense in, but a list of NaNs out would spread that nonsense into
        // every ETA downstream.
        let times = StepTiming.distribute(90, across: [0, 0, 0])

        XCTAssertEqual(times, [30, 30, 30])
        XCTAssertFalse(times.contains { $0.isNaN })
    }

    func testNonsenseDistancesAreTreatedAsZero() {
        let times = StepTiming.distribute(100, across: [.nan, 100, -50])

        XCTAssertEqual(times[1], 100, accuracy: 1e-9)
        XCTAssertFalse(times.contains { $0.isNaN })
    }

    func testNoStepsMeansNoTimes() {
        XCTAssertTrue(StepTiming.distribute(100, across: []).isEmpty)
    }
}
