import Core
import XCTest
@testable import Geometry

private let istanbul = Coordinate(latitude: 41.0082, longitude: 28.9784)

final class SimplifyTests: XCTestCase {
    /// Due north, a vertex every 20 m, perfectly straight.
    private let straight: [Coordinate] = (0...10).map {
        Geo.destination(from: istanbul, bearing: 0, distance: Double($0) * 20)
    }

    /// North for 100 m then east for 100 m, with vertices every 25 m along the
    /// way, so the corner is one vertex among many.
    private lazy var corner: [Coordinate] = {
        let turn = Geo.destination(from: istanbul, bearing: 0, distance: 100)
        let up = (0...4).map { Geo.destination(from: istanbul, bearing: 0, distance: Double($0) * 25) }
        let across = (1...4).map { Geo.destination(from: turn, bearing: 90, distance: Double($0) * 25) }
        return up + across
    }()

    /// Half a circle of radius 300 m, 200 vertices around it. Stands in for a
    /// road that curves the whole way: nothing here is redundant, so every
    /// vertex dropped costs shape.
    private let arc: [Coordinate] = (0..<200).map {
        Geo.destination(from: istanbul, bearing: Double($0) * 0.9, distance: 300)
    }

    // MARK: - Simplifying to a tolerance

    func testAStraightLineKeepsOnlyItsEnds() {
        XCTAssertEqual(Geo.simplify(straight, tolerance: 2), [straight.first, straight.last].compactMap { $0 })
    }

    func testACornerSurvives() {
        let simplified = Geo.simplify(corner, tolerance: 2)

        XCTAssertEqual(simplified.count, 3)
        XCTAssertEqual(simplified[1], corner[4])
    }

    func testDetailWithinTheToleranceIsDropped() {
        // A straight road with half a meter of wobble either side of it. Real
        // route geometry looks like this, and none of it is worth a byte.
        let wobbly = (0...10).map { index -> Coordinate in
            let along = Geo.destination(from: istanbul, bearing: 0, distance: Double(index) * 10)
            return Geo.destination(from: along, bearing: 90, distance: index.isMultiple(of: 2) ? 0.5 : -0.5)
        }

        XCTAssertEqual(Geo.simplify(wobbly, tolerance: 2).count, 2)
        // The same wobble against a tighter tolerance is shape, not noise.
        XCTAssertGreaterThan(Geo.simplify(wobbly, tolerance: 0.1).count, 2)
    }

    func testNothingStrandedFurtherOffThanTheTolerance() throws {
        let tolerance = 5.0
        let simplified = Geo.simplify(arc, tolerance: tolerance)

        // The promise the tolerance makes: every vertex left out still lies on
        // the line that replaced it, to within the tolerance.
        for vertex in arc {
            let projection = try XCTUnwrap(Geo.project(vertex, onto: simplified))
            XCTAssertLessThanOrEqual(projection.distance, tolerance + 1e-6)
        }
    }

    func testKeptVerticesAreTheOriginalOnes() {
        for vertex in Geo.simplify(arc, tolerance: 5) {
            XCTAssertTrue(arc.contains(vertex))
        }
    }

    func testTheEndsAreAlwaysKept() {
        let simplified = Geo.simplify(arc, tolerance: 10_000)

        XCTAssertEqual(simplified, [arc.first, arc.last].compactMap { $0 })
    }

    func testShortAndDegenerateLinesComeBackUnchanged() {
        XCTAssertEqual(Geo.simplify([], tolerance: 2), [])
        XCTAssertEqual(Geo.simplify([istanbul], tolerance: 2), [istanbul])
        XCTAssertEqual(Geo.simplify(Array(straight.prefix(2)), tolerance: 2), Array(straight.prefix(2)))
        XCTAssertEqual(Geo.simplify(arc, tolerance: 0), arc)
    }

    // MARK: - Simplifying to a budget

    func testABudgetIsRespected() {
        XCTAssertLessThanOrEqual(Geo.simplify(arc, toAtMost: 20).count, 20)
        XCTAssertLessThanOrEqual(Geo.simplify(arc, toAtMost: 4).count, 4)
        XCTAssertEqual(Geo.simplify(arc, toAtMost: 2).count, 2)
    }

    func testABiggerBudgetBuysMoreShape() {
        // Not merely "fits": the search is supposed to spend what it is given.
        XCTAssertGreaterThan(
            Geo.simplify(arc, toAtMost: 40).count,
            Geo.simplify(arc, toAtMost: 8).count
        )
    }

    func testALineAlreadyWithinBudgetIsUntouched() {
        XCTAssertEqual(Geo.simplify(corner, toAtMost: 50), corner)
        XCTAssertEqual(Geo.simplify(straight, toAtMost: straight.count), straight)
    }

    func testABudgetTooSmallForALineStillReturnsSomething() {
        // Nothing sensible can be drawn from these, but a caller sizing a
        // packet down to nothing should get an empty answer, not a crash.
        XCTAssertEqual(Geo.simplify(arc, toAtMost: 1), [arc.first].compactMap { $0 })
        XCTAssertEqual(Geo.simplify(arc, toAtMost: 0), [])
        XCTAssertEqual(Geo.simplify(arc, toAtMost: -3), [])
    }
}
