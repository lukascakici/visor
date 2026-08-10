# Visor

An iOS app that sends turn-by-turn navigation data over BLE to an external HUD
device for motorcycle and bicycle riders. The phone computes the route, derives
the maneuvers, and pushes a binary packet to the device at 1 Hz.

**Phase 1:** there is no physical device yet, so this repo also contains a BLE
peripheral simulator for macOS.

## Layout

    Visor/       SwiftPM package — platform-independent, testable layers
      Sources/Core        shared pure models (Coordinate, Route, ManeuverType)
      Sources/Geometry    bearing, distance, cross-track distance
      Sources/Guidance    maneuvers, off-route, ETA   (no CoreLocation/CoreBluetooth)
      Sources/Routing     MKDirections wrapper, MKRoute -> Core.Route
      Sources/Transport   binary packet serialization (no CoreBluetooth)
      Tests/              XCTest unit tests
    VisorApp/    iOS app (SwiftUI, CoreLocation, CoreBluetooth central)
    VisorSim/    macOS BLE peripheral simulator

## Tests

    cd Visor && swift test

The logic layers are pure, so no simulator or device is required.

## Stack

Swift, SwiftUI, iOS 17+, MapKit, CoreLocation, CoreBluetooth.
No third-party dependencies.
