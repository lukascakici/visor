import Core
import Foundation
import Guidance

/// The message the HUD is fed, once a second.
///
/// The layout, version 1, is fixed and little-endian:
///
///     byte  0      protocol version
///     byte  1      maneuver type
///     bytes 2...3  distance to the maneuver, uint16, meters
///     bytes 4...5  distance to the destination, uint16, tens of meters
///     bytes 6...7  time to the destination, uint16, seconds
///     byte  8      speed, uint8, km/h
///     byte  9      flags
///     byte 10...   street name, UTF-8, running to the end of the packet
///
/// Ten fixed bytes and a name, rather than JSON, because this goes out every
/// second over a link whose guaranteed payload is twenty bytes, to a device
/// with no parser worth the name.
///
/// Every numeric field saturates instead of wrapping. A distance of 80 km
/// arriving as 14 km would be a plausible-looking lie; arriving as 65.5 km is
/// obviously the top of the scale.
public struct HUDPacket: Hashable, Sendable {
    /// The version in byte 0. Bump it when the layout changes, never when a
    /// value's meaning stays put.
    public static let version: UInt8 = 1

    /// The fixed part, before the street name.
    public static let headerSize = 10

    /// What a BLE peripheral is guaranteed to accept without negotiating a
    /// larger MTU: the default ATT MTU of 23, less the 3 bytes of write header.
    /// The real limit comes from `maximumWriteValueLength`, which is almost
    /// always larger; this is the floor to fall back on.
    public static let guaranteedSize = 20

    public var maneuver: ManeuverType
    /// Meters to the maneuver.
    public var distanceToManeuver: Double
    /// Meters to the destination.
    public var distanceRemaining: Double
    /// Seconds to the destination.
    public var timeRemaining: TimeInterval
    /// Ground speed in meters per second.
    public var speed: Double
    public var flags: Flags
    public var streetName: String?

    public init(
        maneuver: ManeuverType,
        distanceToManeuver: Double,
        distanceRemaining: Double,
        timeRemaining: TimeInterval,
        speed: Double,
        flags: Flags = [],
        streetName: String? = nil
    ) {
        self.maneuver = maneuver
        self.distanceToManeuver = distanceToManeuver
        self.distanceRemaining = distanceRemaining
        self.timeRemaining = timeRemaining
        self.speed = speed
        self.flags = flags
        self.streetName = streetName
    }

    /// What the HUD is told about conditions, in byte 9.
    public struct Flags: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// The rider has left the route.
        public static let offRoute = Flags(rawValue: 1 << 0)
        /// A replacement route is on its way.
        public static let rerouting = Flags(rawValue: 1 << 1)
        /// The position behind these numbers is not to be trusted.
        public static let weakSignal = Flags(rawValue: 1 << 2)
    }
}

// MARK: - From guidance

extension HUDPacket {
    /// Takes the engine's view of the world.
    ///
    /// With no position yet there is nothing to instruct: the maneuver goes out
    /// as `.unknown` with the distances zeroed, so the HUD shows a blank rather
    /// than the last thing it happened to hear.
    public init(_ state: GuidanceState) {
        var flags: Flags = []
        if state.isOffRoute { flags.insert(.offRoute) }
        if state.isRerouting { flags.insert(.rerouting) }
        if state.hasWeakSignal { flags.insert(.weakSignal) }

        self.init(
            maneuver: state.progress?.maneuver ?? .unknown,
            distanceToManeuver: state.progress?.distanceToManeuver ?? 0,
            distanceRemaining: state.progress?.distanceRemaining ?? 0,
            timeRemaining: state.progress?.timeRemaining ?? 0,
            speed: state.speed,
            flags: flags,
            streetName: state.progress?.streetName
        )
    }
}

// MARK: - Encoding

extension HUDPacket {
    /// Lays the packet out for the wire.
    ///
    /// `maximumSize` is what the link will carry in one write, from
    /// `CBPeripheral.maximumWriteValueLength`. The header is never dropped: a
    /// link that cannot carry ten bytes is a broken link, and a truncated
    /// header would be read as a valid packet full of nonsense.
    public func encoded(maximumSize: Int = HUDPacket.guaranteedSize) -> Data {
        var data = Data(capacity: max(maximumSize, Self.headerSize))

        data.append(Self.version)
        data.append(maneuver.rawValue)
        data.append(littleEndian: saturating(distanceToManeuver))
        data.append(littleEndian: saturating(distanceRemaining, unit: 10))
        data.append(littleEndian: saturating(timeRemaining))
        data.append(saturatingByte(speed * 3.6))
        data.append(flags.rawValue)

        if let name = streetName, maximumSize > Self.headerSize {
            data.append(contentsOf: Self.fit(name, into: maximumSize - Self.headerSize))
        }

        return data
    }

    /// The UTF-8 for as much of `name` as fits in `budget` bytes.
    ///
    /// Cut by character, never by byte. Half of a Ş is not a shorter street
    /// name, it is a broken string, and every other street in Istanbul has one
    /// in it.
    static func fit(_ name: String, into budget: Int) -> [UInt8] {
        let utf8 = Array(name.utf8)
        guard utf8.count > budget else { return utf8 }

        var kept: [UInt8] = []
        kept.reserveCapacity(budget)
        for character in name {
            let bytes = Array(character.utf8)
            guard kept.count + bytes.count <= budget else { break }
            kept.append(contentsOf: bytes)
        }
        return kept
    }

    /// Scales a value into whole units and pins it to the top of the range
    /// rather than letting it wrap.
    private func saturating(_ value: Double, unit: Double = 1) -> UInt16 {
        guard value.isFinite, value > 0 else { return 0 }
        let scaled = (value / unit).rounded()
        return scaled >= Double(UInt16.max) ? .max : UInt16(scaled)
    }

    private func saturatingByte(_ value: Double) -> UInt8 {
        guard value.isFinite, value > 0 else { return 0 }
        let rounded = value.rounded()
        return rounded >= Double(UInt8.max) ? .max : UInt8(rounded)
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }
}
