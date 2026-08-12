import Core
import Foundation
import XCTest
@testable import Transport

/// A packet with every field set to something recognisable.
private func samplePacket(
    maneuver: ManeuverType = .right,
    toManeuver: Double = 250,
    remaining: Double = 3_400,
    time: Double = 512,
    speed: Double = 20,
    flags: HUDPacket.Flags = [],
    street: String? = nil
) -> HUDPacket {
    HUDPacket(
        maneuver: maneuver,
        distanceToManeuver: toManeuver,
        distanceRemaining: remaining,
        timeRemaining: time,
        speed: speed,
        flags: flags,
        streetName: street
    )
}

final class PacketLayoutTests: XCTestCase {
    func testTheHeaderIsTenBytes() {
        XCTAssertEqual(samplePacket().encoded().count, 10)
        XCTAssertEqual(HUDPacket.headerSize, 10)
    }

    func testVersionAndManeuverComeFirst() {
        let bytes = [UInt8](samplePacket(maneuver: .sharpLeft).encoded())

        XCTAssertEqual(bytes[0], 1)
        XCTAssertEqual(bytes[1], ManeuverType.sharpLeft.rawValue)
    }

    func testSixteenBitFieldsAreLittleEndian() {
        // 250 m is 0x00FA: low byte first.
        let bytes = [UInt8](samplePacket(toManeuver: 250).encoded())

        XCTAssertEqual(bytes[2], 0xFA)
        XCTAssertEqual(bytes[3], 0x00)
    }

    func testDistanceToTheDestinationIsInTensOfMeters() {
        let bytes = [UInt8](samplePacket(remaining: 3_400).encoded())
        let raw = UInt16(bytes[4]) | UInt16(bytes[5]) << 8

        XCTAssertEqual(raw, 340)
    }

    func testTimeIsInWholeSeconds() {
        let bytes = [UInt8](samplePacket(time: 512).encoded())
        let raw = UInt16(bytes[6]) | UInt16(bytes[7]) << 8

        XCTAssertEqual(raw, 512)
    }

    func testSpeedIsConvertedToKilometresPerHour() {
        // 20 m/s is 72 km/h.
        XCTAssertEqual([UInt8](samplePacket(speed: 20).encoded())[8], 72)
    }

    func testFlagsSitInTheirOwnBits() {
        XCTAssertEqual(HUDPacket.Flags.offRoute.rawValue, 0b001)
        XCTAssertEqual(HUDPacket.Flags.rerouting.rawValue, 0b010)
        XCTAssertEqual(HUDPacket.Flags.weakSignal.rawValue, 0b100)

        let all: HUDPacket.Flags = [.offRoute, .rerouting, .weakSignal]
        XCTAssertEqual([UInt8](samplePacket(flags: all).encoded())[9], 0b111)
        XCTAssertEqual([UInt8](samplePacket().encoded())[9], 0)
    }
}

final class PacketSaturationTests: XCTestCase {
    func testDistanceToTheManeuverPinsAtTheTopOfTheScale() {
        let bytes = [UInt8](samplePacket(toManeuver: 90_000).encoded(maximumSize: 10))
        XCTAssertEqual(UInt16(bytes[2]) | UInt16(bytes[3]) << 8, .max)
    }

    func testDistanceToTheDestinationPinsAtSixHundredAndFiftyKilometres() {
        let bytes = [UInt8](samplePacket(remaining: 2_000_000).encoded())
        XCTAssertEqual(UInt16(bytes[4]) | UInt16(bytes[5]) << 8, .max)
    }

    func testTimePinsRatherThanWrapping() {
        let bytes = [UInt8](samplePacket(time: 200_000).encoded())
        XCTAssertEqual(UInt16(bytes[6]) | UInt16(bytes[7]) << 8, .max)
    }

    func testSpeedPinsAtTwoHundredAndFiftyFive() {
        // 100 m/s is 360 km/h, which no motorcycle in the packet's range does,
        // but a bad fix can claim it.
        XCTAssertEqual([UInt8](samplePacket(speed: 100).encoded())[8], 255)
    }

    func testNegativeAndNonsenseValuesBecomeZero() {
        let broken = samplePacket(
            toManeuver: -50,
            remaining: .nan,
            time: -.infinity,
            speed: -3
        )
        let bytes = [UInt8](broken.encoded())

        XCTAssertEqual(UInt16(bytes[2]) | UInt16(bytes[3]) << 8, 0)
        XCTAssertEqual(UInt16(bytes[4]) | UInt16(bytes[5]) << 8, 0)
        XCTAssertEqual(UInt16(bytes[6]) | UInt16(bytes[7]) << 8, 0)
        XCTAssertEqual(bytes[8], 0)
    }

    func testValuesAreRoundedNotTruncated() {
        let bytes = [UInt8](samplePacket(toManeuver: 249.6, speed: 20.9).encoded())

        XCTAssertEqual(UInt16(bytes[2]) | UInt16(bytes[3]) << 8, 250)
        XCTAssertEqual(bytes[8], 75)
    }
}

final class StreetNameTests: XCTestCase {
    private let street = "Şemsettin Günaltay Caddesi"

    func testTheNameFollowsTheHeader() throws {
        let data = samplePacket(street: "Ege Sk.").encoded(maximumSize: 40)

        XCTAssertEqual(data.count, HUDPacket.headerSize + 7)
        XCTAssertEqual(String(decoding: data[HUDPacket.headerSize...], as: UTF8.self), "Ege Sk.")
    }

    func testNoNameLeavesTheHeaderAlone() {
        XCTAssertEqual(samplePacket(street: nil).encoded(maximumSize: 200).count, 10)
    }

    func testAnEmptyNameLeavesTheHeaderAlone() {
        XCTAssertEqual(samplePacket(street: "").encoded(maximumSize: 200).count, 10)
    }

    func testAMultiByteNameSurvivesIntact() throws {
        let data = samplePacket(street: street).encoded(maximumSize: 200)
        let decoded = try XCTUnwrap(DecodedPacket(data))

        XCTAssertEqual(decoded.streetName, street)
        // 26 characters but 28 bytes: the Ş and the ü take two each.
        XCTAssertEqual(data.count - HUDPacket.headerSize, 28)
    }

    func testALongNameIsCutToFit() throws {
        let data = samplePacket(street: street).encoded(maximumSize: 20)
        let decoded = try XCTUnwrap(DecodedPacket(data))

        XCTAssertEqual(data.count, 20)
        XCTAssertTrue(street.hasPrefix(decoded.streetName), "got \(decoded.streetName)")
    }

    func testACutNeverSplitsACharacter() throws {
        // Walk every budget across the name. At each one the bytes that come
        // out have to be a whole prefix of it: a name cut halfway through a Ş
        // is not a shorter name, it is a broken string.
        for budget in 0...40 {
            let data = samplePacket(street: street).encoded(maximumSize: HUDPacket.headerSize + budget)
            let tail = data[HUDPacket.headerSize...]
            let text = String(data: Data(tail), encoding: .utf8)

            XCTAssertNotNil(text, "budget \(budget) produced invalid UTF-8")
            XCTAssertTrue(street.hasPrefix(text ?? "!"), "budget \(budget) produced \(text ?? "nil")")
            XCTAssertLessThanOrEqual(tail.count, budget)
        }
    }

    func testTheCutKeepsAsMuchAsFits() {
        // "Şe" is three bytes, so a three byte budget takes both characters and
        // a two byte budget takes only the Ş.
        XCTAssertEqual(HUDPacket.fit("Şemsettin", into: 3), Array("Şe".utf8))
        XCTAssertEqual(HUDPacket.fit("Şemsettin", into: 2), Array("Ş".utf8))
        XCTAssertEqual(HUDPacket.fit("Şemsettin", into: 1), [])
    }

    func testTheHeaderIsNeverSacrificedForTheName() {
        // A link that cannot carry ten bytes gets ten bytes anyway: half a
        // header would read as a valid packet full of nonsense.
        XCTAssertEqual(samplePacket(street: street).encoded(maximumSize: 4).count, 10)
    }
}

final class PacketDecodingTests: XCTestCase {
    func testAPacketSurvivesTheRoundTrip() throws {
        let packet = samplePacket(
            maneuver: .uTurn,
            toManeuver: 1_250,
            remaining: 24_680,
            time: 1_830,
            speed: 25,
            flags: [.offRoute, .weakSignal],
            street: "Bağdat Caddesi"
        )
        let decoded = try XCTUnwrap(DecodedPacket(packet.encoded(maximumSize: 60)))

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.maneuver, .uTurn)
        XCTAssertEqual(decoded.distanceToManeuver, 1_250)
        XCTAssertEqual(decoded.distanceRemaining, 24_680)
        XCTAssertEqual(decoded.timeRemaining, 1_830)
        XCTAssertEqual(decoded.speed, 90)
        XCTAssertEqual(decoded.flags, [.offRoute, .weakSignal])
        XCTAssertEqual(decoded.streetName, "Bağdat Caddesi")
    }

    func testTheDestinationDistanceComesBackRoundedToTenMeters() throws {
        let decoded = try XCTUnwrap(DecodedPacket(samplePacket(remaining: 1_234).encoded()))
        XCTAssertEqual(decoded.distanceRemaining, 1_230)
    }

    func testShortDataIsNotAPacket() {
        XCTAssertNil(DecodedPacket(Data()))
        XCTAssertNil(DecodedPacket(Data(repeating: 0, count: 9)))
        XCTAssertNotNil(DecodedPacket(Data(repeating: 0, count: 10)))
    }

    func testAnUnknownManeuverDoesNotSinkThePacket() throws {
        var bytes = [UInt8](samplePacket().encoded())
        bytes[1] = 200

        let decoded = try XCTUnwrap(DecodedPacket(Data(bytes)))
        XCTAssertEqual(decoded.maneuver, .unknown)
    }

    func testAnUnknownVersionIsReportedRatherThanRejected() throws {
        var bytes = [UInt8](samplePacket().encoded())
        bytes[0] = 9

        let decoded = try XCTUnwrap(DecodedPacket(Data(bytes)))
        XCTAssertEqual(decoded.version, 9)
        XCTAssertEqual(decoded.distanceToManeuver, 250)
    }

    func testMangledTextDoesNotSinkThePacket() throws {
        var bytes = [UInt8](samplePacket(street: "Ege").encoded(maximumSize: 40))
        bytes[HUDPacket.headerSize] = 0xFF

        let decoded = try XCTUnwrap(DecodedPacket(Data(bytes)))
        XCTAssertEqual(decoded.distanceToManeuver, 250)
        XCTAssertFalse(decoded.streetName.isEmpty)
    }
}
