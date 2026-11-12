/// When Cra's permission sheet asks, and what cra.log says about each request (#286).
///
/// Chrome asks in the tab that wants something, and only while that tab is in front: a request
/// from a tab behind waits there until the user switches to it (PermissionRequestManager). Every
/// Cra page is the one tab of its own Chrome window, so Chromium sees each page as the tab in
/// front and hands Cra a hidden page's request at once. Cra's sheet covers the whole window, so
/// a page behind (a call reconnecting after the Mac woke) asked over the tab the user was reading,
/// with nothing saying which tab it was. Cra holds such a request until its tab is shown, as
/// Chrome does, and asks one at a time.
public enum PermissionAsk {
    /// Whether a request waits rather than asking now: its tab isn't on screen, or another
    /// request's sheet is still up.
    public static func waits(tabShown: Bool, sheetUp: Bool) -> Bool { !tabShown || sheetUp }

    /// Whether the request asking now steps aside: its tab went behind. Cra asks in Arc's popover
    /// under the URL field since #371 (the sheet blocked the whole window), so the user can
    /// switch tabs while it is up; the popover goes unanswered and its request waits first in
    /// line until its tab is shown again, as Chrome's bubble does.
    public static func stepsAside(tabShown: Bool) -> Bool { !tabShown }

    /// What macOS says about Cra using the camera or microphone (AVCaptureDevice's
    /// authorization status). A page can only reach the device past `.notAsked` after macOS's
    /// own question, which Chrome's media code puts up when the page opens the device.
    public enum DeviceAccess: String, Sendable {
        case allowed
        case denied
        case restricted
        case notAsked = "not asked yet"
    }

    /// What became of a request.
    public enum Outcome: String, Sendable {
        case allowed = "allowed"
        case blocked = "blocked"
        /// Chromium dropped it: the page navigated or closed, or a newer request replaced it.
        case withdrawn = "withdrawn by the page"
        /// Its tab closed, or slept, before it was shown.
        case tabGone = "dropped, its tab closed"
    }

    /// "camera", "microphone", "camera and microphone", "location", or the kinds' bits.
    public static func kindNames(_ kinds: UInt) -> String {
        var names: [String] = []
        if kinds & 1 != 0 { names.append("camera") }
        if kinds & 2 != 0 { names.append("microphone") }
        if kinds & 4 != 0 { names.append("location") }
        if kinds & 8 != 0 { names.append("notifications") }
        let rest = kinds & ~UInt(15)
        if rest != 0 { names.append("permission bits 0x\(String(rest, radix: 16))") }
        return names.isEmpty ? "a permission" : names.joined(separator: " and ")
    }

    /// The request as it arrives:
    /// `permission: meet.google.com wants microphone (tab 1a2b3c4d, behind; macOS microphone: allowed) → waits for its tab`.
    public static func requestLine(origin: String, kinds: UInt, tab: String?, shown: Bool, waits: Bool,
                                   camera: DeviceAccess?, microphone: DeviceAccess?) -> String {
        var context = [tab.map { "tab \($0), \(shown ? "in front" : "behind")" } ?? "no tab"]
        var devices: [String] = []
        if kinds & 1 != 0, let camera { devices.append("camera: \(camera.rawValue)") }
        if kinds & 2 != 0, let microphone { devices.append("microphone: \(microphone.rawValue)") }
        if !devices.isEmpty { context.append("macOS " + devices.joined(separator: ", ")) }
        let next = waits ? (shown ? "waits for the sheet before it" : "waits for its tab") : "asks"
        return "permission: \(host(origin)) wants \(kindNames(kinds)) (\(context.joined(separator: "; "))) → \(next)"
    }

    /// A waiting request whose tab came to the front: `permission: meet.google.com wants microphone → asks now`.
    public static func shownLine(origin: String, kinds: UInt) -> String {
        "permission: \(host(origin)) wants \(kindNames(kinds)) → asks now"
    }

    /// The asking request's tab went behind: `permission: meet.google.com wants microphone → waits for its tab again`.
    public static func asideLine(origin: String, kinds: UInt) -> String {
        "permission: \(host(origin)) wants \(kindNames(kinds)) → waits for its tab again"
    }

    /// `permission: meet.google.com microphone: blocked`.
    public static func outcomeLine(origin: String, kinds: UInt, outcome: Outcome) -> String {
        "permission: \(host(origin)) \(kindNames(kinds)): \(outcome.rawValue)"
    }

    /// The origin's host, as the rest of cra.log names sites; the origin when it has none.
    static func host(_ origin: String) -> String {
        guard let scheme = origin.range(of: "://") else { return origin }
        let rest = origin[scheme.upperBound...]
        let host = rest.prefix { $0 != "/" && $0 != ":" }
        return host.isEmpty ? origin : String(host)
    }
}

/// Chromium's audio service across a sleep (#286). Its hang monitor ends the service when the
/// audio thread misses three pings in a row, a minute apart (media/audio/
/// audio_thread_hang_monitor.cc); it skips the check when the Mac slept between two pings, so
/// what it ends is a real stall during a wake, often a dark wake with nobody at the Mac. Chromium
/// starts the service again on the next sound or microphone. cra.log says which it was.
public enum AudioServiceWake {
    public static func sleepLine(pid: Int32?) -> String {
        "the Mac sleeps; audio service: " + (pid.map { "pid \($0)" } ?? "not running")
    }

    public static func line(beforeSleep: Int32?, now: Int32?) -> String {
        switch (beforeSleep, now) {
        case let (b?, n?) where b == n: return "audio service: alive across the sleep (pid \(n))"
        case let (b?, n?): return "audio service: restarted while the Mac slept (pid \(b) → \(n))"
        case let (b?, nil): return "audio service: ended while the Mac slept (pid \(b)); Chromium starts it on the next sound"
        case let (nil, n?): return "audio service: started while the Mac slept (pid \(n))"
        case (nil, nil): return "audio service: not running"
        }
    }
}
