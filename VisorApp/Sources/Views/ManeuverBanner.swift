import Guidance
import SwiftUI

/// The band across the top: the one instruction that matters right now.
///
/// Sized for a glance at speed. When the signal cannot be trusted the whole
/// band dims and says so, rather than presenting a stale turn as fact.
struct ManeuverBanner: View {
    let state: GuidanceState

    var body: some View {
        HStack(spacing: 16) {
            if let progress = state.progress {
                Image(systemName: ManeuverGlyph.symbol(progress.maneuver))
                    .font(.system(size: 44, weight: .semibold))
                    .frame(width: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.distance(progress.distanceToManeuver))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(progress.streetName ?? ManeuverGlyph.name(progress.maneuver))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
            } else {
                Image(systemName: "location.slash")
                    .font(.system(size: 36, weight: .semibold))
                    .frame(width: 56)
                Text("Waiting for a position")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .bottom) { warnings }
        .opacity(state.hasWeakSignal ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.2), value: state.hasWeakSignal)
    }

    /// The three flag bits, in the order a rider needs them.
    @ViewBuilder
    private var warnings: some View {
        HStack(spacing: 6) {
            if state.isOffRoute {
                Flag(text: "OFF ROUTE", tint: .red)
            }
            if state.isRerouting {
                Flag(text: "REROUTING", tint: .orange)
            }
            if state.hasWeakSignal {
                Flag(text: "WEAK GPS", tint: .yellow)
            }
        }
        .offset(y: 12)
    }

    private struct Flag: View {
        let text: String
        let tint: Color

        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint, in: Capsule())
                .foregroundStyle(.black)
        }
    }
}
