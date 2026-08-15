import Core
import Foundation
import MapKit

/// Somewhere the map service is offering while the rider is still typing.
///
/// Deliberately carries no coordinate. A completion is a name the service
/// recognises, not a position; it costs a lookup to turn one into a place, and
/// doing that for every row of a list that changes on every keystroke would be
/// several hundred lookups to answer a question nobody asked.
public struct Suggestion: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    /// The district or street that tells two places of the same name apart.
    public let subtitle: String?
}

public enum SuggestionProblem: LocalizedError {
    /// Tapped just as the list moved under the finger.
    case noLongerOffered
    case nothingThere

    public var errorDescription: String? {
        switch self {
        case .noLongerOffered: "That suggestion is gone, try typing it again"
        case .nothingThere: "Could not find that place"
        }
    }
}

/// Search as the rider types.
///
/// The reason this exists alongside `PlaceSearch`: a search returns places, and
/// a place is expensive, so a search cannot be run on every keystroke. This
/// returns names, which are cheap, and it is what makes a search field feel like
/// it is keeping up. Only the one the rider actually taps is turned into a
/// place.
/// `@preconcurrency` on the conformance because MapKit's delegate predates
/// Swift's actors and so is not marked as running anywhere in particular. It
/// does call back on the main queue; this says so, and checks it at runtime
/// rather than taking it on faith.
@MainActor
@Observable
public final class PlaceCompleter: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    public private(set) var suggestions: [Suggestion] = []

    private let completer = MKLocalSearchCompleter()
    /// Held apart from `suggestions` so what the view shows stays a plain value
    /// that carries nothing of MapKit's with it.
    private var offered: [Int: MKLocalSearchCompletion] = [:]
    private var nextID = 0

    public override init() {
        super.init()
        // Addresses and places, but not queries. A query completion is another
        // search rather than somewhere to go, and every row here should be
        // somewhere the rider can be taken.
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    /// Asks for suggestions near `origin`, so a half-typed street name finds the
    /// one down the road rather than one on another continent.
    ///
    /// Safe to call on every keystroke: the completer does its own throttling,
    /// which is the whole reason for using it instead of a debounce of our own.
    public func suggest(_ text: String, near origin: Coordinate, within meters: Double = 50_000) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else {
            clear()
            return
        }

        completer.region = MKCoordinateRegion(
            center: origin.asCLCoordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
        completer.queryFragment = trimmed
    }

    public func clear() {
        completer.queryFragment = ""
        suggestions = []
        offered = [:]
    }

    /// Turns the one the rider tapped into somewhere with a position.
    public func resolve(_ suggestion: Suggestion) async throws -> Place {
        guard let completion = offered[suggestion.id] else {
            throw SuggestionProblem.noLongerOffered
        }

        let response = try await MKLocalSearch(request: .init(completion: completion)).start()
        guard let place = response.mapItems.compactMap(Place.init).first else {
            throw SuggestionProblem.nothingThere
        }
        return place
    }

    // MARK: - MKLocalSearchCompleterDelegate

    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var offered: [Int: MKLocalSearchCompletion] = [:]
        var suggestions: [Suggestion] = []

        for completion in completer.results {
            // A fresh identity every round rather than a row number. Tapping
            // just as the list moves under the finger then fails to resolve,
            // which is recoverable; resolving whatever now sits at that row is
            // the wrong destination, silently.
            nextID += 1
            offered[nextID] = completion
            suggestions.append(Suggestion(
                id: nextID,
                title: completion.title,
                subtitle: completion.subtitle.isEmpty ? nil : completion.subtitle
            ))
        }

        self.offered = offered
        self.suggestions = suggestions
    }

    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Not shown to the rider. This fails routinely and harmlessly halfway
        // through a word, and an error appearing and vanishing under the
        // cursor reads as the app being broken rather than as the word being
        // half-typed.
        suggestions = []
        offered = [:]
    }
}
