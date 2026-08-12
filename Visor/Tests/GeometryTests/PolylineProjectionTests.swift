import Core
import XCTest
@testable import Geometry

private let istanbul = Coordinate(latitude: 41.0082, longitude: 28.9784)

/// Builds a polyline by walking `legs` of (bearing, meters) from `start`.
/// Every vertex is placed by the same geometry the projection is tested
/// against, which keeps the expected values in the tests readable.
private func polyline(from start: Coordinate, legs: [(bearing: Double, meters: Double)]) -> [Coordinate] {
    var vertices = [start]
    for leg in legs {
        vertices.append(Geo.destination(from: vertices[vertices.count - 1], bearing: leg.bearing, distance: leg.meters))
    }
    return vertices
}

final class PolylineProjectionTests: XCTestCase {
    /// Two 100 m legs heading due north.
    private let straight = polyline(from: istanbul, legs: [(0, 100), (0, 100)])

    func testEmptyPolylineHasNoProjection() {
        XCTAssertNil(Geo.project(istanbul, onto: []))
    }

    func testSingleVertexProjectsOntoThatVertex() {
        let point = Geo.destination(from: istanbul, bearing: 45, distance: 25)
        let projection = Geo.project(point, onto: [istanbul])

        XCTAssertEqual(projection?.point, istanbul)
        XCTAssertEqual(projection?.distance ?? .nan, 25, accuracy: 0.05)
        XCTAssertEqual(projection?.segmentIndex, 0)
        XCTAssertEqual(projection?.fraction ?? .nan, 0, accuracy: 1e-9)
        XCTAssertEqual(projection?.distanceAlongPolyline ?? .nan, 0, accuracy: 1e-9)
    }

    func testPointOnTheLineHasNoOffset() throws {
        let onLine = Geo.destination(from: istanbul, bearing: 0, distance: 150)
        let projection = try XCTUnwrap(Geo.project(onLine, onto: straight))

        XCTAssertEqual(projection.distance, 0, accuracy: 0.05)
        XCTAssertEqual(projection.distanceAlongPolyline, 150, accuracy: 0.1)
        XCTAssertEqual(projection.segmentIndex, 1)
        XCTAssertEqual(projection.fraction, 0.5, accuracy: 0.005)
    }

    func testPerpendicularOffsetIsMeasuredInMeters() throws {
        let onLine = Geo.destination(from: istanbul, bearing: 0, distance: 50)
        let offRoute = Geo.destination(from: onLine, bearing: 90, distance: 40)
        let projection = try XCTUnwrap(Geo.project(offRoute, onto: straight))

        XCTAssertEqual(projection.distance, 40, accuracy: 0.1)
        XCTAssertEqual(projection.distanceAlongPolyline, 50, accuracy: 0.1)
        XCTAssertEqual(projection.segmentIndex, 0)
        XCTAssertEqual(projection.fraction, 0.5, accuracy: 0.005)
    }

    func testOffsetIsTheSameOnEitherSide() throws {
        let onLine = Geo.destination(from: istanbul, bearing: 0, distance: 120)
        let east = try XCTUnwrap(Geo.project(Geo.destination(from: onLine, bearing: 90, distance: 40), onto: straight))
        let west = try XCTUnwrap(Geo.project(Geo.destination(from: onLine, bearing: 270, distance: 40), onto: straight))

        XCTAssertEqual(east.distance, west.distance, accuracy: 0.01)
        XCTAssertEqual(east.distanceAlongPolyline, west.distanceAlongPolyline, accuracy: 0.01)
    }

    func testPointBeforeTheStartClampsToTheFirstVertex() throws {
        let behind = Geo.destination(from: istanbul, bearing: 180, distance: 30)
        let projection = try XCTUnwrap(Geo.project(behind, onto: straight))

        XCTAssertEqual(projection.distance, 30, accuracy: 0.1)
        XCTAssertEqual(projection.distanceAlongPolyline, 0, accuracy: 0.05)
        XCTAssertEqual(projection.segmentIndex, 0)
        XCTAssertEqual(projection.fraction, 0, accuracy: 1e-9)
    }

    func testPointBeyondTheEndClampsToTheLastVertex() throws {
        let ahead = Geo.destination(from: straight[straight.count - 1], bearing: 0, distance: 30)
        let projection = try XCTUnwrap(Geo.project(ahead, onto: straight))

        XCTAssertEqual(projection.distance, 30, accuracy: 0.1)
        XCTAssertEqual(projection.distanceAlongPolyline, 200, accuracy: 0.1)
        XCTAssertEqual(projection.segmentIndex, 1)
        XCTAssertEqual(projection.fraction, 1, accuracy: 1e-9)
    }

    func testNearestSegmentWinsOnACorner() throws {
        // North for 100 m, then a right angle east for 100 m.
        let corner = polyline(from: istanbul, legs: [(0, 100), (90, 100)])
        let onEastLeg = Geo.destination(from: corner[1], bearing: 90, distance: 60)
        let nearEastLeg = Geo.destination(from: onEastLeg, bearing: 0, distance: 10)

        let projection = try XCTUnwrap(Geo.project(nearEastLeg, onto: corner))

        XCTAssertEqual(projection.segmentIndex, 1)
        XCTAssertEqual(projection.distance, 10, accuracy: 0.1)
        XCTAssertEqual(projection.distanceAlongPolyline, 160, accuracy: 0.2)
    }

    func testInsideACornerTheCloserLegWins() throws {
        let corner = polyline(from: istanbul, legs: [(0, 100), (90, 100)])
        // Right next to the north leg, far from the east leg.
        let point = Geo.destination(from: Geo.destination(from: istanbul, bearing: 0, distance: 20), bearing: 90, distance: 5)

        let projection = try XCTUnwrap(Geo.project(point, onto: corner))

        XCTAssertEqual(projection.segmentIndex, 0)
        XCTAssertEqual(projection.distance, 5, accuracy: 0.1)
    }

    func testDuplicatedVerticesDoNotBreakProjection() throws {
        let duplicated = [istanbul, istanbul, Geo.destination(from: istanbul, bearing: 0, distance: 100)]
        let point = Geo.destination(from: istanbul, bearing: 0, distance: 40)

        let projection = try XCTUnwrap(Geo.project(point, onto: duplicated))

        XCTAssertEqual(projection.distance, 0, accuracy: 0.05)
        XCTAssertEqual(projection.distanceAlongPolyline, 40, accuracy: 0.1)
        XCTAssertFalse(projection.fraction.isNaN)
    }

    func testDistanceAlongGrowsMonotonicallyAlongTheRoute() throws {
        let route = polyline(from: istanbul, legs: [(0, 100), (45, 100), (90, 100)])
        var previous = -1.0

        for meters in stride(from: 0.0, through: 280.0, by: 20.0) {
            // Walk the route by projecting points that sit on it.
            let onRoute = try XCTUnwrap(Geo.coordinate(on: route, at: meters))
            let along = try XCTUnwrap(Geo.project(onRoute, onto: route))
            XCTAssertGreaterThan(along.distanceAlongPolyline, previous, "at \(meters) m")
            previous = along.distanceAlongPolyline
        }
    }
}
