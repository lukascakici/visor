import CoreGraphics
import Foundation

/// The device's framebuffer, rendered by the device's own code.
///
/// Packets go in as the bytes that arrived; pixels come out. Nothing in between
/// is Swift: the decoding, the crossing between packets and every line drawn
/// are the C in `Firmware/main`, compiled into this app. Which means the
/// preview cannot flatter the firmware, and a layout that falls off the round
/// glass falls off it here first.
final class DeviceScreen {
    /// Pixels across, which is the only thing that changes between panels.
    ///
    /// Nothing in the firmware's layout is written in pixels: every band, every
    /// arrow and the whole map are worked out from the canvas it is handed. So
    /// a denser panel costs a number here and a driver on the device, and not
    /// one line of the drawing.
    let size: Int

    private var state = visor_hud_state_t()
    private var pixels: [UInt16]
    private var rgba: [UInt8]
    private let started = DispatchTime.now().uptimeNanoseconds

    init(size: Int) {
        self.size = size
        self.pixels = [UInt16](repeating: 0, count: size * size)
        self.rgba = [UInt8](repeating: 0, count: size * size * 4)
        visor_hud_reset(&state)
    }

    /// The device's clock, which is what paces the crossing between packets.
    private var microseconds: Int64 {
        Int64((DispatchTime.now().uptimeNanoseconds &- started) / 1000)
    }

    func receiveGuidance(_ data: Data) {
        let now = microseconds
        data.withUnsafeBytes { raw in
            visor_hud_receive_guidance(&state, raw.bindMemory(to: UInt8.self).baseAddress, data.count, now)
        }
    }

    func receivePath(_ data: Data) {
        let now = microseconds
        data.withUnsafeBytes { raw in
            visor_hud_receive_path(&state, raw.bindMemory(to: UInt8.self).baseAddress, data.count, now)
        }
    }

    /// Renders a frame and hands it back as an image.
    ///
    /// On round glass the corners are not dark, they are absent, so they come
    /// back transparent rather than black. Anything the firmware drew out there
    /// is something a rider would never have seen.
    func frame(round: Bool) -> CGImage? {
        let now = microseconds
        let shape = round ? VISOR_PANEL_ROUND : VISOR_PANEL_SQUARE

        let width = size
        pixels.withUnsafeMutableBufferPointer { buffer in
            var canvas = visor_canvas_t(
                pixels: buffer.baseAddress,
                width: Int32(width),
                height: Int32(width)
            )
            visor_hud_render(&canvas, &state, now, shape)
        }

        let radius = Double(size) / 2
        for index in 0..<(size * size) {
            let pixel = pixels[index]
            rgba[index * 4] = UInt8(Int((pixel >> 11) & 0x1F) * 255 / 31)
            rgba[index * 4 + 1] = UInt8(Int((pixel >> 5) & 0x3F) * 255 / 63)
            rgba[index * 4 + 2] = UInt8(Int(pixel & 0x1F) * 255 / 31)

            guard round else {
                rgba[index * 4 + 3] = 255
                continue
            }
            let dx = Double(index % size) - radius
            let dy = Double(index / size) - radius
            rgba[index * 4 + 3] = dx * dx + dy * dy <= radius * radius ? 255 : 0
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }

        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
