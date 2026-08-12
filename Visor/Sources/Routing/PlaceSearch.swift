import Core
import Foundation
import MapKit

/// Somewhere a rider might be heading.
public struct Place: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    /// Street, district, city: whatever the map service knows, for telling two
    /// places of the same name apart.
    public let address: String?
    public let coordinate: Coordinate

    public init(name: String, address: String?, coordinate: Coordinate) {
        self.name = name
        self.address = address
        self.coordinate = coordinate
    }
}

/// Looks up destinations by name.
public struct PlaceSearch: Sendable {
    public init() {}

    /// Searches around `origin`, so "pharmacy" means one nearby rather than one
    /// on another continent.
    public func find(_ query: String, near origin: Coordinate, within meters: Double = 50_000) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(
            center: origin.asCLCoordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap(Place.init)
    }
}

extension Place {
    init?(_ item: MKMapItem) {
        guard let coordinate = item.placemark.location?.coordinate else { return nil }
        self.init(
            name: item.name ?? item.placemark.title ?? "Unnamed",
            address: Place.describe(item.placemark),
            coordinate: Coordinate(coordinate)
        )
    }

    /// The parts of an address worth showing on one line.
    private static func describe(_ placemark: MKPlacemark) -> String? {
        let parts = [placemark.thoroughfare, placemark.locality, placemark.administrativeArea]
        let joined = parts.compactMap { $0 }.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }
}
