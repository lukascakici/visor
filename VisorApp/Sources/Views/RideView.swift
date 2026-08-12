import Core
import Guidance
import MapKit
import Simulation
import SwiftUI

/// The one screen there is: the route on a map, the next maneuver over it, and
/// the controls that stand in for a rider until there is a device to ride with.
struct RideView: View {
    @State private var session = RideSession()
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()

            ManeuverBanner(state: session.state)
                .padding(.horizontal, 12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                StatusBar(state: session.state)
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear {
            camera = .region(region(around: session.route.polyline.first))
            session.start()
        }
        .onChange(of: session.state.progress?.snapped) { _, snapped in
            guard let snapped else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                camera = .region(region(around: snapped))
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            MapPolyline(coordinates: session.route.polyline.map(\.asCLCoordinate))
                .stroke(.cyan.opacity(0.85), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))

            if let destination = session.route.polyline.last {
                Annotation("", coordinate: destination.asCLCoordinate) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .black)
                }
            }

            if let progress = session.state.progress {
                // Where the rider actually is, and where the route says that
                // is. The gap between the two is the off-route distance, so
                // showing both makes the decision visible.
                Annotation("", coordinate: progress.snapped.asCLCoordinate) {
                    Circle()
                        .fill(session.state.isOffRoute ? .red : .cyan)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private func region(around coordinate: Coordinate?) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: (coordinate ?? DemoRoute.origin).asCLCoordinate,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Scenario", selection: Binding(get: { session.scenario }, set: { session.scenario = $0 })) {
                ForEach(Scenario.allCases, id: \.self) { scenario in
                    Text(scenario.rawValue.capitalized).tag(scenario)
                }
            }
            .pickerStyle(.segmented)
            .disabled(session.source == .device)

            HStack(spacing: 10) {
                Picker("Source", selection: Binding(get: { session.source }, set: { session.source = $0 })) {
                    ForEach(RideSession.Source.allCases) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    session.isRunning ? session.stop() : session.start()
                } label: {
                    Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    session.restart()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    RideView()
        .preferredColorScheme(.dark)
}
