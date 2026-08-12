/// What the rider is asked to do at a junction.
///
/// The raw values go on the wire as byte 1 of the HUD packet, so they are part
/// of the device contract: append new cases, never renumber existing ones.
public enum ManeuverType: UInt8, Hashable, Sendable, CaseIterable {
    /// The geometry was too degenerate to classify. The HUD is expected to show
    /// a neutral arrow: a missing instruction is safer than a wrong one.
    case unknown = 0
    case depart = 1
    case straight = 2
    case slightRight = 3
    case right = 4
    case sharpRight = 5
    case slightLeft = 6
    case left = 7
    case sharpLeft = 8
    case uTurn = 9
    case arrive = 10
}
