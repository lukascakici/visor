import Core
import Routing
import SwiftUI

/// Picking somewhere to go.
///
/// Suggestions arrive while the rider types, near them rather than globally, so
/// a half-typed street name finds the one down the road instead of one in
/// another country. Nothing is looked up properly until a row is tapped.
///
/// It also takes a link. Searching here will never be as good as searching in
/// Google or Yandex, and there is no reason to compete with them: find the place
/// wherever you already find places, share the link in, and this app does the
/// part those apps cannot, which is talk to the display.
struct DestinationSearch: View {
    let origin: Coordinate
    let onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var completer = PlaceCompleter()
    @State private var query = ""
    /// Only ever filled by a pasted link. Typing produces suggestions, which
    /// are not places until one is chosen.
    @State private var found: [Place] = []
    @State private var isBusy = false
    @State private var problem: String?
    @State private var work: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if let problem {
                    Text(problem).foregroundStyle(.secondary)
                }

                if isEmptyHanded {
                    shareHint
                }

                ForEach(found) { place in
                    row(place.name, place.address) {
                        onPick(place)
                        dismiss()
                    }
                }

                ForEach(completer.suggestions) { suggestion in
                    row(suggestion.title, suggestion.subtitle) {
                        choose(suggestion)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isBusy { ProgressView() }
            }
        }
        .searchable(text: $query, prompt: "Street, place or postcode")
        .onChange(of: query) { _, text in
            react(to: text)
        }
    }

    private var isEmptyHanded: Bool {
        found.isEmpty && completer.suggestions.isEmpty && !isBusy
    }

    private func row(_ title: String, _ detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The way in from other map apps, said plainly, because nobody discovers it
    /// by guessing.
    private var shareHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Or bring one in")
                .font(.footnote.weight(.semibold))

            Text("Find the place in Google Maps, Yandex or Apple Maps, tap Share, copy the link, and paste it here.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            PasteButton(payloadType: String.self) { items in
                guard let text = items.first else { return }
                query = text
            }
            .buttonBorderShape(.capsule)
        }
        .padding(.vertical, 6)
    }

    private func react(to text: String) {
        work?.cancel()
        found = []
        problem = nil

        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // A link is not a search term. Handing one to the completer can only
        // come back empty, and the rider would be left thinking the place does
        // not exist.
        guard !MapLinkReader.looksLikeALink(trimmed) else {
            completer.clear()
            work = Task {
                // The only pause left in here. Following a link is a network
                // call and a pasted link arrives one character at a time as far
                // as this is concerned.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await follow(trimmed)
            }
            return
        }

        // No debounce: the completer throttles itself, which is most of why it
        // is here rather than a search on a timer.
        completer.suggest(trimmed, near: origin)
    }

    /// Looks up the one that was tapped, which is the first time this screen
    /// asks the map service for a position.
    private func choose(_ suggestion: Suggestion) {
        work?.cancel()
        work = Task {
            isBusy = true
            problem = nil
            defer { isBusy = false }

            do {
                onPick(try await completer.resolve(suggestion))
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                problem = error.localizedDescription
            }
        }
    }

    /// Opens a shared link, following it first if it is one of the shortened
    /// ones Google hands out.
    private func follow(_ text: String) async {
        isBusy = true
        problem = nil
        defer { isBusy = false }

        do {
            switch try await MapLinkReader.resolve(text) {
            case .position(let link):
                found = [Place(
                    name: link.name ?? "Shared destination",
                    address: String(format: "%.5f, %.5f", link.coordinate.latitude, link.coordinate.longitude),
                    coordinate: link.coordinate
                )]

            case .address(let address):
                // Half of these links carry no position, only the address they
                // were shared as. Which is the better half of the bargain: the
                // rider searched somewhere that knows the place, and a full
                // postal address is a far surer thing to geocode than anything
                // they would have typed here.
                found = try await PlaceSearch().find(address, near: origin)
                if found.isEmpty {
                    problem = "Could not find \"\(address)\""
                }

            case .none:
                problem = "That link does not carry a place"
                found = []
            }
        } catch {
            guard !Task.isCancelled else { return }
            // Said plainly rather than as a URLError: the rider is holding a
            // link that did not work, and the reason it did not is not theirs
            // to debug.
            problem = "Could not open that link"
            found = []
        }
    }
}
