import Core
import Foundation

extension Geo {
    /// Thins a polyline down to the vertices that carry its shape.
    ///
    /// Douglas-Peucker: keep both ends, find the vertex furthest from the line
    /// between them, and if it stands further off than `tolerance`, keep it too
    /// and repeat on each half. Whatever stays within `tolerance` of a kept line
    /// is dropped, because redrawing it would change nothing anyone could see.
    ///
    /// Route geometry arrives with a vertex every few meters, most of them
    /// describing a road that is simply straight. At the far end of a Bluetooth
    /// link those vertices cost bytes that buy no shape.
    ///
    /// The result is a subset of the input: kept vertices are the original
    /// coordinates and never interpolated ones, so simplifying adds no
    /// positional error of its own. It only leaves detail out.
    public static func simplify(_ polyline: [Coordinate], tolerance: Double) -> [Coordinate] {
        guard polyline.count > 2, tolerance > 0 else { return polyline }

        let points = planar(polyline)
        var kept = [Bool](repeating: false, count: polyline.count)
        kept[0] = true
        kept[polyline.count - 1] = true

        // An explicit stack rather than recursion: a route can carry thousands
        // of vertices, and how deep this divides is decided by the road, not by
        // anything we control.
        var pending = [(first: 0, last: polyline.count - 1)]
        while let (first, last) = pending.popLast() {
            guard last > first + 1 else { continue }

            var furthest = first
            var worst = 0.0
            for index in (first + 1)..<last {
                let offset = offset(of: points[index], from: points[first], to: points[last])
                if offset > worst {
                    worst = offset
                    furthest = index
                }
            }

            guard worst > tolerance else { continue }
            kept[furthest] = true
            pending.append((first, furthest))
            pending.append((furthest, last))
        }

        return zip(polyline, kept).compactMap { $1 ? $0 : nil }
    }

    /// Thins a polyline until at most `limit` vertices are left.
    ///
    /// The tolerance is searched for rather than given, because on a radio link
    /// the budget is the fixed thing: a write carries so many bytes and no more.
    /// The search settles on the smallest tolerance that still fits, so a link
    /// with room to spare spends it on detail rather than leaving it unused.
    public static func simplify(_ polyline: [Coordinate], toAtMost limit: Int) -> [Coordinate] {
        guard limit > 1 else { return Array(polyline.prefix(max(0, limit))) }
        guard polyline.count > limit else { return polyline }

        // Bracket the answer first. This terminates: a tolerance wider than the
        // polyline itself leaves nothing but the two ends, which fits any limit
        // of two or more.
        var tooFine = 0.0
        var coarseEnough = 1.0
        var best = simplify(polyline, tolerance: coarseEnough)
        while best.count > limit {
            tooFine = coarseEnough
            coarseEnough *= 4
            best = simplify(polyline, tolerance: coarseEnough)
        }

        // Then close the gap. Twelve halvings put the tolerance within a
        // thousandth of the bracket, which is finer than the geometry means
        // anything at.
        for _ in 0..<12 {
            let middle = (tooFine + coarseEnough) / 2
            let candidate = simplify(polyline, tolerance: middle)
            if candidate.count > limit {
                tooFine = middle
            } else {
                coarseEnough = middle
                best = candidate
            }
        }

        return best
    }

    /// The polyline in a local east/north frame in meters, centred on its first
    /// vertex.
    ///
    /// Flattening the earth this way distorts over long distances, but the
    /// frame is only ever used to decide *which* vertices matter. The ones that
    /// survive are handed back as the original coordinates, so the distortion
    /// never reaches the output.
    private static func planar(_ polyline: [Coordinate]) -> [(x: Double, y: Double)] {
        guard let origin = polyline.first else { return [] }
        let scale = cos(origin.latitude.inRadians)

        return polyline.map { coordinate in
            (
                x: earthRadius * (coordinate.longitude - origin.longitude).inRadians * scale,
                y: earthRadius * (coordinate.latitude - origin.latitude).inRadians
            )
        }
    }

    /// Distance from a point to a segment, in the planar frame.
    ///
    /// To the segment rather than to the infinite line through it: where a
    /// route doubles back, the two anchors can end up near each other, and the
    /// line through them then runs off in a direction the road never took.
    private static func offset(
        of point: (x: Double, y: Double),
        from start: (x: Double, y: Double),
        to end: (x: Double, y: Double)
    ) -> Double {
        let run = (x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = run.x * run.x + run.y * run.y

        let fraction = lengthSquared > 0
            ? min(1, max(0, ((point.x - start.x) * run.x + (point.y - start.y) * run.y) / lengthSquared))
            : 0

        let closest = (x: start.x + fraction * run.x, y: start.y + fraction * run.y)
        let away = (x: point.x - closest.x, y: point.y - closest.y)
        return (away.x * away.x + away.y * away.y).squareRoot()
    }
}
