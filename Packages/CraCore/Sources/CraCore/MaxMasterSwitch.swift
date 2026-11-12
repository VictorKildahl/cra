import Foundation

/// The button beside "Enable Max" in Arc's Max pane. Arc keeps no switch of its own for it: the title follows how many
/// of the features are on ("Turn Off Max" with all of them, "Turn On All" with some, "Turn On Max" with none) and a
/// press sets every feature the same way.
public enum MaxMasterSwitch {
    public static func title(_ features: [Bool]) -> String {
        if !features.isEmpty, features.allSatisfy({ $0 }) { return "Turn Off Max" }
        return features.contains(true) ? "Turn On All" : "Turn On Max"
    }

    /// What every feature becomes when the button is pressed.
    public static func pressTurnsOn(_ features: [Bool]) -> Bool {
        features.isEmpty || !features.allSatisfy { $0 }
    }

    /// Arc fills the button in blue except when it turns Max off.
    public static func isEmphasised(_ features: [Bool]) -> Bool { pressTurnsOn(features) }
}
