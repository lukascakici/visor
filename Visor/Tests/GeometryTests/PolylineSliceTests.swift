import Core
import XCTest
@testable import Geometry

private let istanbul = Coordinate(latitude: 41.0082, longitude: 28.9784)

final class PolylineSliceTests: XCTestCase {
    /// North for 100 m, then east for 100 m.
    private lazy var corner: [Coordinate] = {
        let middle = Geo.destination(from: istanbul, bearing: 0, distance: 100)
        return [istanbul, middle, Geo.destination(from: middle, bearing: 90, distance: 100)]
    }()

    func testASliceIsAsLongAsAsked() {
        XCTAssertEqual(Geo.length(of: Geo.slice(corner, from: 40, to: 160)), 120, accuracy: 0.2)
    }

    func testASliceStartsAndEndsWhereAsked() throws {
        let sliced = Geo.slice(corner, from: 40, to: 160)

        let first = try XCTUnwrap(Geo.project(try XCTUnwrap(sliced.first), onto: corner))
        let last = try XCTUnwrap(Geo.project(try XCTUnwrap(sliced.last), onto: corner))
        XCTAssertEqual(first.distanceAlongPolyline, 40, accuracy: 0.2)
        XCTAssertEqual(last.distanceAlongPolyline, 160, accuracy: 0.2)
    }

    func testASliceKeepsTheVerticesInBetween() {
        // The corner at 100 m has to survive, or the slice cuts it off.
        XCTAssertEqual(Geo.slice(corner, from: 40, to: 160).count, 3)
    }

    func testASliceWithinOneSegmentIsJustItsEnds() {
        XCTAssertEqual(Geo.slice(corner, from: 20, to: 60).count, 2)
    }

    func testAVertexOnACutIsNotDuplicated() {
        XCTAssertEqual(Geo.slice(corner, from: 100, to: 160).count, 2)
        XCTAssertEqual(Geo.slice(corner, from: 40, to: 100).count, 2)
    }

    func testTheEndsAreClamped() throws {
        let whole = Geo.slice(corner, from: -50, to: 10_000)

        XCTAssertEqual(try XCTUnwrap(whole.first), corner.first)
        XCTAssertEqual(try XCTUnwrap(whole.last), corner.last)
        XCTAssertEqual(Geo.length(of: whole), 200, accuracy: 0.2)
    }

    func testAnEmptyRangeCollapsesToAPoint() {
        let sliced = Geo.slice(corner, from: 70, to: 70)

        XCTAssertEqual(Geo.length(of: sliced), 0, accuracy: 1e-6)
        XCTAssertEqual(sliced.first, sliced.last)
    }

    func testABackwardsRangeIsTreatedAsEmpty() {
        XCTAssertEqual(Geo.length(of: Geo.slice(corner, from: 150, to: 50)), 0, accuracy: 1e-6)
    }

    func testDegenerateLinesComeBackUnchanged() {
        XCTAssertEqual(Geo.slice([], from: 0, to: 10), [])
        XCTAssertEqual(Geo.slice([istanbul], from: 0, to: 10), [istanbul])
    }

    func testDistancesMeasuredOnASliceAreRelativeToIt() throws {
        let sliced = Geo.slice(corner, from: 50, to: 200)
        let point = try XCTUnwrap(Geo.coordinate(on: corner, at: 120))
        let projection = try XCTUnwrap(Geo.project(point, onto: sliced))

        XCTAssertEqual(projection.distanceAlongPolyline, 70, accuracy: 0.2)
        XCTAssertEqual(projection.distance, 0, accuracy: 0.05)
    }
}
