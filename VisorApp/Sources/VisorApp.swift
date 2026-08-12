import SwiftUI

@main
struct VisorApp: App {
    var body: some Scene {
        WindowGroup {
            RideView()
                .preferredColorScheme(.dark)
        }
    }
}
