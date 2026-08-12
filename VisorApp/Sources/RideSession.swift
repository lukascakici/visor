import Core
import Foundation
import Guidance
import Observation
import Simulation

/// Drives the guidance engine and holds what the screen shows.
///
/// One timer, one beat: the same 1 Hz the HUD will be written at. Everything
/// that decides anything lives in the engine underneath; this only feeds it and
/// publishes the answer.
@Observable
final class RideSession {
    enum Source: String, CaseIterable, Identifiable {
        /// A scripted ride, which is what makes this run without a receiver.
        case replay
        /// The device's own receiver.
        case device

        var id: String { rawValue }
        var label: String { self == .replay ? "Replay" : "Live GPS" }
    }

    private(set) var route: Route
    private(set) var state: GuidanceState
    private(set) var isRunning = false

    var scenario: Scenario = .ride {
        didSet { restart() }
    }

    var source: Source = .replay {
        didSet { restart() }
    }

    private var engine: GuidanceEngine
    private var locations: any LocationSource
    private var timer: Timer?

    init() {
        let route = DemoRoute.make()
        self.route = route
        self.engine = GuidanceEngine(route: route)
        self.locations = ReplaySource(route: route, scenario: .ride)
        self.state = engine.state(at: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - Running

    func start() {
        guard !isRunning else { return }
        isRunning = true

        (locations as? DeviceLocationSource)?.start()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        (locations as? DeviceLocationSource)?.stop()
    }

    func restart() {
        let wasRunning = isRunning
        stop()

        engine = GuidanceEngine(route: route)
        locations = switch source {
        case .replay: ReplaySource(route: route, scenario: scenario)
        case .device: DeviceLocationSource()
        }
        state = engine.state(at: locations.now)

        if wasRunning { start() }
    }

    private func tick() {
        if let fix = locations.tick() {
            engine.receive(fix)
        }

        let now = locations.now
        state = engine.state(at: now)

        // Where the reroute will be kicked off once MKDirections is wired in.
        // Until then the flag going up and staying up is the honest picture:
        // the route has been left and nothing is coming to replace it.
        if engine.shouldRequestReroute(at: now) {
            engine.beginRerouting(at: now)
        }

        if let replay = locations as? ReplaySource, replay.hasFinished {
            stop()
        }
    }
}
