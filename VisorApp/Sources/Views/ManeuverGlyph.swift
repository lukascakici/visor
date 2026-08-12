import Core
import SwiftUI

/// The arrow for a maneuver, and the words for it.
///
/// Both are chosen from the maneuver type, never from an instruction string, so
/// the display says the same thing the HUD does.
enum ManeuverGlyph {
    static func symbol(_ maneuver: ManeuverType) -> String {
        switch maneuver {
        case .unknown: "questionmark"
        case .depart: "location.north.line.fill"
        case .straight: "arrow.up"
        case .slightRight: "arrow.up.right"
        case .right: "arrow.turn.up.right"
        case .sharpRight: "arrow.turn.right.down"
        case .slightLeft: "arrow.up.left"
        case .left: "arrow.turn.up.left"
        case .sharpLeft: "arrow.turn.left.down"
        case .uTurn: "arrow.uturn.down"
        case .arrive: "flag.checkered"
        }
    }

    static func name(_ maneuver: ManeuverType) -> String {
        switch maneuver {
        case .unknown: "Continue"
        case .depart: "Head off"
        case .straight: "Straight on"
        case .slightRight: "Slight right"
        case .right: "Turn right"
        case .sharpRight: "Sharp right"
        case .slightLeft: "Slight left"
        case .left: "Turn left"
        case .sharpLeft: "Sharp left"
        case .uTurn: "Make a U-turn"
        case .arrive: "Arrive"
        }
    }
}

/// Distances the way a rider reads them: coarse when far off, precise when the
/// junction is close enough to act on.
enum Format {
    static func distance(_ meters: Double) -> String {
        switch meters {
        case ..<10: "now"
        case ..<400: "\(Int((meters / 10).rounded()) * 10) m"
        case ..<1000: "\(Int((meters / 50).rounded()) * 50) m"
        default: String(format: "%.1f km", meters / 1000)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total < 3600
            ? String(format: "%d:%02d", total / 60, total % 60)
            : String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func speed(_ metersPerSecond: Double) -> String {
        "\(Int((metersPerSecond * 3.6).rounded()))"
    }
}
