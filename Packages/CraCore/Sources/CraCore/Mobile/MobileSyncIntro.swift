import Foundation

/// Cra's version of Arc Search 1.49's "Sync with Arc Desktop" (Victor's recording, 3:30): the
/// Spaces sheet before anything has synced, and the "Every tab, anywhere." card over the tab
/// row's Spaces button. Arc signs in to an Arc account; Cra has none, its Mac sends its Spaces
/// through iCloud, so the two buttons lead to how to turn that on, or where to get Cra.
public enum MobileSyncIntro {
    public enum Page: Equatable { case intro, haveMac, noMac }

    public static let title = "Sync with Cra for Mac"
    public static let body = "Search and browse your Cra Spaces on the go."
    public static let haveMacButton = "I have Cra on my Mac"
    public static let noMacButton = "I don\u{2019}t have Cra yet"
    public static let goBack = "Go back"

    public static let haveMacTitle = "Turn on Sync on your Mac"
    /// iCloud signed in on the phone or not.
    public static func haveMacBody(iCloud: Bool) -> String {
        let mac = "In Cra on your Mac, open Settings \u{25B8} General and turn on Sync. Your Spaces come over through iCloud."
        return iCloud ? mac : mac + " Sign in to iCloud on this iPhone too."
    }

    public static let noMacTitle = "Get Cra on your computer first"
    public static let noMacBody = "Visit crabrowser.app to download Cra for Mac."

    public static let cardTitle = "Every tab, anywhere."
    public static let cardDetail = "Sync with Cra for Mac"

    /// The card shows over the tab row until it is closed, and never once the Mac's Spaces are here.
    public static func showsCard(hasSpaces: Bool, dismissed: Bool) -> Bool { !hasSpaces && !dismissed }
}
