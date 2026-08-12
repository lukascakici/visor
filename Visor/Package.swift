// swift-tools-version: 6.0
import PackageDescription

// Visor's platform-independent layers. The iOS app and the macOS simulator
// both consume this package as a local dependency, so the logic layers can be
// exercised with `swift test` without a device or a simulator.
let package = Package(
    name: "Visor",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Geometry", targets: ["Geometry"]),
        .library(name: "Guidance", targets: ["Guidance"]),
        .library(name: "Routing", targets: ["Routing"]),
        .library(name: "Transport", targets: ["Transport"]),
        .executable(name: "visor-replay", targets: ["VisorReplay"]),
    ],
    targets: [
        // Shared pure models: Coordinate, Route, ManeuverType and friends.
        // Depends on no Apple framework.
        .target(name: "Core"),

        // Pure geometry: bearing, distance, cross-track distance.
        .target(name: "Geometry", dependencies: ["Core"]),

        // Maneuver classification, off-route detection, ETA. Completely
        // independent of CoreLocation and CoreBluetooth.
        .target(name: "Guidance", dependencies: ["Core", "Geometry"]),

        // MKDirections wrapper: converts MKRoute into Core.Route. This is the
        // only layer that touches MapKit.
        .target(name: "Routing", dependencies: ["Core", "Geometry"]),

        // Binary packet serialization. Pure; no CoreBluetooth dependency.
        .target(name: "Transport", dependencies: ["Core"]),

        // Rides a synthetic track through the guidance engine and prints what
        // would go to the HUD. No device, no simulator, no map service.
        .executableTarget(name: "VisorReplay", dependencies: ["Core", "Geometry", "Guidance"]),

        .testTarget(name: "GeometryTests", dependencies: ["Geometry"]),
        .testTarget(name: "GuidanceTests", dependencies: ["Guidance"]),
        .testTarget(name: "RoutingTests", dependencies: ["Routing"]),
        .testTarget(name: "TransportTests", dependencies: ["Transport"]),
    ]
)
