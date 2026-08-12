import Core

extension Geo {
    /// Total length of a polyline, in meters.
    public static func length(of polyline: [Coordinate]) -> Double {
        guard polyline.count > 1 else { return 0 }
        return (0..<(polyline.count - 1)).reduce(0) { total, index in
            total + distance(from: polyline[index], to: polyline[index + 1])
        }
    }

    /// The coordinate found `meters` along the polyline.
    ///
    /// Clamped at both ends: a negative distance returns the first vertex, one
    /// past the end returns the last. Returns `nil` only for an empty polyline.
    public static func coordinate(on polyline: [Coordinate], at meters: Double) -> Coordinate? {
        guard let first = polyline.first, let last = polyline.last else { return nil }
        guard meters > 0 else { return first }

        var remaining = meters
        for index in 0..<max(0, polyline.count - 1) {
            let start = polyline[index]
            let end = polyline[index + 1]
            let segment = distance(from: start, to: end)

            if remaining <= segment {
                guard segment > 0 else { return start }
                let fraction = remaining / segment
                return Coordinate(
                    latitude: start.latitude + fraction * (end.latitude - start.latitude),
                    longitude: start.longitude + fraction * (end.longitude - start.longitude)
                )
            }
            remaining -= segment
        }
        return last
    }
}
