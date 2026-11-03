/// The question Cra's permission sheet asks for a page's request. `kinds` is CraCEF's bit set:
/// 1 camera, 2 microphone, 4 location, 8 notifications, 16 a type CraCEF can't name, and from
/// 1 << 5 Chrome's other types. Notifications ask like the others (Arc asks too; Messenger and
/// the like need them), up to 0.1.27 they were denied without a sheet. Every type has Chrome's
/// own words, so the sheet says what Allow gives (#137: Calendar's sheet said only "a browser
/// permission").
public enum PermissionPrompt {
    /// Chrome's wording (its *_PERMISSION_FRAGMENT strings), in the order the sheet lists them.
    public static let requests: [(kind: UInt, wants: String)] = [
        (8, "show notifications"),
        (1 << 5, "see text and images copied to the clipboard"),
        (1 << 6, "manage windows on all your displays"),
        (1 << 7, "access other devices on your local network"),
        (1 << 8, "access other apps and services on this device"),
        (1 << 9, "use its cookies and site data on this page"),
        (1 << 10, "let the sites it embeds use their cookies and site data"),
        (1 << 11, "use the fonts on your computer"),
        (1 << 12, "know when you're actively using this device"),
        (1 << 13, "control and reprogram your MIDI devices"),
        (1 << 14, "download multiple files"),
        (1 << 15, "override some keys on your keyboard, like Esc"),
        (1 << 16, "lock and use your mouse"),
        (1 << 17, "play protected content"),
        (1 << 18, "open a kind of link, like email or calendar links"),
        (1 << 19, "create a 3D map of your surroundings and track camera position"),
        (1 << 20, "use virtual reality devices and data"),
        (1 << 21, "track your hands"),
        (1 << 22, "use your motion sensors"),
        (1 << 23, "store files on this device"),
        (1 << 24, "use your accounts to log in to websites"),
        (1 << 25, "scroll and zoom the contents of your shared tab"),
        (1 << 26, "install web apps"),
        (1 << 27, "edit files on this device"),
        (1 << 28, "sign you in automatically"),
    ]

    public static func message(origin: String, kinds: UInt) -> String {
        var devices: [String] = []
        if kinds & 1 != 0 { devices.append("camera") }
        if kinds & 2 != 0 { devices.append("microphone") }
        if kinds & 4 != 0 { devices.append("location") }
        var wants = devices.isEmpty ? [] : ["use your \(list(devices))"]
        wants += requests.filter { kinds & $0.kind != 0 }.map(\.wants)
        if kinds & 16 != 0, !wants.isEmpty { wants.append("use another browser permission") }
        return wants.isEmpty ? "\(origin) is asking for a browser permission"
                             : "\(origin) wants to \(list(wants))"
    }

    /// "a", "a and b", "a, b and c".
    private static func list(_ items: [String]) -> String {
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}
