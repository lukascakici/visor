/// Where one maneuver stops and the next begins, in degrees of turn.
///
/// Each bound is inclusive: a turn of exactly `straight` degrees still counts as
/// going straight. The bands must be listed in increasing order.
public struct ManeuverThresholds: Hashable, Sendable {
    /// Up to here the road is considered to just continue.
    public var straight: Double
    /// Up to here it is a slight left or right.
    public var slight: Double
    /// Up to here it is an ordinary turn.
    public var turn: Double
    /// Up to here it is a sharp turn; past it, a U-turn.
    ///
    /// The spec calls anything over 135 degrees sharp and "around 180" a
    /// U-turn, which leaves the boundary between them open. 160 is the pick:
    /// it keeps genuine hairpins reading as sharp turns, and reserves the
    /// U-turn arrow for a real reversal.
    public var sharp: Double
    /// How much of the geometry either side of a junction feeds the bearing, in
    /// meters.
    ///
    /// Route polylines end in short noisy segments, sometimes a meter or two
    /// long, so a bearing taken from the final segment alone can be off by
    /// tens of degrees. Averaging over a stretch of road instead is what makes
    /// the classification stable.
    public var bearingWindow: Double

    public init(
        straight: Double = 15,
        slight: Double = 45,
        turn: Double = 135,
        sharp: Double = 160,
        bearingWindow: Double = 20
    ) {
        self.straight = straight
        self.slight = slight
        self.turn = turn
        self.sharp = sharp
        self.bearingWindow = bearingWindow
    }

    public static let `default` = ManeuverThresholds()
}
