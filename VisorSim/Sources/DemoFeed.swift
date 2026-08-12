import Core
import Foundation
import Guidance
import Observation
import Simulation
import Transport

/// Feeds the display packets from a replayed ride, without any Bluetooth in
/// between.
///
/// The point is to be able to tell two failures apart. If the display is wrong
/// under the demo feed, the fault is here. If it is right under the demo feed
/// and wrong over the air, the fault is in the link.
@Observable
final class DemoFeed {
    private(set) var isRunning = false

    @ObservationIgnored private let route = DemoRoute.make()
    @ObservationIgnored private var engine: GuidanceEngine
    @ObservationIgnored private var ride: Ride
    @ObservationIgnored private var second = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let departure = Date(timeIntervalSince1970: 1_700_000_000)

    init() {
        let route = DemoRoute.make()
        self.engine = GuidanceEngine(route: route)
        self.ride = Ride(route: route, scenario: .ride)
    }

    func start(into server: PeripheralServer) {
        guard !isRunning else { return }
        isRunning = true

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick(into: server)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func tick(into server: PeripheralServer) {
        if second > ride.duration {
            restart()
        }

        let now = departure.addingTimeInterval(Double(second))
        if let fix = ride.fix(atSecond: second, now: now) {
            engine.receive(fix)
        }

        let packet = HUDPacket(engine.state(at: now))
        server.accept(packet.encoded(maximumSize: HUDPacket.guaranteedSize))
        second += 1
    }

    private func restart() {
        engine = GuidanceEngine(route: route)
        ride = Ride(route: route, scenario: .ride)
        second = 0
    }
}
