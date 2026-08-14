import SwiftUI

/// A panel the ESP32-S3 could actually be given, and how coarse it would look.
///
/// Listed by the two numbers that decide that: how many pixels there are and
/// how far apart they are spread. The second is the one people mean when they
/// say a screen looks pixelated, and it is the one a bigger panel makes worse
/// rather than better.
struct DeviceGlass: Identifiable, Hashable {
    let label: String
    let pixels: Int
    let inches: Double
    /// Whether the framebuffer needs to live in PSRAM. Past about 300 pixels a
    /// side, two bytes a pixel no longer fits comfortably in the S3's own SRAM
    /// alongside a Bluetooth stack.
    let needsPSRAM: Bool

    var id: String { label }
    var density: Int { Int((Double(pixels) / inches).rounded()) }
    var framebufferKB: Int { pixels * pixels * 2 / 1024 }

    static let all = [
        DeviceGlass(label: "1.28″ 240", pixels: 240, inches: 1.28, needsPSRAM: false),
        DeviceGlass(label: "1.43″ 466", pixels: 466, inches: 1.43, needsPSRAM: true),
        DeviceGlass(label: "2.1″ 480", pixels: 480, inches: 2.1, needsPSRAM: true),
    ]
}

/// The HUD as the hardware would show it.
///
/// Redrawn as fast as the Mac will redraw anything, because the road is crossed
/// between packets and the whole point of that work is only visible in motion.
/// The pixels are not smoothed on the way up to screen size: a preview that
/// interpolated them would hide exactly the coarseness being judged.
struct DevicePanel: View {
    let screen: DeviceScreen
    let glass: DeviceGlass

    private let shown = 320.0

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation) { _ in
                ZStack {
                    Circle()
                        .fill(.black)
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 8))

                    if let frame = screen.frame(round: true) {
                        Image(decorative: frame, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: shown, height: shown)
                    }
                }
                .frame(width: shown, height: shown)
            }

            // The number that answers "will it really look like this": how far
            // apart the pixels are. A phone sits near 460, and this preview is
            // magnified several times over, so it exaggerates whatever it has.
            Text("\(glass.pixels)×\(glass.pixels) · \(glass.inches, specifier: "%.2f")″ · \(glass.density) PPI  (a phone is ~460)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(glass.needsPSRAM
                ? "\(glass.framebufferKB) KB framebuffer — needs a module with PSRAM"
                : "\(glass.framebufferKB) KB framebuffer — fits in the S3's own SRAM")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(glass.needsPSRAM ? .orange.opacity(0.8) : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
    }
}
