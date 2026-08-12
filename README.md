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

In the simulator the link reports "No Bluetooth on this device", which is the
truth: the iOS Simulator has no Bluetooth stack at all. Everything else works
there; the link can only be tried on a real iPhone.

## Trying the whole thing end to end

Needs a real iPhone, because of the above.

1. On the Mac, run `VisorSim`. Wait for "Advertising, waiting for the phone".
2. In `VisorApp`, select the Visor target, and under Signing & Capabilities
   choose your team and change the bundle identifier to one nobody else has
   taken.
3. Plug the iPhone in, pick it in the device menu, and run.
4. The pill under the search bar should go to "Connected", with a packet count
   climbing once a second. The Mac window shows the same numbers, decoded from
   the bytes it received.

Guidance keeps running with the screen off while Live GPS is the source: the app
holds location updates in the background, which is what keeps the 1 Hz writes
going. A replayed ride has no location updates to hold it awake, so it stops
when the app does.

## Running the HUD simulator

    cd VisorSim && open VisorSim.xcodeproj

Run it on the Mac. It advertises itself as a Visor heads-up display over
Bluetooth and shows whatever gets written to it, decoded from the bytes and
nothing else. The **Demo feed** switch drives the display from a replayed ride
with no Bluetooth in between, which is how a display fault is told apart from a
link fault.

Also generated with XcodeGen from `project.yml`.

## Seeing it work

Ride a synthetic track through the guidance engine and watch what would be sent
to the HUD, one line per second:

    cd Visor
    swift run visor-replay          # a clean ride
    swift run visor-replay detour   # the rider misses a turn
    swift run visor-replay tunnel   # the signal drops out

Add `--fast` to skip the pause between seconds, and `--bytes` to print the
packet that would be written to the HUD under each line.

To ride a real route rather than the hand-built one, name a destination. This is
the only way to find out what a map service's geometry does to the maneuver
classifier before a rider does:

    swift run visor-replay --to Bostanci
    swift run visor-replay --to Bostanci --steps

`--steps` prints one row per junction: the bearings either side of it, the angle
between them, the maneuver worked out from that angle, and the sentence the map
service attached to the same junction. If those two ever stop agreeing,
something has come apart.

## Tests

    cd Visor && swift test

The logic layers are pure, so no simulator or device is required.

## Stack

Swift, SwiftUI, iOS 17+, MapKit, CoreLocation, CoreBluetooth.
No third-party dependencies.
