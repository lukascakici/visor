import Guidance
import SwiftUI

/// Distance left, time left, speed. The trip numbers, kept out of the way of
/// the maneuver.
struct StatusBar: View {
    let state: GuidanceState

    var body: some View {
        HStack {
            reading(
                value: state.progress.map { Format.distance($0.distanceRemaining) } ?? "—",
                caption: "remaining"
            )
            Divider().frame(height: 28)
            reading(
                value: state.progress.map { Format.duration($0.timeRemaining) } ?? "—",
                caption: "to arrive"
            )
            Divider().frame(height: 28)
            reading(value: Format.speed(state.speed), caption: "km/h")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func reading(value: String, caption: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
