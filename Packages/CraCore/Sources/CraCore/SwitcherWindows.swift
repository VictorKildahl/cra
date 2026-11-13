/// The windows a window switcher shows for Cra (#401).
///
/// DockDoor, AltTab and the like read an app's windows from its accessibility element
/// (`AXWindows`) and keep the ones that look like a window a person works in: a standard
/// window or a dialog, or anything with a close or minimize button. Child windows count too.
/// Cra docks Chromium windows that are no window of their own: the empty Chrome window an
/// embedded page moved out of, and the page and DevTools windows it lays over a Little
/// Window, a Peek or a tab's card. Listed, each was another "Cra window", blank or a slice of
/// the one it sits in, and a parked Peek's page window was a blank one that stayed. Docked
/// windows answer as groups inside their parent and are left out of AXWindows
/// (DockedWindowAccessibility, #391), so only Cra's own windows are listed.
public enum SwitcherWindows {
    public struct Window: Equatable, Sendable {
        /// `AXRole`: AXWindow for a window, AXGroup for a docked one.
        public var role: String?
        public var subrole: String?
        public var hasCloseButton: Bool
        public var hasMinimizeButton: Bool

        public init(role: String? = "AXWindow", subrole: String?, hasCloseButton: Bool, hasMinimizeButton: Bool) {
            self.role = role
            self.subrole = subrole
            self.hasCloseButton = hasCloseButton
            self.hasMinimizeButton = hasMinimizeButton
        }
    }

    /// Whether a switcher lists `window`, an element of the app's `AXWindows`. DockDoor's rule
    /// (WindowUtil): a close or minimize button, or a standard window or dialog subrole.
    public static func lists(_ window: Window) -> Bool {
        guard window.role == "AXWindow" else { return false }
        return window.hasCloseButton || window.hasMinimizeButton
            || window.subrole == "AXStandardWindow" || window.subrole == "AXDialog"
    }
}
