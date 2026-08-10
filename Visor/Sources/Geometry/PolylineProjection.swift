import Core
import Foundation

/// Where a point falls relative to a polyline: the closest point on the line,
/// how far off it is, and how far along the line that lands.
///
/// One projection answers three questions at once: off-route detection reads
/// `distance`, progress along the route reads `distanceAlongPolyline`, and the
/// remaining maneuvers are found from `segmentIndex`.
public struct PolylineProjection: Hashable, Sendable {
    /// The closest point on the polyline.
    public let point: Coordinate
    /// Perpendicular distance from the queried point to the polyline, in meters.
    public let distance: Double
    /// Index of the segment that owns the closest point; the segment runs from
    /// vertex `segmentIndex` to `segmentIndex + 1`.
    public let segmentIndex: Int
    /// Position within that segment, `0` at its start vertex, `1` at its end.
    public let fraction: Double
    /// Distance from the start of the polyline to the closest point, in meters.
    public let distanceAlongPolyline: Double
}

extension Geo {
    /// Projects `point` onto `polyline`, returning the closest point on it.
    ///
    /// Returns `nil` only for an empty polyline. A single-vertex polyline
    /// projects onto that vertex.
    ///
    /// The math runs in a local east/north frame in meters, centred on the
    /// queried point. Over the scale of a route segment the flat-earth error is
    /// millimetric, and in exchange every segment becomes plain 2D vector work.
    public static func project(_ point: Coordinate, onto polyline: [Coordinate]) -> PolylineProjection? {
        guard let first = polyline.first else { return nil }

        guard polyline.count > 1 else {
            return PolylineProjection(
                point: first,
                distance: distance(from: point, to: first),
                segmentIndex: 0,
                fraction: 0,
                distanceAlongPolyline: 0
            )
        }

        // The queried point sits at the origin of the local frame, so the
        // distance to a projected point is just its magnitude.
        let scale = cos(point.latitude.inRadians)
        func local(_ coordinate: Coordinate) -> (x: Double, y: Double) {
            (
                x: earthRadius * (coordinate.longitude - point.longitude).inRadians * scale,
                y: earthRadius * (coordinate.latitude - point.latitude).inRadians
            )
        }

        var best: PolylineProjection?
        var travelled = 0.0

        for index in 0..<(polyline.count - 1) {
            let start = polyline[index]
            let end = polyline[index + 1]
            let segmentLength = distance(from: start, to: end)

            let a = local(start)
            let b = local(end)
            let run = (x: b.x - a.x, y: b.y - a.y)
            let lengthSquared = run.x * run.x + run.y * run.y

            // A zero-length segment (duplicated vertices happen in real route
            // geometry) has no direction to project onto, so it collapses to
            // its start vertex.
            let fraction = lengthSquared > 0
                ? min(1, max(0, -(a.x * run.x + a.y * run.y) / lengthSquared))
                : 0

            let closest = (x: a.x + fraction * run.x, y: a.y + fraction * run.y)
            let offset = (closest.x * closest.x + closest.y * closest.y).squareRoot()

            if best == nil || offset < best!.distance {
                best = PolylineProjection(
                    point: Coordinate(
                        latitude: start.latitude + fraction * (end.latitude - start.latitude),
                        longitude: start.longitude + fraction * (end.longitude - start.longitude)
                    ),
                    distance: offset,
                    segmentIndex: index,
                    fraction: fraction,
                    distanceAlongPolyline: travelled + fraction * segmentLength
                )
            }

            travelled += segmentLength
        }

        return best
    }
}
