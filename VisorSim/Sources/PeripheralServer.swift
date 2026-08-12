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
    /// Newest first, capped: this is a window on a live link, not a recording.
    private(set) var recent: [Received] = []
    private(set) var packetCount = 0

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
        let characteristic = CBMutableCharacteristic(
            type: CBUUID(string: VisorService.packetCharacteristic),
            // Write without response only. There is nothing useful to say back,
            // and declaring it this way makes it impossible for a central to
            // wait on an acknowledgement that will never matter.
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        let service = CBMutableService(type: CBUUID(string: VisorService.uuid), primary: true)
        service.characteristics = [characteristic]

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
        for request in requests {
            guard let data = request.value else { continue }
            accept(data)
        }
    }
}
