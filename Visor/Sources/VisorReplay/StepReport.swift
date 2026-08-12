import Core
import Foundation
import Geometry
import Guidance

/// Lays a route's steps out side by side with the evidence behind each
/// maneuver.
///
/// For arguing with a map service. A classification is an opinion derived from
/// two bearings; when the opinion is disputed, this prints the bearings, the
/// angle between them, and what the service said about the same junction, so
/// the argument can be settled by looking rather than by guessing.
enum StepReport {
    static func print(_ route: Route, window: Double = ManeuverThresholds.default.bearingWindow) {
        // One row per junction, with our reading and the service's side by
        // side. They describe the same corner: the turn into step N, and the
        // sentence the service attached to step N-1, which is where a map
        // service puts the words for the maneuver that ends a step. Anything
        // that stops lining up here has come apart.
        Swift.print("""

          step  length   entry   exit   turn      ours          the same junction, in the service's words
          ────  ───────  ──────  ─────  ────────  ────────────  ────────────────────────────────────────
        """)

        for (index, step) in route.steps.enumerated() {
            let entry = ManeuverClassifier.entryBearing(of: step.polyline, window: window)
            let exit = ManeuverClassifier.exitBearing(of: step.polyline, window: window)

            let turn = index > 0
                ? ManeuverClassifier.turn(
                    leaving: route.steps[index - 1].polyline,
                    entering: step.polyline
                )
                : nil

            let columns = [
                pad("\(index)", 4),
                pad(String(format: "%.0f m", Geo.length(of: step.polyline)), 7),
                pad(degrees(entry), 6),
                pad(degrees(exit), 5),
                pad(turn.map { String(format: "%+.0f°", $0) } ?? "—", 8),
                pad(String(describing: step.maneuver), 12),
                index > 0 ? (route.steps[index - 1].streetName ?? "—") : "—",
            ]
            Swift.print("  " + columns.joined(separator: "  "))
        }
        Swift.print("")
    }

    private static func degrees(_ value: Double?) -> String {
        value.map { String(format: "%.0f°", $0) } ?? "—"
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
