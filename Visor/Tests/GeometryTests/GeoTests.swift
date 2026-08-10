import Core
import XCTest
@testable import Geometry

/// One degree of latitude on the sphere we model, in meters.
private let degreeInMeters = Geo.earthRadius * .pi / 180

/// Somewhere in Istanbul; a mid-latitude anchor for cases where the equator
/// would hide a longitude-scaling mistake.
private let istanbul = Coordinate(latitude: 41.0082, longitude: 28.9784)

final class DistanceTests: XCTestCase {
    func testSamePointIsZeroApart() {
        XCTAssertEqual(Geo.distance(from: istanbul, to: istanbul), 0, accuracy: 1e-9)
    }

    func testOneDegreeOfLatitude() {
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 1, longitude: 0)
        XCTAssertEqual(Geo.distance(from: a, to: b), degreeInMeters, accuracy: 0.5)
    }

    func testOneDegreeOfLongitudeOnTheEquator() {
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 0, longitude: 1)
        XCTAssertEqual(Geo.distance(from: a, to: b), degreeInMeters, accuracy: 0.5)
    }

    func testLongitudeShrinksTowardsThePoles() {
        let a = Coordinate(latitude: 60, longitude: 0)
        let b = Coordinate(latitude: 60, longitude: 1)
        // cos(60 degrees) is exactly one half.
        XCTAssertEqual(Geo.distance(from: a, to: b), degreeInMeters / 2, accuracy: 1)
    }

    func testDistanceIsSymmetric() {
        let other = Geo.destination(from: istanbul, bearing: 217, distance: 4_300)
        XCTAssertEqual(
            Geo.distance(from: istanbul, to: other),
            Geo.distance(from: other, to: istanbul),
            accuracy: 1e-9
        )
    }
}

final class BearingTests: XCTestCase {
    func testCardinalDirections() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        let cases: [(Coordinate, Double)] = [
            (Coordinate(latitude: 1, longitude: 0), 0),
            (Coordinate(latitude: 0, longitude: 1), 90),
            (Coordinate(latitude: -1, longitude: 0), 180),
            (Coordinate(latitude: 0, longitude: -1), 270),
        ]
        for (target, expected) in cases {
            XCTAssertEqual(
                Geo.initialBearing(from: origin, to: target),
                expected,
                accuracy: 1e-9,
                "bearing towards \(target)"
            )
        }
    }

    func testBearingIsNeverNegative() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        let southWest = Coordinate(latitude: -1, longitude: -1)
        XCTAssertEqual(Geo.initialBearing(from: origin, to: southWest), 225, accuracy: 0.01)
    }

    func testBearingSurvivesTheAntimeridian() {
        let west = Coordinate(latitude: 0, longitude: 179.9)
        let east = Coordinate(latitude: 0, longitude: -179.9)
        XCTAssertEqual(Geo.initialBearing(from: west, to: east), 90, accuracy: 1e-9)
        XCTAssertEqual(Geo.initialBearing(from: east, to: west), 270, accuracy: 1e-9)
    }

    func testNormalizationFoldsFullTurns() {
        XCTAssertEqual(Geo.normalizedBearing(370), 10, accuracy: 1e-9)
        XCTAssertEqual(Geo.normalizedBearing(-10), 350, accuracy: 1e-9)
        XCTAssertEqual(Geo.normalizedBearing(720), 0, accuracy: 1e-9)
    }
}

final class DestinationTests: XCTestCase {
    func testDistanceRoundTrips() {
        let target = Geo.destination(from: istanbul, bearing: 73, distance: 250)
        XCTAssertEqual(Geo.distance(from: istanbul, to: target), 250, accuracy: 0.01)
    }

    func testBearingRoundTrips() {
        for bearing in stride(from: 0.0, to: 360.0, by: 37.0) {
            let target = Geo.destination(from: istanbul, bearing: bearing, distance: 1_200)
            let measured = Geo.initialBearing(from: istanbul, to: target)
            // Compared through the delta rather than raw equality: due north
            // comes back as either 0 or 359.999..., and both are correct.
            XCTAssertEqual(
                Geo.bearingDelta(from: bearing, to: measured),
                0,
                accuracy: 1e-6,
                "bearing \(bearing)"
            )
        }
    }

    func testZeroDistanceStaysPut() {
        let target = Geo.destination(from: istanbul, bearing: 123, distance: 0)
        XCTAssertEqual(Geo.distance(from: istanbul, to: target), 0, accuracy: 1e-9)
    }
}

final class BearingDeltaTests: XCTestCase {
    func testStraightAhead() {
        XCTAssertEqual(Geo.bearingDelta(from: 42, to: 42), 0, accuracy: 1e-9)
    }

    func testRightTurnIsPositive() {
        XCTAssertEqual(Geo.bearingDelta(from: 90, to: 180), 90, accuracy: 1e-9)
    }

    func testLeftTurnIsNegative() {
        XCTAssertEqual(Geo.bearingDelta(from: 180, to: 90), -90, accuracy: 1e-9)
    }

    func testWrappingAcrossNorthTakesTheShortWay() {
        XCTAssertEqual(Geo.bearingDelta(from: 350, to: 10), 20, accuracy: 1e-9)
        XCTAssertEqual(Geo.bearingDelta(from: 10, to: 350), -20, accuracy: 1e-9)
    }

    func testReversalReportsPositiveHalfTurnFromEitherSide() {
        XCTAssertEqual(Geo.bearingDelta(from: 0, to: 180), 180, accuracy: 1e-9)
        XCTAssertEqual(Geo.bearingDelta(from: 180, to: 0), 180, accuracy: 1e-9)
    }

    func testDeltaStaysWithinHalfTurn() {
        for from in stride(from: 0.0, to: 360.0, by: 13.0) {
            for to in stride(from: 0.0, to: 360.0, by: 17.0) {
                let delta = Geo.bearingDelta(from: from, to: to)
                XCTAssertGreaterThan(delta, -180.000001, "\(from) -> \(to)")
                XCTAssertLessThanOrEqual(delta, 180, "\(from) -> \(to)")
            }
        }
    }
}
