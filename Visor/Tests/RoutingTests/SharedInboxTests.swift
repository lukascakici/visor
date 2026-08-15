import XCTest
@testable import Routing

/// A container of its own per test, so one test's leftovers are never another
/// test's arriving destination.
private func scratch(_ name: String = #function) -> UserDefaults {
    let suite = "SharedInboxTests.\(name)"
    UserDefaults().removePersistentDomain(forName: suite)
    return UserDefaults(suiteName: suite)!
}

final class SharedInboxTests: XCTestCase {
    func testNothingWaitsUntilSomethingIsShared() {
        let inbox = SharedInbox(store: scratch())

        XCTAssertNil(inbox.take(), "an app that was just opened has no destination waiting")
    }

    func testAHandoverCrossesFromOneInboxToTheOther() {
        // Two instances over one container, because that is the real shape of
        // it: the extension writes and a different process reads.
        let container = scratch()
        SharedInbox(store: container).hand(over: "https://maps.app.goo.gl/abc")

        XCTAssertEqual(SharedInbox(store: container).take(), "https://maps.app.goo.gl/abc")
    }

    func testTakingItLeavesNothingBehind() {
        let container = scratch()
        SharedInbox(store: container).hand(over: "https://maps.app.goo.gl/abc")

        let inbox = SharedInbox(store: container)
        _ = inbox.take()

        // Otherwise a destination the rider already dealt with is offered again
        // every time they come back to the app.
        XCTAssertNil(inbox.take(), "the same share is not offered twice")
    }

    func testTheSecondShareIsTheOneThatCounts() {
        let container = scratch()
        let inbox = SharedInbox(store: container)

        inbox.hand(over: "https://maps.app.goo.gl/first")
        inbox.hand(over: "https://maps.app.goo.gl/second")

        XCTAssertEqual(inbox.take(), "https://maps.app.goo.gl/second", "sharing twice is changing your mind")
    }

    func testAnEmptyShareIsNotADestination() {
        let container = scratch()
        let inbox = SharedInbox(store: container)

        inbox.hand(over: "   \n ")

        XCTAssertNil(inbox.take(), "whitespace would open the search sheet on nothing")
    }

    func testAnEmptyShareDoesNotWipeARealOne() {
        let container = scratch()
        let inbox = SharedInbox(store: container)

        inbox.hand(over: "https://maps.app.goo.gl/abc")
        inbox.hand(over: "")

        XCTAssertEqual(inbox.take(), "https://maps.app.goo.gl/abc", "an item worth nothing does not displace one worth something")
    }

    func testSharedTextArrivesWithoutItsSurroundingSpace() {
        let container = scratch()
        let inbox = SharedInbox(store: container)

        // Google's share sheet hands over the link with a trailing newline, and
        // a URL with a newline on it is not a URL.
        inbox.hand(over: "  https://maps.app.goo.gl/abc\n")

        XCTAssertEqual(inbox.take(), "https://maps.app.goo.gl/abc")
    }

    func testAMissingContainerIsQuietRatherThanFatal() {
        // What a misconfigured app group looks like from here. It has to fail by
        // doing nothing: the alternative is an app that crashes on launch
        // because of an entitlement.
        let inbox = SharedInbox(store: nil)

        inbox.hand(over: "https://maps.app.goo.gl/abc")

        XCTAssertNil(inbox.take())
    }
}
