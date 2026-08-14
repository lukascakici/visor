import Core
import Foundation
import Guidance

/// The shape of the road, sent alongside the guidance packet.
///
/// The layout, version 1, is fixed and little-endian:
///
///     byte  0      protocol version
///     byte  1      number of points
///     byte  2      index of the maneuver point, 255 for none
///     byte  3      padding, zero
///     bytes 4...   points, each int16 right then int16 ahead, decimeters
///
/// Coordinates, not pixels. A 240x240 display holds 115 kB of them, which no
/// Bluetooth link is going to carry once a second, while the same road as forty
/// points is 164 bytes and comes out sharp instead of smeared. It also means
/// the packet says nothing about the display it is going to: the device decides
/// how much road to show and how thick to draw it.
///
/// Decimeters in an int16 reach 3.2 km either way, which is six times the road
/// this ever carries, and resolve to 10 cm, which is finer than GPS can place
/// the rider. Values beyond that saturate rather than wrap, as everywhere else.
///
/// Byte 3 is padding rather than a field looking for a purpose: it puts the
/// points on a four-byte boundary, which is where firmware reading them two
/// bytes at a time wants them.
public struct PathPacket: Hashable, Sendable {
    /// The version in byte 0. This layout's own, unrelated to the guidance
    /// packet's: the two travel on different characteristics and can change
    /// independently.
    public static let version: UInt8 = 1

    /// The fixed part, before the points.
    public static let headerSize = 4

    /// Bytes per point: two int16s.
    public static let pointSize = 4

    /// Byte 2 when no junction falls inside the drawn stretch. Safe as a
    /// sentinel: 255 points means indices 0 through 254, so it can never be a
    /// real one.
    public static let noManeuver: UInt8 = 0xFF

    /// The floor a link is guaranteed to carry, shared with the guidance
    /// packet because it comes from the same default ATT MTU.
    public static let guaranteedSize = HUDPacket.guaranteedSize

    public var path: RoutePath

    public init(_ path: RoutePath) {
        self.path = path
    }

    /// How many points a write of `maximumSize` bytes has room for.
    ///
    /// This is what sizes the path before it is built, so the geometry is
    /// simplified to what the link can carry rather than being built and then
    /// cut short.
    public static func points(fitting maximumSize: Int) -> Int {
        max(0, min(255, (maximumSize - headerSize) / pointSize))
    }
}

// MARK: - Encoding

extension PathPacket {
    /// Lays the packet out for the wire.
    ///
    /// Points past `maximumSize` are dropped from the far end, so an
    /// undersized write shortens the road ahead rather than corrupting it. If
    /// the junction is among the ones dropped, the marker goes with it: a
    /// device told the turn is at a point that is no longer there would draw it
    /// somewhere it is not.
    public func encoded(maximumSize: Int = PathPacket.guaranteedSize) -> Data {
        let room = Self.points(fitting: maximumSize)
        let points = path.points.prefix(room)

        var marker = Self.noManeuver
        if let index = path.maneuverIndex, index >= 0, index < points.count {
            marker = UInt8(index)
        }

        var data = Data(capacity: Self.headerSize + points.count * Self.pointSize)
        data.append(Self.version)
        data.append(UInt8(points.count))
        data.append(marker)
        data.append(0)

        for point in points {
            data.append(littleEndian: Self.decimeters(point.right))
            data.append(littleEndian: Self.decimeters(point.ahead))
        }

        return data
    }

    /// Meters as tenths, pinned to the ends of the range rather than wrapped.
    private static func decimeters(_ meters: Double) -> Int16 {
        guard meters.isFinite else { return 0 }

        let scaled = (meters * 10).rounded()
        if scaled >= Double(Int16.max) { return .max }
        if scaled <= Double(Int16.min) { return .min }
        return Int16(scaled)
    }
}

private extension Data {
    mutating func append(littleEndian value: Int16) {
        let bits = UInt16(bitPattern: value)
        append(UInt8(bits & 0xFF))
        append(UInt8(bits >> 8))
    }
}
