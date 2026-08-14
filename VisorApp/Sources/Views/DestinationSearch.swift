import Core
import Routing
import SwiftUI

/// Picking somewhere to go.
///
/// Searches near the rider rather than globally, so a half-typed street name
/// finds the one down the road instead of one in another country.
///
/// It also takes a link. Searching here will always be worse than searching in
/// Google or Yandex, and there is no reason to compete with them: find the
/// place wherever you already find places, share the link in, and this app does
/// the part those apps cannot, which is talk to the display.
struct DestinationSearch: View {
    let origin: Coordinate
    let onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var problem: String?
    @State private var search: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if let problem {
                    Text(problem).foregroundStyle(.secondary)
                }

                if results.isEmpty, !isSearching {
                    shareHint
                }

                ForEach(results) { place in
                    Button {
                        onPick(place)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .font(.body)
                            if let address = place.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
                if isSearching { ProgressView() }
            }
        }
        .searchable(text: $query, prompt: "Street, place or postcode")
        .onChange(of: query) { _, text in
            // One search in flight at a time, started once typing pauses. Every
            // keystroke firing a request would get the app throttled by the map
            // service in about a second.
            search?.cancel()
            search = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await run(text)
            }
        }
    }

    /// The way in from other map apps, said plainly, because nobody discovers
    /// it by guessing.
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

    private func run(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 1 else {
            results = []
            return
        }

        // A link is not a search term. Handing one to the map service can only
        // come back empty, and the rider would be left thinking the place does
        // not exist.
        if MapLinkReader.looksLikeALink(trimmed) {
            await follow(trimmed)
            return
        }

        isSearching = true
        problem = nil
        defer { isSearching = false }

        do {
            results = try await PlaceSearch().find(text, near: origin)
            if results.isEmpty { problem = "Nothing found near you" }
        } catch {
            guard !Task.isCancelled else { return }
            problem = error.localizedDescription
            results = []
        }
    }

    /// Opens a shared link, following it first if it is one of the shortened
    /// ones Google hands out.
    private func follow(_ text: String) async {
        isSearching = true
        problem = nil
        defer { isSearching = false }

        do {
            guard let link = try await MapLinkReader.resolve(text) else {
                problem = "That link does not carry a position"
                results = []
                return
            }

            results = [Place(
                name: link.name ?? "Shared destination",
                address: String(format: "%.5f, %.5f", link.coordinate.latitude, link.coordinate.longitude),
                coordinate: link.coordinate
            )]
        } catch {
            guard !Task.isCancelled else { return }
            // Said plainly rather than as a URLError: the rider is holding a
            // link that did not work, and the reason it did not is not theirs
            // to debug.
            problem = "Could not open that link"
            results = []
        }
    }
}
