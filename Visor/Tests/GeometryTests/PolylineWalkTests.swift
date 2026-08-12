import Core
import XCTest
@testable import Geometry

private let istanbul = Coordinate(latitude: 41.0082, longitude: 28.9784)

final class PolylineWalkTests: XCTestCase {
    /// North for 100 m, then east for 100 m.
    private lazy var corner: [Coordinate] = {
        let middle = Geo.destination(from: istanbul, bearing: 0, distance: 100)
        return [istanbul, middle, Geo.destination(from: middle, bearing: 90, distance: 100)]
    }()

    func testLengthOfEmptyAndSingleVertexLinesIsZero() {
        XCTAssertEqual(Geo.length(of: []), 0)
        XCTAssertEqual(Geo.length(of: [istanbul]), 0)
    }

    func testLengthSumsTheSegments() {
        XCTAssertEqual(Geo.length(of: corner), 200, accuracy: 0.1)
    }

    func testWalkingReturnsNilOnlyForAnEmptyLine() {
        XCTAssertNil(Geo.coordinate(on: [], at: 10))
        XCTAssertEqual(Geo.coordinate(on: [istanbul], at: 10), istanbul)
    }

    func testWalkingLandsAtTheRightDistance() throws {
        for meters in [0.0, 25.0, 100.0, 150.0, 200.0] {
            let point = try XCTUnwrap(Geo.coordinate(on: corner, at: meters))
            let projection = try XCTUnwrap(Geo.project(point, onto: corner))
            XCTAssertEqual(projection.distanceAlongPolyline, meters, accuracy: 0.2, "at \(meters) m")
            XCTAssertEqual(projection.distance, 0, accuracy: 0.05, "at \(meters) m")
        }
    }

    func testWalkingCrossesTheCorner() throws {
        let afterCorner = try XCTUnwrap(Geo.coordinate(on: corner, at: 150))
        XCTAssertEqual(Geo.initialBearing(from: corner[1], to: afterCorner), 90, accuracy: 0.01)
    }

    func testWalkingClampsAtBothEnds() {
        XCTAssertEqual(Geo.coordinate(on: corner, at: -50), corner.first)
        XCTAssertEqual(Geo.coordinate(on: corner, at: 10_000), corner.last)
    }

    func testWalkingSkipsOverRepeatedVertices() throws {
        let doubled = [istanbul, istanbul, corner[1]]
        let point = try XCTUnwrap(Geo.coordinate(on: doubled, at: 40))
        XCTAssertEqual(Geo.distance(from: istanbul, to: point), 40, accuracy: 0.1)
    }
}
