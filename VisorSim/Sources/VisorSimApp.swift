import SwiftUI
import Transport

@main
struct VisorSimApp: App {
    var body: some Scene {
        WindowGroup("Visor HUD Simulator") {
            SimulatorView()
                .frame(minWidth: 620, minHeight: 860)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
    }
}

/// The whole simulator: what the HUD would show on top, the bytes that produced
/// it underneath.
struct SimulatorView: View {
    /// What is being looked at: the device's own pixels, or the same packets
    /// spelled out. The first answers "what will a rider see", the second
    /// answers "did the right bytes arrive", and neither substitutes for the
    /// other.
    @State private var server = PeripheralServer()
    @State private var feed = DemoFeed()
    @State private var glass = DeviceGlass.all[0]
    @State private var showReadout = false
    @State private var screen = DeviceScreen(size: DeviceGlass.all[0].pixels)

    var body: some View {
        VStack(spacing: 16) {
            header

            Picker("", selection: Binding(
                get: { showReadout ? nil : glass },
                set: { choice in
                    showReadout = choice == nil
                    if let choice { glass = choice }
                }
            )) {
                ForEach(DeviceGlass.all) { Text($0.label).tag(Optional($0)) }
                Text("Readout").tag(DeviceGlass?.none)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if showReadout {
                HUDView(received: server.latest, path: server.path)
            } else {
                DevicePanel(screen: screen, glass: glass)
            }

            log
        }
        .padding(16)
        .onAppear { server.start() }
        // A different panel is a different framebuffer, so it is a different
        // screen. Handing it the packets already in hand saves it a second of
        // looking blank for no reason.
        .onChange(of: glass) {
            let fresh = DeviceScreen(size: glass.pixels)
            if let data = server.latest?.data { fresh.receiveGuidance(data) }
            if let data = server.path.data { fresh.receivePath(data) }
            screen = fresh
        }
        // Fed the bytes as they land, not the decoded packets: the firmware
        // does its own decoding, and letting it is the only way the preview
        // proves anything.
        .onChange(of: server.packetCount) {
            if let data = server.latest?.data { screen.receiveGuidance(data) }
        }
        .onChange(of: server.pathCount) {
            if let data = server.path.data { screen.receivePath(data) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(server.status.label)
                    .font(.system(size: 13, weight: .medium))
                Text("\(server.packetCount) packets, \(server.pathCount) maps received")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Demo feed", isOn: Binding(
                get: { feed.isRunning },
                set: { $0 ? feed.start(into: server) : feed.stop() }
            ))
            .toggleStyle(.switch)
            .help("Feeds the display from a replayed ride, with no Bluetooth in between")
        }
    }

    private var tint: Color {
        switch server.status {
        case .receiving: .green
        case .advertising: .blue
        case .starting: .gray
        default: .red
        }
    }

    /// The raw traffic. A HUD that looks right for the wrong reason is caught
    /// here and nowhere else.
    private var log: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PACKETS")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(server.recent) { received in
                        HStack(spacing: 10) {
                            Text(hex(received.data.prefix(10)))
                            Text("\(received.data.count)B")
                                .foregroundStyle(.secondary)
                            Text(received.packet.streetName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
        }
    }

    private func hex(_ data: some Sequence<UInt8>) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
