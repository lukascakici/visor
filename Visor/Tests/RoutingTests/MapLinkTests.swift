import Core
import XCTest
@testable import Routing

/// Somewhere in Kadikoy, which is what all of these links point at.
private let there = Coordinate(latitude: 40.9782, longitude: 29.0640)

private func near(_ link: MapLink?, _ expected: Coordinate, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    guard let link else {
        XCTFail("no position read: \(message)", file: file, line: line)
        return
    }
    XCTAssertEqual(link.coordinate.latitude, expected.latitude, accuracy: 0.001, message, file: file, line: line)
    XCTAssertEqual(link.coordinate.longitude, expected.longitude, accuracy: 0.001, message, file: file, line: line)
}

final class MapLinkTests: XCTestCase {
    // MARK: - Google

    func testAGooglePlaceLinkIsReadFromItsPin() {
        // Google carries the pin twice. The !3d/!4d pair is the place; the @ is
        // wherever the map happened to be centred, and here they differ.
        let link = MapLinkReader.parse(
            "https://www.google.com/maps/place/Bostanci+Sahili/@40.9700,29.0500,17z/data=!4m6!3m5!8m2!3d40.9782!4d29.0640"
        )

        near(link, there, "the pin, not the map centre")
        XCTAssertEqual(link?.name, "Bostanci Sahili")
    }

    func testAGoogleLinkWithOnlyACentreStillWorks() {
        near(
            MapLinkReader.parse("https://www.google.com/maps/@40.9782,29.0640,17z"),
            there,
            "the centre is all there is"
        )
    }

    func testAGoogleSearchLinkIsRead() {
        near(
            MapLinkReader.parse("https://www.google.com/maps/search/?api=1&query=40.9782,29.0640"),
            there,
            "a query that is a position"
        )
    }

    // MARK: - Yandex

    func testYandexPutsLongitudeFirst() {
        // The one that has to be right: read in the other order this lands off
        // the coast of Somalia, and looks like a routing bug rather than a
        // parsing one.
        near(
            MapLinkReader.parse("https://yandex.com.tr/maps/?ll=29.0640%2C40.9782&z=17"),
            there,
            "longitude then latitude"
        )
    }

    func testAYandexPinIsRead() {
        near(
            MapLinkReader.parse("https://yandex.com.tr/maps/11508/kadikoy/?pt=29.0640,40.9782&z=16"),
            there,
            "a dropped pin"
        )
    }

    // MARK: - Apple and geo

    func testAnAppleMapsLinkIsRead() {
        let link = MapLinkReader.parse("https://maps.apple.com/?ll=40.9782,29.0640&q=Bostanci")

        near(link, there, "latitude then longitude")
        XCTAssertEqual(link?.name, "Bostanci")
    }

    func testAGeoLinkIsRead() {
        near(MapLinkReader.parse("geo:40.9782,29.0640"), there, "a bare geo link")
    }

    func testAGeoLinkWithTheUsualZeroesFallsBackToItsQuery() {
        // geo:0,0?q=... is the common shape and the zeroes are a placeholder.
        // Taking them at face value would route a rider into the Atlantic.
        let link = MapLinkReader.parse("geo:0,0?q=40.9782,29.0640(Bostanci%20Sahili)")

        near(link, there, "the query, not the zeroes")
        XCTAssertEqual(link?.name, "Bostanci Sahili")
    }

    // MARK: - What people actually paste

    func testALinkInsideASentenceIsFound() {
        near(
            MapLinkReader.parse("burada buluşalım https://maps.apple.com/?ll=40.9782,29.0640 saat 8de"),
            there,
            "shared text is rarely just a URL"
        )
    }

    func testTheNameOnTheLineAboveDoesNotConfuseIt() {
        near(
            MapLinkReader.parse("Bostancı Sahili\nhttps://www.google.com/maps/@40.9782,29.0640,17z"),
            there,
            "the way Google shares"
        )
    }

    func testTwoNumbersOnTheirOwnAreAPosition() {
        near(MapLinkReader.parse("40.9782, 29.0640"), there, "people paste coordinates too")
    }

    func testNegativeCoordinatesSurvive() {
        near(
            MapLinkReader.parse("geo:-33.8688,-151.2093"),
            Coordinate(latitude: -33.8688, longitude: -151.2093),
            "signs are not lost"
        )
    }

    // MARK: - What should not be read

    /// What a Google share actually expands to, taken off the wire from a real
    /// one. There is no position in it anywhere: an address, and two
    /// identifiers that mean something only inside Google. Anyone building this
    /// expecting coordinates builds the wrong thing.
    func testAGoogleShareExpandsToAnAddressAndNotAPosition() {
        let expanded = "https://www.google.com/maps?q=Vodafone+genel+m%C3%BCd%C3%BCrl%C3%BCk,"
            + "+19+May%C4%B1s,+B%C3%BCy%C3%BCkdere+Cd.+253-1,+34398+%C5%9Ei%C5%9Fli/%C4%B0stanbul"
            + "&ftid=0x14cab5959829708f:0x81025573ac77abc8&entry=gps&shh=CAE"

        XCTAssertNil(MapLinkReader.parse(expanded))
        XCTAssertEqual(
            MapLinkReader.placeQuery(in: expanded),
            "Vodafone genel müdürlük, 19 Mayıs, Büyükdere Cd. 253-1, 34398 Şişli/İstanbul"
        )
    }

    func testAnAddressIsOnlyOfferedWhenThereIsNoPosition() {
        // A link that does say where does not need geocoding, and geocoding it
        // anyway would trade an exact position for an approximate one.
        XCTAssertNil(MapLinkReader.placeQuery(in: "https://maps.apple.com/?ll=40.9782,29.0640&q=Bostanci"))
    }

    func testAShortenedLinkIsRecognisedRatherThanGuessedAt() {
        // There is nothing in these to read. Saying so is what lets the app go
        // and follow it instead of silently failing.
        XCTAssertTrue(MapLinkReader.isShortened("https://maps.app.goo.gl/aBcDeF123"))
        XCTAssertNil(MapLinkReader.parse("https://maps.app.goo.gl/aBcDeF123"))

        XCTAssertFalse(MapLinkReader.isShortened("https://maps.apple.com/?ll=40.9782,29.0640"))
    }

    func testNonsenseIsNotAPosition() {
        XCTAssertNil(MapLinkReader.parse(""))
        XCTAssertNil(MapLinkReader.parse("hello"))
        XCTAssertNil(MapLinkReader.parse("https://example.com/about"))
        XCTAssertNil(MapLinkReader.parse("geo:0,0"))
    }

    func testPositionsOffTheEarthAreRefused() {
        XCTAssertNil(MapLinkReader.parse("geo:91.0,29.0"))
        XCTAssertNil(MapLinkReader.parse("geo:40.9,181.0"))
    }
}
