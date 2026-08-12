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

    /// The stretch of a polyline between two distances measured along it.
    ///
    /// Both ends are clamped to the line, and the cut points become real
    /// vertices, so the slice is a polyline in its own right: its length is
    /// `to - from` and projecting onto it gives distances relative to `from`.
    public static func slice(_ polyline: [Coordinate], from: Double, to: Double) -> [Coordinate] {
        guard polyline.count > 1 else { return polyline }

        let total = length(of: polyline)
        let start = min(max(0, from), total)
        let end = min(max(start, to), total)

        guard
            let first = coordinate(on: polyline, at: start),
            let last = coordinate(on: polyline, at: end)
        else { return [] }

        // A vertex sitting on a cut is already in the slice, as the
        // interpolated end. The tolerance is what keeps it from being added a
        // second time: cumulative distances are sums of square roots, so a
        // vertex exactly 100 m along measures as 100 m give or take a
        // nanometer, and a strict comparison would go either way.
        let tolerance = 1e-6

        var sliced = [first]
        var travelled = 0.0
        for index in 0..<(polyline.count - 1) {
            travelled += distance(from: polyline[index], to: polyline[index + 1])
            if travelled > start + tolerance, travelled < end - tolerance {
                sliced.append(polyline[index + 1])
            }
        }
        sliced.append(last)

        return sliced
    }
}
