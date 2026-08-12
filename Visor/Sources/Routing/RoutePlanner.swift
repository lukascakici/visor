import Core
import Foundation
import MapKit

/// Asks MapKit for a route.
///
/// Thin on purpose: everything interesting happens either side of it, in the
/// conversion below and in the guidance engine above.
public struct RoutePlanner: Sendable {
    public enum Failure: Error, Equatable {
        /// MapKit had no route between those two points.
        case noRouteFound
        /// The service is refusing requests for now. The caller is expected to
        /// wait rather than try again immediately.
        case throttled
        case failed(String)
    }

    public var transportType: MKDirectionsTransportType

    /// Motorcycles are not one of MapKit's options, so driving directions it
    /// is. They keep to roads a motorcycle can use, which walking or cycling
    /// directions would not.
    public init(transportType: MKDirectionsTransportType = .automobile) {
        self.transportType = transportType
    }

    public func route(from origin: Coordinate, to destination: Coordinate) async throws -> Route {
        try await route(
            from: MKMapItem(placemark: MKPlacemark(coordinate: origin.asCLCoordinate)),
            to: MKMapItem(placemark: MKPlacemark(coordinate: destination.asCLCoordinate))
        )
    }

    public func route(from origin: MKMapItem, to destination: MKMapItem) async throws -> Route {
        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = transportType
        // One route is all the HUD can show. Asking for alternates would only
        // cost time on a reroute, which is the moment that can least afford it.
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let best = response.routes.first else { throw Failure.noRouteFound }
            return Route(best)
        } catch let error as Failure {
            throw error
        } catch let error as MKError where error.code == .loadingThrottled {
            throw Failure.throttled
        } catch let error as MKError where error.code == .placemarkNotFound || error.code == .directionsNotFound {
            throw Failure.noRouteFound
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
    }
}
