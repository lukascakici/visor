import Core
import Routing
import SwiftUI

/// Picking somewhere to go.
///
/// Searches near the rider rather than globally, so a half-typed street name
/// finds the one down the road instead of one in another country.
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

    private func run(_ text: String) async {
        guard text.trimmingCharacters(in: .whitespaces).count > 1 else {
            results = []
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
}
