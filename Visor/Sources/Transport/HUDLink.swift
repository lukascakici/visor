import CoreBluetooth
import Foundation
import Observation

/// The radio link to the HUD.
///
/// Finds the display, keeps hold of it, and writes a packet whenever it is
/// given one. Everything about what to write lives elsewhere; this only
/// concerns itself with getting bytes across.
///
/// Reconnection is left to CoreBluetooth: a `connect` request that is never
/// cancelled stays pending forever, so a display that goes out of range at a
/// junction and comes back two streets later reconnects on its own, without a
/// retry loop here guessing at how long to wait.
@Observable
public final class HUDLink: NSObject {
    public enum State: Equatable, Sendable {
        case starting
        case bluetoothOff
        case unauthorized
        case unsupported
        case searching
        case connecting
        case connected

        public var label: String {
            switch self {
            case .starting: "Starting"
            case .bluetoothOff: "Bluetooth is off"
            case .unauthorized: "Bluetooth not allowed"
            case .unsupported: "No Bluetooth on this device"
            case .searching: "Looking for the display"
            case .connecting: "Connecting"
            case .connected: "Connected"
            }
        }
    }

    public private(set) var state: State = .starting
    public private(set) var packetsSent = 0
    /// Packets thrown away because the radio was not ready for them.
    ///
    /// Not a failure to hide: at one packet a second, a queue would only ever
    /// deliver stale instructions late. Better to drop one and send fresher
    /// numbers a second later, and to be able to see how often that happens.
    public private(set) var packetsDropped = 0
    public private(set) var lastPacketSize = 0

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var display: CBPeripheral?
    @ObservationIgnored private var characteristic: CBCharacteristic?

    // Instance properties rather than statics: CBUUID is not Sendable, and a
    // shared global of one would be a data race waiting to be noticed.
    @ObservationIgnored private let serviceID = CBUUID(string: VisorService.uuid)
    @ObservationIgnored private let characteristicID = CBUUID(string: VisorService.packetCharacteristic)

    public override init() {
        super.init()
    }

    /// Brings the radio up.
    ///
    /// Called at launch rather than when a ride starts: with a restoration
    /// identifier, iOS can relaunch the app in the background to hand back a
    /// connection, and the manager has to be recreated with the same identifier
    /// early enough for that hand-back to find it.
    public func start() {
        guard central == nil else { return }

        var options: [String: Any] = [:]
        #if os(iOS)
        options[CBCentralManagerOptionRestoreIdentifierKey] = "com.visor.hud-link"
        #endif
        central = CBCentralManager(delegate: self, queue: .main, options: options)
    }

    public func stop() {
        central?.stopScan()
        if let display {
            central?.cancelPeripheralConnection(display)
        }
        display = nil
        characteristic = nil
        state = central == nil ? .starting : .searching
    }

    /// Writes one packet, if there is anywhere to write it.
    ///
    /// The payload is sized to what this particular link will carry, which is
    /// only known once connected: a display that negotiated a larger MTU gets
    /// the whole street name, one that did not gets as much of it as fits.
    public func send(_ packet: HUDPacket) {
        guard let display, let characteristic, state == .connected else { return }

        guard display.canSendWriteWithoutResponse else {
            packetsDropped += 1
            return
        }

        let limit = display.maximumWriteValueLength(for: .withoutResponse)
        let data = packet.encoded(maximumSize: limit)
        display.writeValue(data, for: characteristic, type: .withoutResponse)

        packetsSent += 1
        lastPacketSize = data.count
    }
}

// MARK: - Finding and keeping the display

extension HUDLink: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // A display this app connected to before may still be connected at
            // the system level, from a previous run or another app. Adopting it
            // is quicker than advertising and scanning all over again.
            if let known = central.retrieveConnectedPeripherals(withServices: [serviceID]).first {
                connect(to: known, using: central)
            } else {
                beginScanning(with: central)
            }
        case .poweredOff:
            state = .bluetoothOff
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unsupported
        default:
            state = .starting
        }
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Relaunched in the background with connections still in hand. Picking
        // the peripheral back up here is what keeps a ride going after iOS has
        // decided to reclaim the app mid-journey.
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]
        guard let peripheral = restored?.first else { return }

        display = peripheral
        peripheral.delegate = self
        state = peripheral.state == .connected ? .connecting : .searching
        if peripheral.state == .connected {
            peripheral.discoverServices([serviceID])
        }
    }

    private func beginScanning(with central: CBCentralManager) {
        state = .searching
        central.scanForPeripherals(withServices: [serviceID])
    }

    private func connect(to peripheral: CBPeripheral, using central: CBCentralManager) {
        display = peripheral
        peripheral.delegate = self
        state = .connecting
        central.stopScan()
        central.connect(peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        connect(to: peripheral, using: central)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        characteristic = nil
        beginScanning(with: central)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        characteristic = nil
        state = .connecting
        // Left pending on purpose: this is the request that reconnects by
        // itself when the display comes back.
        central.connect(peripheral)
    }
}

// MARK: - Finding the characteristic to write to

extension HUDLink: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            return
        }
        peripheral.discoverCharacteristics([characteristicID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let match = service.characteristics?.first(where: { $0.uuid == characteristicID }) else {
            return
        }
        characteristic = match
        state = .connected
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        // Nothing to flush: the next packet is a second away and will be more
        // accurate than anything held back would have been.
    }
}
