import AppKit

/// Restrict the native-window fallback to Chromium bubbles in the requesting page.
/// This is still a native ownership check, not a protocol target-to-window mapping.
enum ExtensionPopupCandidate {
    @MainActor
    static func matches(_ window: NSWindow, owner: NSWindow?, sourceHost: NSWindow?,
                        isPageHost: (NSWindow) -> Bool) -> Bool {
        guard let owner, owner.isVisible, window.isVisible, window.frame.width > 1,
              !window.styleMask.contains(.titled), !(window is NSPanel),
              NSStringFromClass(type(of: window)) == "NativeWidgetMacNSWindow",
              let host = window.parent, isPageHost(host), host.parent === owner else { return false }
        return sourceHost == nil || host === sourceHost
    }
}
