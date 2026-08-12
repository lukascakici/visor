import Core
import Foundation
import Guidance
import Observation
import Routing
import Simulation
import Transport

/// Drives the guidance engine and holds what the screen shows.
///
/// One timer, one beat: the same 1 Hz the HUD will be written at. Everything
/// that decides anything lives in the engine underneath; this feeds it, asks
/// the map service for a route when one is needed, and publishes the answer.
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
    /// Where the rider is heading, once one has been chosen.
    private(set) var destination: Place?
    /// What went wrong the last time a route was asked for.
    private(set) var routingProblem: String?
    private(set) var isPlanning = false

    var scenario: Scenario = .ride {
        didSet { restart() }
    }

    var source: Source = .replay {
        didSet { restart() }
    }

    /// The radio. Observed through its own properties, so the screen can show
    /// what the link is doing without this having to mirror any of it.
    @ObservationIgnored let link = HUDLink()

    @ObservationIgnored private var engine: GuidanceEngine
    @ObservationIgnored private var locations: any LocationSource
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let planner = RoutePlanner()
    @ObservationIgnored private var pendingReroute: Task<Void, Never>?

    init() {
        let route = DemoRoute.make()
        let engine = GuidanceEngine(route: route)
        let locations = ReplaySource(route: route, scenario: .ride)

        self.route = route
        self.engine = engine
        self.locations = locations
        // Read from the local, not from `self`: under @Observable the stored
        // properties are accessors, and none of them may be touched until every
        // one of them has been assigned.
        self.state = engine.state(at: locations.now)
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
        pendingReroute?.cancel()

        engine = GuidanceEngine(route: route)
        switch source {
        case .replay: locations = ReplaySource(route: route, scenario: scenario)
        case .device: locations = DeviceLocationSource()
        }
        state = engine.state(at: locations.now)

        if wasRunning { start() }
    }

    // MARK: - Choosing where to go

    /// Where a route would start from: wherever the rider is, or the demo
    /// route's origin before anything has been heard from the receiver.
    var origin: Coordinate {
        state.progress?.snapped ?? route.polyline.first ?? DemoRoute.origin
    }

    /// Asks the map service for a route to `place` and rides it.
    func setDestination(_ place: Place) async {
        isPlanning = true
        routingProblem = nil
        defer { isPlanning = false }

        do {
            let planned = try await planner.route(from: origin, to: place.coordinate)
            destination = place
            route = planned
            restart()
            start()
        } catch {
            routingProblem = describe(error)
        }
    }

    /// Goes back to the hand-built route, which needs no network.
    func useDemoRoute() {
        pendingReroute?.cancel()
        destination = nil
        routingProblem = nil
        route = DemoRoute.make()
        restart()
        start()
    }

    // MARK: - The beat

    private func tick() {
        if let fix = locations.tick() {
            engine.receive(fix)
        }

        let now = locations.now
        state = engine.state(at: now)

        // The beat the whole thing is built around: one packet a second,
        // whether or not a fix arrived, because a display that hears nothing
        // cannot tell a quiet phone from a dead one.
        link.send(HUDPacket(state))

        if engine.shouldRequestReroute(at: now) {
            requestReroute(at: now)
        }

        if let replay = locations as? ReplaySource, replay.hasFinished {
            stop()
        }
    }

    /// Asks for a replacement route from where the rider actually is.
    ///
    /// Only ever one request at a time, and the engine decides when another is
    /// allowed: a route service that is throttling must not be asked again a
    /// second later.
    private func requestReroute(at now: Date) {
        guard let destination, pendingReroute == nil else { return }

        engine.beginRerouting(at: now)
        let from = state.progress?.snapped ?? origin

        pendingReroute = Task { [planner] in
            defer { pendingReroute = nil }
            do {
                let replacement = try await planner.route(from: from, to: destination.coordinate)
                guard !Task.isCancelled else { return }
                route = replacement
                engine.adopt(replacement)
                // The replayed rider has to be put back on the new road; a live
                // one is already on it.
                if source == .replay {
                    locations = ReplaySource(route: replacement, scenario: .ride)
                }
            } catch {
                routingProblem = describe(error)
                engine.cancelRerouting()
            }
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case RoutePlanner.Failure.noRouteFound: "No route to there"
        case RoutePlanner.Failure.throttled: "The map service is busy, trying again shortly"
        case RoutePlanner.Failure.failed(let reason): reason
        default: error.localizedDescription
        }
    }
}
