import CraCore
import Testing

/// The developer bar's DevTools commands (GitHub #88) on the engine: Network opens on Network, Inspect arms the
/// picker the first time, and DevTools take the keys as Chrome's do.
struct DevToolsFrontendCallsTests {

    /// Network on closed DevTools: Chrome has no Network panel to open them on, so the frontend is switched once
    /// it is up, and takes the keys then.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/776")) func networkOnClosedDevToolsSwitchesOnceTheFrontendIsUp() {
        var calls = DevToolsFrontendCalls()
        let (engine, now) = calls.command("network", shows: true, frontendUp: false)
        #expect(engine == "network")
        #expect(now == .init())
        #expect(calls.frontendShowsPanel(first: true) == .init(script: "InspectorFrontendAPI.showPanel('network')", takesKeys: true))
        #expect(calls.frontendShowsPanel(first: false) == .init(), "it runs once")
    }

    /// Network or Console on open DevTools: the frontend switches at once, and takes the keys.
    @Test func panelOnOpenDevToolsSwitchesAtOnce() {
        var calls = DevToolsFrontendCalls()
        let (engine, now) = calls.command("console", shows: true, frontendUp: true)
        #expect(engine == "console")
        #expect(now == .init(script: "InspectorFrontendAPI.showPanel('console')", takesKeys: true))
        #expect(calls.waiting == nil)
    }

    /// Inspect on closed DevTools: they open on Elements and the picker is armed once the frontend is up, without
    /// Chrome's Inspect, which left it off.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/776")) func inspectOnClosedDevToolsArmsThePickerOnceUp() {
        var calls = DevToolsFrontendCalls()
        let (engine, now) = calls.command("inspect", shows: true, frontendUp: false)
        #expect(engine == "elements")
        #expect(now == .init())
        #expect(calls.frontendShowsPanel(first: true) == .init(script: DevToolsFrontendCalls.armPicker, takesKeys: true))
    }

    /// Inspect on DevTools that are up is Chrome's: it arms the picker, or turns it off when it is on.
    @Test func inspectOnOpenDevToolsIsChromes() {
        var calls = DevToolsFrontendCalls()
        let (engine, now) = calls.command("inspect", shows: true, frontendUp: true)
        #expect(engine == "inspect")
        #expect(now == .init(takesKeys: true))
    }

    /// The picker script leaves a picker that is on as it is: it reads the action's state before it runs it.
    @Test func armingThePickerNeverTurnsItOff() {
        #expect(DevToolsFrontendCalls.armPicker.contains("if(!a.toggled())a.execute()"))
    }

    /// ⌥⌘I: DevTools open as they were and take the keys once up; closing asks nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/776")) func toggleOpensWithTheKeysAndClosesWithNothing() {
        var calls = DevToolsFrontendCalls()
        #expect(calls.command(nil, shows: true, frontendUp: false) == (nil, .init()))
        #expect(calls.frontendShowsPanel(first: true) == .init(takesKeys: true))
        #expect(calls.frontendShowsPanel(first: false) == .init(), "a later switch, from the frontend's tabs, keeps the keys where they are")
        let (engine, now) = calls.command(nil, shows: false, frontendUp: true)
        #expect(engine == nil && now == .init())
    }

    /// A press that closes DevTools drops the script still waiting for them; a later one replaces it.
    @Test func aLaterCommandReplacesTheWaitingScript() {
        var calls = DevToolsFrontendCalls()
        _ = calls.command("network", shows: true, frontendUp: false)
        _ = calls.command("console", shows: true, frontendUp: false)
        #expect(calls.waiting == "InspectorFrontendAPI.showPanel('console')")
        _ = calls.command(nil, shows: false, frontendUp: false)
        #expect(calls.waiting == nil)
    }

    /// An action with no panel to show passes to the engine as it is.
    @Test func otherActionsPassThrough() {
        var calls = DevToolsFrontendCalls()
        let (engine, now) = calls.command("sources", shows: true, frontendUp: true)
        #expect(engine == "sources" && now == .init(takesKeys: true))
    }
}
