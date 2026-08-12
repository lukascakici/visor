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
        .library(name: "Simulation", targets: ["Simulation"]),
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

        // MKDirections wrapper: converts MKRoute into Core.Route, maneuvers and
        // all. The only layer that touches MapKit.
        .target(name: "Routing", dependencies: ["Core", "Geometry", "Guidance"]),

        // Binary packet serialization: guidance in, bytes out. Depends on
        // Guidance because that is what it serializes, and on nothing from
        // CoreBluetooth, so the wire format can be tested without a radio.
        .target(name: "Transport", dependencies: ["Core", "Guidance"]),

        // A route and a rider to try the guidance engine against while there is
        // no device, no map service and nobody actually riding. Used by both
        // the replay tool and the iOS app.
        .target(name: "Simulation", dependencies: ["Core", "Geometry", "Guidance"]),

        // Rides a synthetic track through the guidance engine and prints what
        // would go to the HUD.
        .executableTarget(
            name: "VisorReplay",
            dependencies: ["Core", "Geometry", "Guidance", "Routing", "Simulation", "Transport"]
        ),

        .testTarget(name: "GeometryTests", dependencies: ["Geometry"]),
        .testTarget(name: "GuidanceTests", dependencies: ["Guidance"]),
        .testTarget(name: "RoutingTests", dependencies: ["Routing"]),
        .testTarget(name: "TransportTests", dependencies: ["Transport"]),
    ]
)
