import Core
import CoreBluetooth
import Foundation
import Observation
import Transport

/// Pretends to be the HUD.
///
/// Advertises the Visor service, accepts writes to the packet characteristic,
/// and decodes whatever arrives. Standing in for hardware that does not exist
/// yet, its job is to be honest about what actually came over the air rather
/// than to look good doing it.
@Observable
final class PeripheralServer: NSObject, CBPeripheralManagerDelegate {
    enum Status: Equatable {
        case starting
        case advertising
        case receiving
        case bluetoothOff
        case unauthorized
        case unsupported

        var label: String {
            switch self {
            case .starting: "Starting"
            case .advertising: "Advertising, waiting for the phone"
            case .receiving: "Receiving packets"
            case .bluetoothOff: "Bluetooth is off"
            case .unauthorized: "Not allowed to use Bluetooth"
            case .unsupported: "No Bluetooth on this Mac"
            }
        }
    }

    /// One packet as it arrived, kept whole so the raw bytes stay inspectable.
    struct Received: Identifiable {
        let id = UUID()
        let at: Date
        let data: Data
        let packet: DecodedPacket
    }

    private(set) var status: Status = .starting
    private(set) var latest: Received?
    /// The last two paths and when the newer one landed.
    ///
    /// Two rather than one because a display that only ever knows the newest
    /// road can only ever jump to it. Everything needed to draw the road
    /// *moving* is here: where it was, where it is, and how long the crossing
    /// between them should take.
    struct PathFeed: Equatable {
        var latest: DecodedPath?
        var previous: DecodedPath?
        var arrivedAt: Date?
        /// Measured rather than assumed, so the drawing keeps up with whatever
        /// rate the phone actually manages.
        var interval: TimeInterval = 1
    }

    /// The shape of the road as last written, decoded from its own bytes.
    ///
    /// Held separately from `latest` because the two arrive on separate
    /// characteristics and either can go missing on its own. A display still
    /// showing a map while the instructions have stopped is a fault worth being
    /// able to see rather than one to paper over.
    private(set) var path = PathFeed()
    /// Newest first, capped: this is a window on a live link, not a recording.
    private(set) var recent: [Received] = []
    private(set) var packetCount = 0
    private(set) var pathCount = 0

    @ObservationIgnored private var manager: CBPeripheralManager?
    @ObservationIgnored private var lastArrival: Date?

    func start() {
        guard manager == nil else { return }
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    /// Takes a packet as though it had come over the air. The demo feed uses
    /// this so the display can be seen working before a phone exists to talk
    /// to it.
    func accept(_ data: Data) {
        guard let packet = DecodedPacket(data) else { return }

        let received = Received(at: Date(), data: data, packet: packet)
        latest = received
        recent.insert(received, at: 0)
        if recent.count > 40 { recent.removeLast(recent.count - 40) }
        packetCount += 1
        lastArrival = received.at

        if status == .advertising { status = .receiving }
    }

    /// Takes a path packet the same way, from the air or from the demo feed.
    func acceptPath(_ data: Data) {
        guard let decoded = DecodedPath(data) else { return }

        let now = Date()
        // A gap that is neither a duplicate nor a reconnection is what the
        // packets are actually arriving at; anything else is not worth pacing
        // the drawing to.
        if let last = path.arrivedAt {
            let gap = now.timeIntervalSince(last)
            if gap > 0.05, gap < 3 { path.interval = gap }
        }

        path.previous = path.latest
        path.latest = decoded
        path.arrivedAt = now
        pathCount += 1
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            publishService(on: peripheral)
        case .poweredOff:
            status = .bluetoothOff
        case .unauthorized:
            status = .unauthorized
        case .unsupported:
            status = .unsupported
        default:
            status = .starting
        }
    }

    private func publishService(on peripheral: CBPeripheralManager) {
        // Write without response only, both of them. There is nothing useful to
        // say back, and declaring it this way makes it impossible for a central
        // to wait on an acknowledgement that will never matter.
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: VisorService.packetCharacteristic),
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        let path = CBMutableCharacteristic(
            type: CBUUID(string: VisorService.pathCharacteristic),
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        let service = CBMutableService(type: CBUUID(string: VisorService.uuid), primary: true)
        service.characteristics = [characteristic, path]

        peripheral.removeAllServices()
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            status = .starting
            return
        }

        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: VisorService.advertisedName,
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: VisorService.uuid)],
        ])
        status = .advertising
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // No `respond(to:)` here on purpose: these are writes without response,
        // and answering one is an error rather than a courtesy.
        let pathID = CBUUID(string: VisorService.pathCharacteristic)

        for request in requests {
            guard let data = request.value else { continue }
            if request.characteristic.uuid == pathID {
                acceptPath(data)
            } else {
                accept(data)
            }
        }
    }
}
