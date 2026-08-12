/// The Bluetooth identifiers both ends of the link agree on.
///
/// Kept as strings rather than `CBUUID`s so this stays in a layer that knows
/// nothing about CoreBluetooth: the phone builds a central from them, the HUD
/// builds a peripheral, and the wire format they exchange is defined next door.
public enum VisorService {
    /// The service the HUD advertises and the phone scans for.
    public static let uuid = "A1B2C3D4-0001-4A6F-9B1E-5F3C2D7E8A90"

    /// The characteristic guidance packets are written to.
    ///
    /// Written without a response, once a second. An acknowledgement per packet
    /// would buy nothing: by the time a lost packet could be noticed and resent
    /// the next one is already due, and it carries fresher numbers.
    public static let packetCharacteristic = "A1B2C3D4-0002-4A6F-9B1E-5F3C2D7E8A90"

    /// The name the HUD advertises itself under.
    public static let advertisedName = "Visor HUD"
}
