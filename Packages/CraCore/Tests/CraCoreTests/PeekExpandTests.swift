import CraCore
import Foundation
import Testing

/// ⌘-click on a Peek's Expand button (GitHub #380).
struct PeekExpandTests {
    static func target(command: Bool, source: Bool = true, on: Bool) -> PeekExpand {
        var s = AppSettings()
        s.peekExpandInSourceTab = on
        return PeekExpand.target(commandClick: command, hasSourceTab: source, settings: s)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/380"))
    func commandClickLoadsInTheSourceTabOnlyWhenTurnedOn() {
        #expect(Self.target(command: true, on: true) == .sourceTab)
        #expect(Self.target(command: true, on: false) == .newTab, "off: Arc's Expand")
        #expect(Self.target(command: false, on: true) == .newTab, "a plain click still makes a tab")
        #expect(Self.target(command: true, source: false, on: true) == .newTab, "no tab to load in")
    }

    /// Off unless turned on, for new settings and ones saved before it existed; kept once on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/380"))
    func offByDefault() throws {
        #expect(!AppSettings().peekExpandInSourceTab)
        let decoder = ModelFixtureTests.decoder
        #expect(try !decoder.decode(AppSettings.self, from: Data("{}".utf8)).peekExpandInSourceTab)
        var on = AppSettings()
        on.peekExpandInSourceTab = true
        let saved = try ModelFixtureTests.encoder.encode(on)
        #expect(try decoder.decode(AppSettings.self, from: saved).peekExpandInSourceTab)
    }
}
