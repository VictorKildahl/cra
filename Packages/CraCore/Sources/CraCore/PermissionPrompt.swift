/// The question Cra's permission sheet asks for a page's request. `kinds` is CraCEF's bit set:
/// 1 camera, 2 microphone, 4 location, 8 notifications, 16 anything else. Notifications ask
/// like the others (Arc asks too; Messenger and the like need them), up to 0.1.27 they were
/// denied without a sheet.
public enum PermissionPrompt {
    public static func message(origin: String, kinds: UInt) -> String {
        var devices: [String] = []
        if kinds & 1 != 0 { devices.append("camera") }
        if kinds & 2 != 0 { devices.append("microphone") }
        if kinds & 4 != 0 { devices.append("location") }
        var wants = devices.isEmpty ? [] : ["use your \(devices.joined(separator: " and "))"]
        if kinds & 8 != 0 { wants.append("show notifications") }
        return wants.isEmpty ? "\(origin) is asking for a browser permission"
                             : "\(origin) wants to \(wants.joined(separator: " and "))"
    }
}
