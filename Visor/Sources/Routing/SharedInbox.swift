import Foundation

/// The handover between the share sheet and the app.
///
/// A share extension is a different process with a different sandbox, so it
/// cannot simply tell the app where the rider wants to go. It leaves the link
/// in a container both of them are allowed to open, and the app picks it up the
/// next time it comes to the front.
///
/// What is left there is the shared text exactly as it arrived, not a place. The
/// extension has a few seconds of life and no business making network calls;
/// reading the link is `MapLinkReader`'s job and it already does it, in the app,
/// where a failure can be shown to the rider instead of disappearing with the
/// process.
public struct SharedInbox {
    /// Both the app and the extension have to name this identically in their
    /// entitlements, or the write and the read go to two different places and
    /// nothing arrives — with no error on either side.
    public static let group = "group.com.visor.app.lukas"

    private let store: UserDefaults?

    private static let key = "pendingDestination"

    public init(group: String = SharedInbox.group) {
        self.init(store: UserDefaults(suiteName: group))
    }

    /// For tests, and for anywhere the container is not the real one.
    public init(store: UserDefaults?) {
        self.store = store
    }

    /// Leaves a shared link for the app. Called from the extension.
    ///
    /// Only the last one is kept. Sharing a second place before opening the app
    /// is how someone changes their mind, and a queue of destinations is not a
    /// thing anyone asked for.
    public func hand(over text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store?.set(trimmed, forKey: Self.key)
    }

    /// Takes whatever is waiting, and leaves nothing behind. Called from the app.
    ///
    /// Taking rather than reading, because a share is something that happened
    /// once. Left in place it would be offered again on every return to the
    /// app, including the returns after the rider looked at it and said no.
    public func take() -> String? {
        guard let text = store?.string(forKey: Self.key) else { return nil }
        store?.removeObject(forKey: Self.key)
        return text
    }
}
