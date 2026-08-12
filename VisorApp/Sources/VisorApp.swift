import SwiftUI

@main
struct VisorApp: App {
    @State private var session: RideSession

    init() {
        let session = RideSession()
        // The radio comes up with the app, not with the ride. iOS can relaunch
        // this app in the background purely to hand a Bluetooth connection
        // back, and there is nowhere later to catch that.
        session.link.start()
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            RideView(session: session)
                .preferredColorScheme(.dark)
        }
    }
}
