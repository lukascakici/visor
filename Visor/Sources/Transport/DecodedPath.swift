import Core
import Foundation

/// A path packet read back off the wire, in the units the wire carries.
///
/// Like `DecodedPacket`, this keeps the quantization visible instead of
/// converting it away: every coordinate here is a whole decimeter, because
/// that is all that was sent. A renderer divides by ten.
public struct DecodedPath: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        /// Decimeters to the rider's right; negative is to the left.
        public let right: Int
        /// Decimeters in front of the rider; negative is behind.
        public let ahead: Int

        public init(right: Int, ahead: Int) {
            self.right = right
            self.ahead = ahead
        }
    }

    public let version: UInt8
    public let points: [Point]
    /// Which point the maneuver sits at, when the packet named one that exists.
    public let maneuverIndex: Int?
    /// How far along the points the rider is, `0` to `1`.
    public let riderFraction: Double
}

extension DecodedPath {
    /// Reads a path packet, or returns `nil` if there is not a whole header
    /// there.
    ///
    /// Lenient in the same way as the guidance decoder: a write that arrived
    /// short of the points it promised yields the points that did arrive, and a
    /// version this build does not know is reported rather than refused. A
    /// device that draws a shorter road is still guiding; one that draws
    /// nothing has given up.
    public init?(_ data: Data) {
        guard data.count >= PathPacket.headerSize else { return nil }

        let bytes = [UInt8](data)
        let promised = Int(bytes[1])
        let arrived = (bytes.count - PathPacket.headerSize) / PathPacket.pointSize
        let count = min(promised, arrived)

        var points: [Point] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let offset = PathPacket.headerSize + index * PathPacket.pointSize
            points.append(Point(
                right: Int(value(bytes, at: offset)),
                ahead: Int(value(bytes, at: offset + 2))
            ))
        }

        let marker = Int(bytes[2])
        self.version = bytes[0]
        self.points = points
        self.maneuverIndex = marker < points.count ? marker : nil
        self.riderFraction = Double(bytes[3]) / 255
    }
}

private func value(_ bytes: [UInt8], at index: Int) -> Int16 {
    Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
}
