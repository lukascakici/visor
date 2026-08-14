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
    Firmware/    ESP32-S3 firmware — the same decisions in C

## What goes over the link

Two packets, on two characteristics of one custom service, both written without
a response because there is nothing useful to say back.

**Guidance**, once a second, ten fixed bytes and a street name: the maneuver
ahead, how far to it, how far and how long to the destination, speed, and three
flags for off-route, rerouting and weak GPS. Every number saturates rather than
wrapping, because 65.5 km is obviously the top of a scale and 14 km is a
plausible lie.

**The road**, alongside it: the shape of the route around the rider as up to a
few dozen points, four bytes each, in decimeters right of and ahead of them. The
rider is always the origin and up is always the way they are heading, so the
device needs no map, no projection and no idea where north is.

Coordinates rather than pixels, and that one decision is why any of this fits: a
240x240 screen is 115 kB a frame, and the same road as forty points is 164
bytes. It also means the packet says nothing about the display it is going to.

## Firmware

`Firmware/` is the ESP32-S3 side, arranged the way the Swift is: the parts with
no hardware in them are kept apart from the parts with hardware in them, so they
can be run without a board.

    cd Firmware/test && ./run.sh

Decoding, the frame, the crossing between packets and the whole rasteriser are
plain C over plain memory, so this needs no ESP-IDF and no toolchain. It leaves
`hud.ppm` next to itself, which is what the display would actually look like.

There is no font anywhere: numbers are seven segments and arrows are polygons.
A font is the one asset that would have to be generated, embedded and kept in
step with a character set, and what a rider reads at speed is a shape, an arrow
and a number. The cost is that the street name is decoded but not shown.

## Running the app

    cd VisorApp && open Visor.xcodeproj

Pick an iPhone simulator and run. The app opens on the receiver with no route,
because a navigation app should start where the rider is: search for somewhere
to go and it plans from the position the receiver reported, never from a
position snapped onto a route that is not yet the rider's.

**Demo** loads the hand-built Kadikoy route and a scripted rider to drive it,
which needs no receiver, no map service and no HUD. The scenario picker at the
bottom then switches between a clean ride, a missed turn and a lost signal.

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

Add `--fast` to skip the pause between seconds, and `--bytes` to print both
packets that would be written under each line.

`--map` draws the road the way the HUD draws it, in the same fixed frame: the
rider always in the same place, up the screen the way they are heading. It is
the only way to see what the path channel is sending without a Mac, a phone and
a Bluetooth link all working at once.

    swift run visor-replay --fast --map
    swift run visor-replay --fast --bytes --mtu 23

`--mtu` sets what one write carries; it defaults to what iOS actually
negotiates. Putting it back on the floor of what Bluetooth guarantees is where
the street name starts being cut and the road starts losing points, and both
should degrade rather than break.

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
    cd Firmware/test && ./run.sh

The logic layers are pure on both sides, so neither needs a simulator, a device
or a board.

## Stack

Swift, SwiftUI, iOS 17+, MapKit, CoreLocation, CoreBluetooth, and C99 on the
device. No third-party dependencies anywhere, on either side.
