import Foundation

/// What a page's DevTools frontend is asked to do for the developer bar's commands (⌥⌘J, Network, ⌥⌘C, ⌥⌘I; the app's
/// DevToolsToggle decides open or close), and when DevTools take the keys.
///
/// Chrome's own DevToolsToggleAction picks a panel only for DevTools it is creating, and has no Network panel; Inspect
/// pressed while DevTools were closed opened them with the element picker off (engine 159.0.8154.45). So panels are
/// switched, and the picker is armed, by the frontend's own API (as the CEF bridge's runDevToolsAction did), once the
/// frontend is up: once it reports the panel it shows. As Chrome does for DevTools it shows, they take the keys when
/// they open and when a command keeps them shown.
public struct DevToolsFrontendCalls: Equatable, Sendable {
    /// What happens in the frontend now.
    public struct Step: Equatable, Sendable {
        /// Run in the frontend (CraBrowser.executeJavaScript(_:inDevTools:)).
        public var script: String?
        /// The frontend becomes its window's first responder.
        public var takesKeys: Bool

        public init(script: String? = nil, takesKeys: Bool = false) {
            self.script = script
            self.takesKeys = takesKeys
        }
    }

    /// The panels a command shows.
    public static let panels: Set<String> = ["console", "network", "elements"]

    /// Turns the element picker on, and leaves it on when it already is; the frontend registers the action a moment
    /// after its first panel, so it waits for it (5 s at most).
    public static let armPicker = "(function(){var n=0;function arm(){import('./ui/legacy/legacy.js').then(function(UI){"
        + "var r=UI.ActionRegistry.ActionRegistry.instance();if(!r.hasAction('elements.toggle-element-search')){"
        + "if(++n<50)setTimeout(arm,100);return;}var a=r.getAction('elements.toggle-element-search');"
        + "if(!a.toggled())a.execute();});}arm();})();"

    /// The script waiting for the frontend to come up.
    public private(set) var waiting: String?

    public init() {}

    /// A command. `action` is what DevToolsToggle asks of the frontend (nil: nothing), `shows` whether DevTools are
    /// shown after it (opened, or open and kept), `frontendUp` whether they were open before it. Returns the action
    /// DevTools are opened or shown with (CraBrowser.devToolsAction) and what happens now; a script for DevTools
    /// still to open waits for frontendShowsPanel.
    public mutating func command(_ action: String?, shows: Bool, frontendUp: Bool) -> (engineAction: String?, now: Step) {
        let engineAction: String?
        let script: String?
        switch action {
        case "inspect"?:
            // Chrome arms the picker of a frontend that is up, and turns it off when it is on, as ⌥⌘C does in Chrome.
            engineAction = frontendUp ? "inspect" : "elements"
            script = frontendUp ? nil : Self.armPicker
        case let panel? where Self.panels.contains(panel):
            engineAction = panel
            script = "InspectorFrontendAPI.showPanel('\(panel)')"
        default:
            engineAction = action
            script = nil
        }
        guard frontendUp else {
            waiting = script
            return (engineAction, Step())
        }
        waiting = nil
        return (engineAction, Step(script: script, takesKeys: shows))
    }

    /// The frontend of DevTools that are open reported the panel it shows; `first` when it is its first report since
    /// they opened.
    public mutating func frontendShowsPanel(first: Bool) -> Step {
        defer { waiting = nil }
        return Step(script: waiting, takesKeys: first)
    }
}
