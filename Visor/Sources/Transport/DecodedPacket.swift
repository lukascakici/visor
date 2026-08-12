import Core
import Foundation

/// A packet read back off the wire, in exactly the units the wire carries.
///
/// Deliberately not an `HUDPacket`: the wire holds whole meters, tens of
/// meters, whole seconds and whole km/h, and pretending the original values
/// survived would hide the quantization from anyone reading a decoded packet.
/// This is what the device firmware sees, and what the macOS peripheral
/// simulator prints.
public struct DecodedPacket: Hashable, Sendable {
    public let version: UInt8
    public let maneuver: ManeuverType
    /// Meters to the maneuver.
    public let distanceToManeuver: Int
    /// Meters to the destination, already scaled up from tens of meters.
    public let distanceRemaining: Int
    /// Seconds to the destination.
    public let timeRemaining: Int
    /// Speed in km/h.
    public let speed: Int
    public let flags: HUDPacket.Flags
    /// The street name, empty when the packet carried none.
    public let streetName: String
}

extension DecodedPacket {
    /// Reads a packet, or returns `nil` if there is not a whole header there.
    ///
    /// A version that is not the one this build knows is not rejected: the
    /// caller is told what it is and decides. Refusing to parse would leave the
    /// device with nothing at all to show, which is worse than a field being
    /// interpreted generously.
    public init?(_ data: Data) {
        guard data.count >= HUDPacket.headerSize else { return nil }

        let bytes = [UInt8](data)
        func value(at index: Int) -> UInt16 {
            UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
        }

        self.version = bytes[0]
        self.maneuver = ManeuverType(rawValue: bytes[1]) ?? .unknown
        self.distanceToManeuver = Int(value(at: 2))
        self.distanceRemaining = Int(value(at: 4)) * 10
        self.timeRemaining = Int(value(at: 6))
        self.speed = Int(bytes[8])
        self.flags = HUDPacket.Flags(rawValue: bytes[9])
        // Whatever follows the header is the name, to the end of the write.
        // Decoded leniently: a device that mangles a byte should show a
        // replacement character, not lose the whole packet.
        self.streetName = String(decoding: bytes[HUDPacket.headerSize...], as: UTF8.self)
    }
}
