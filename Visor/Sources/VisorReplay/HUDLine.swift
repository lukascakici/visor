import Core
import Foundation
import Guidance

/// Renders guidance state the way the HUD would show it, one line per second.
///
/// This is the whole point of the tool: the numbers below are exactly what byte
/// 1 through byte 9 of the packet will carry, in a form that can be read while
/// they go past.
enum HUDLine {
    static let header = """
      time  turn                     street                          left      eta   speed  flags
      ────  ───────────────────────  ──────────────────────────────  ──────  ─────  ──────  ─────────────
    """

    static func render(_ state: GuidanceState, atSecond second: Int) -> String {
        let stamp = String(format: "%3ds", second)

        guard let progress = state.progress else {
            return "  \(stamp)  \(pad("no position yet", 23))  \(pad("", 30))  \(pad("", 6))  \(pad("", 5))  \(pad("", 6))  \(flags(state))"
        }

        let turn = "\(arrow(progress.maneuver)) \(pad(label(progress.maneuver), 12)) \(pad(meters(progress.distanceToManeuver), 8))"
        let street = pad(progress.streetName ?? "—", 30)
        let left = pad(meters(progress.distanceRemaining), 6)
        let eta = pad(clock(progress.timeRemaining), 5)
        let speed = pad(String(format: "%.0f km/h", state.speed * 3.6), 6)

        return "  \(stamp)  \(pad(turn, 23))  \(street)  \(left)  \(eta)  \(speed)  \(flags(state))"
    }

    /// The three flag bits the packet carries, spelled out.
    private static func flags(_ state: GuidanceState) -> String {
        var raised: [String] = []
        if state.isOffRoute { raised.append("OFF-ROUTE") }
        if state.isRerouting { raised.append("REROUTING") }
        if state.hasWeakSignal { raised.append("WEAK-GPS") }
        return raised.joined(separator: " ")
    }

    private static func arrow(_ maneuver: ManeuverType) -> String {
        switch maneuver {
        case .unknown: "?"
        case .depart: "•"
        case .straight: "↑"
        case .slightRight: "↗"
        case .right: "→"
        case .sharpRight: "↘"
        case .slightLeft: "↖"
        case .left: "←"
        case .sharpLeft: "↙"
        case .uTurn: "↺"
        case .arrive: "⚑"
        }
    }

    private static func label(_ maneuver: ManeuverType) -> String {
        switch maneuver {
        case .unknown: "unknown"
        case .depart: "depart"
        case .straight: "straight"
        case .slightRight: "slight right"
        case .right: "right"
        case .sharpRight: "sharp right"
        case .slightLeft: "slight left"
        case .left: "left"
        case .sharpLeft: "sharp left"
        case .uTurn: "u-turn"
        case .arrive: "arrive"
        }
    }

    private static func meters(_ value: Double) -> String {
        value >= 1000
            ? String(format: "%.1f km", value / 1000)
            : String(format: "%.0f m", value)
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    /// Pads to a column width counting characters, not bytes: Turkish street
    /// names would otherwise pull the columns apart.
    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
