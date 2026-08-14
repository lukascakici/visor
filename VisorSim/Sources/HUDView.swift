import Core
import SwiftUI
import Transport

/// What the HUD would show, drawn from the decoded packet and nothing else.
///
/// Every value here was read back out of the bytes rather than passed in
/// alongside them. If the encoder and the decoder disagree, this is where it
/// shows.
struct HUDView: View {
    let received: PeripheralServer.Received?
    let path: PeripheralServer.PathFeed

    var body: some View {
        VStack(spacing: 0) {
            if let packet = received?.packet {
                instruction(packet)
                PathView(feed: path, isOffRoute: packet.flags.contains(.offRoute))
                    .padding(.top, 18)
                readings(packet)
                flags(packet)
            } else {
                Text("No packets yet")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding(24)
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
    }

    private func instruction(_ packet: DecodedPacket) -> some View {
        HStack(spacing: 22) {
            Image(systemName: symbol(packet.maneuver))
                .font(.system(size: 66, weight: .semibold))
                .frame(width: 90)

            VStack(alignment: .leading, spacing: 4) {
                Text(packet.distanceToManeuver == 0 ? "now" : "\(packet.distanceToManeuver) m")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                Text(packet.streetName.isEmpty ? "—" : packet.streetName)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .foregroundStyle(.white)
    }

    private func readings(_ packet: DecodedPacket) -> some View {
        HStack(spacing: 0) {
            reading("\(packet.distanceRemaining) m", "to destination")
            reading(clock(packet.timeRemaining), "to arrive")
            reading("\(packet.speed)", "km/h")
        }
        .padding(.top, 22)
    }

    private func reading(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func flags(_ packet: DecodedPacket) -> some View {
        HStack(spacing: 8) {
            badge("OFF ROUTE", .red, on: packet.flags.contains(.offRoute))
            badge("REROUTING", .orange, on: packet.flags.contains(.rerouting))
            badge("WEAK GPS", .yellow, on: packet.flags.contains(.weakSignal))
        }
        .padding(.top, 18)
    }

    private func badge(_ text: String, _ tint: Color, on: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(on ? tint : Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(on ? .black : .white.opacity(0.3))
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func symbol(_ maneuver: ManeuverType) -> String {
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
}
