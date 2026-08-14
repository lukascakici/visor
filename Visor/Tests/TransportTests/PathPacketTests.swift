import Core
import Foundation
import Guidance
import XCTest
@testable import Transport

private func point(_ right: Double, _ ahead: Double) -> RoutePath.Point {
    RoutePath.Point(right: right, ahead: ahead)
}

/// A short line coming from behind, turning right at the second point.
private let samplePath = RoutePath(
    points: [point(0, -100), point(0, 50), point(120, 50)],
    maneuverIndex: 1
)

final class PathPacketTests: XCTestCase {
    // MARK: - Layout

    func testTheHeaderSaysWhatIsInThePacket() {
        let bytes = [UInt8](PathPacket(samplePath).encoded(maximumSize: 200))

        XCTAssertEqual(bytes[0], PathPacket.version)
        XCTAssertEqual(bytes[1], 3)
        XCTAssertEqual(bytes[2], 1)
        XCTAssertEqual(bytes[3], 0)
        XCTAssertEqual(bytes.count, PathPacket.headerSize + 3 * PathPacket.pointSize)
    }

    func testAPointIsFourLittleEndianBytes() {
        let bytes = [UInt8](PathPacket(RoutePath(points: [point(1, -2)], maneuverIndex: nil)).encoded(maximumSize: 200))

        // 1 m right is 10 decimeters, 2 m behind is -20.
        XCTAssertEqual(Array(bytes[4...7]), [10, 0, 0xEC, 0xFF])
    }

    func testNoManeuverIsSaidSoRatherThanGuessed() {
        let bytes = [UInt8](PathPacket(RoutePath(points: [point(0, 10)], maneuverIndex: nil)).encoded(maximumSize: 200))

        XCTAssertEqual(bytes[2], PathPacket.noManeuver)
    }

    func testAnEmptyPathIsJustAHeader() throws {
        let data = PathPacket(.empty).encoded(maximumSize: 200)

        XCTAssertEqual(data.count, PathPacket.headerSize)
        let decoded = try XCTUnwrap(DecodedPath(data))
        XCTAssertEqual(decoded.points, [])
        XCTAssertNil(decoded.maneuverIndex)
    }

    // MARK: - Numbers

    func testPositionsSurviveToATenthOfAMeter() throws {
        let path = RoutePath(points: [point(12.34, -56.78)], maneuverIndex: nil)
        let decoded = try XCTUnwrap(DecodedPath(PathPacket(path).encoded(maximumSize: 200)))

        XCTAssertEqual(decoded.points[0], DecodedPath.Point(right: 123, ahead: -568))
    }

    func testPositionsBeyondTheRangeSaturate() throws {
        // Nothing this far out is ever drawn, but a value that wrapped would
        // put a piece of road on the wrong side of the rider.
        let path = RoutePath(points: [point(9_000, -9_000)], maneuverIndex: nil)
        let decoded = try XCTUnwrap(DecodedPath(PathPacket(path).encoded(maximumSize: 200)))

        XCTAssertEqual(decoded.points[0].right, Int(Int16.max))
        XCTAssertEqual(decoded.points[0].ahead, Int(Int16.min))
    }

    func testNonsenseNumbersBecomeZeroRatherThanRubbish() throws {
        // Neither of these can come out of the geometry, so there is no right
        // answer to give; zero is the same one the guidance packet gives, and
        // one convention beats two.
        let path = RoutePath(points: [point(.nan, .infinity)], maneuverIndex: nil)
        let decoded = try XCTUnwrap(DecodedPath(PathPacket(path).encoded(maximumSize: 200)))

        XCTAssertEqual(decoded.points[0], DecodedPath.Point(right: 0, ahead: 0))
    }

    // MARK: - Fitting the link

    func testTheRoomInAWriteIsCountedInWholePoints() {
        XCTAssertEqual(PathPacket.points(fitting: 20), 4)
        XCTAssertEqual(PathPacket.points(fitting: 23), 4)
        XCTAssertEqual(PathPacket.points(fitting: 244), 60)
        // A write with no room for a whole point carries none, rather than
        // half of one.
        XCTAssertEqual(PathPacket.points(fitting: 4), 0)
        XCTAssertEqual(PathPacket.points(fitting: 0), 0)
    }

    func testASmallWriteShortensTheRoadRatherThanBreakingIt() throws {
        let long = RoutePath(points: (0..<40).map { point(0, Double($0) * 10) }, maneuverIndex: nil)
        let data = PathPacket(long).encoded(maximumSize: 20)

        XCTAssertEqual(data.count, 20)
        let decoded = try XCTUnwrap(DecodedPath(data))
        XCTAssertEqual(decoded.points.count, 4)
        XCTAssertEqual(decoded.points.first, DecodedPath.Point(right: 0, ahead: 0))
    }

    func testAJunctionThatDoesNotFitIsNotMarked() throws {
        // The turn is the tenth point and only four fit. Marking a point that
        // was left behind would draw the turn at the wrong bend.
        let long = RoutePath(points: (0..<40).map { point(0, Double($0) * 10) }, maneuverIndex: 10)
        let decoded = try XCTUnwrap(DecodedPath(PathPacket(long).encoded(maximumSize: 20)))

        XCTAssertNil(decoded.maneuverIndex)
    }

    // MARK: - Reading it back

    func testAWholePathSurvivesTheRoundTrip() throws {
        let decoded = try XCTUnwrap(DecodedPath(PathPacket(samplePath).encoded(maximumSize: 200)))

        XCTAssertEqual(decoded.version, PathPacket.version)
        XCTAssertEqual(decoded.maneuverIndex, 1)
        XCTAssertEqual(decoded.points, [
            DecodedPath.Point(right: 0, ahead: -1_000),
            DecodedPath.Point(right: 0, ahead: 500),
            DecodedPath.Point(right: 1_200, ahead: 500),
        ])
    }

    func testTooFewBytesForAHeaderIsNotAPacket() {
        XCTAssertNil(DecodedPath(Data()))
        XCTAssertNil(DecodedPath(Data([1, 2, 3])))
    }

    func testAPacketCutShortGivesUpWhatArrived() throws {
        // Says three points, carries one and a half. The one that made it is
        // still road worth drawing.
        var data = PathPacket(samplePath).encoded(maximumSize: 200)
        data = data.prefix(PathPacket.headerSize + PathPacket.pointSize + 2)

        let decoded = try XCTUnwrap(DecodedPath(data))
        XCTAssertEqual(decoded.points, [DecodedPath.Point(right: 0, ahead: -1_000)])
        // The junction it named is no longer among them.
        XCTAssertNil(decoded.maneuverIndex)
    }

    func testAVersionFromTheFutureIsReportedNotRefused() throws {
        var data = PathPacket(samplePath).encoded(maximumSize: 200)
        data[0] = 9

        let decoded = try XCTUnwrap(DecodedPath(data))
        XCTAssertEqual(decoded.version, 9)
        XCTAssertEqual(decoded.points.count, 3)
    }
}
