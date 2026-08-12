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

## Running the app

    cd VisorApp && open Visor.xcodeproj

Pick an iPhone simulator and run. The app opens on the demo route with a
replayed rider driving it, so it needs no receiver, no map service and no HUD.
The scenario picker at the bottom switches between a clean ride, a missed turn
and a lost signal.

`Visor.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen); both are committed, so the
project opens without installing anything. After editing `project.yml`, or the
`Info.plist` values inside it, regenerate:

    cd VisorApp && xcodegen generate

Bluetooth is not part of this yet, and could not be: the iOS Simulator has no
Bluetooth stack at all. The HUD link is tried on a real iPhone against the
macOS peripheral simulator.

## Seeing it work

Ride a synthetic track through the guidance engine and watch what would be sent
to the HUD, one line per second:

    cd Visor
    swift run visor-replay          # a clean ride
    swift run visor-replay detour   # the rider misses a turn
    swift run visor-replay tunnel   # the signal drops out

Add `--fast` to skip the pause between seconds. No device, no simulator and no
map service is involved.

## Tests

    cd Visor && swift test

The logic layers are pure, so no simulator or device is required.

## Stack

Swift, SwiftUI, iOS 17+, MapKit, CoreLocation, CoreBluetooth.
No third-party dependencies.
