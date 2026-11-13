import CraCore
import Foundation
import Testing

/// Arc's choice per shortcut of who gets its keys, Cra or the page (GitHub #374).
struct ShortcutPriorityTests {
    static let command = KeyChord.Modifiers.command.rawValue

    /// keybindings.json stores Arc's own values, and the pop-up shows Arc's names and lines with Cra for Arc.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func arcsValuesNamesAndWording() {
        #expect(ShortcutPriority.allCases.map(\.rawValue) == ["overrideWebView", "promptAfterConsumedByWebView", "low"])
        #expect(ShortcutPriority.allCases.map(\.title) == ["Prefer Cra", "Use Both", "Prefer Websites"])
        #expect(ShortcutPriority.preferCra.subtitle == "When shortcuts conflict, Cra wins.")
        #expect(ShortcutPriority.useBoth.subtitle
            == "Press this shortcut once to use the website’s shortcut. Press it twice to use Cra’s shortcut.")
        #expect(ShortcutPriority.preferWebsites.subtitle == "When shortcuts conflict, the website wins.")
    }

    /// Prefer Cra takes the key before the page sees it; Prefer Websites never does (the page gets it,
    /// and Cra only what it leaves); Use Both only the repeat of a press the page kept.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func whoTakesTheKeyBeforeThePage() {
        #expect(ShortcutPriority.preferCra.takesBeforePage())
        #expect(ShortcutPriority.preferCra.takesBeforePage(repeatOffered: true))
        #expect(!ShortcutPriority.preferWebsites.takesBeforePage())
        #expect(!ShortcutPriority.preferWebsites.takesBeforePage(repeatOffered: true))
        #expect(!ShortcutPriority.useBoth.takesBeforePage())
        #expect(ShortcutPriority.useBoth.takesBeforePage(repeatOffered: true))
    }

    /// Until the user picks, every action does what it did before the choice: the reserved ones
    /// (new tab, close tab, tab and space switches…) prefer Cra, everything else prefers websites.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"), arguments: [
        ("newTab", ShortcutPriority.preferCra), ("closeTab", .preferCra), ("editURL", .preferCra), ("toggleSidebar", .preferCra),
        ("item1", .preferCra), ("item9", .preferCra), ("space3", .preferCra), ("moveTabToSpace9", .preferCra), ("nextSpace", .preferCra),
        ("find", .preferWebsites), ("reload", .preferWebsites), ("goBack", .preferWebsites), ("pinTab", .preferWebsites),
        ("item10", .preferWebsites), ("someFutureAction", .preferWebsites),
    ])
    func defaultsAreTodaysBehaviour(action: String, priority: ShortcutPriority) {
        #expect(ShortcutPriority.defaultPriority(for: action) == priority)
    }

    /// Copy URL is Cra's first, like Arc's: Google Docs takes ⇧⌘C for its word count.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/194"))
    func copyURLPrefersCra() {
        #expect(ShortcutPriority.defaultPriority(for: "copyURL") == .preferCra)
        #expect(ShortcutPriority.defaultPriority(for: "copyURLMarkdown") == .preferCra)
        #expect(KeyBindingOverrides().priority(for: "copyURL") == .preferCra)
    }

    // MARK: Use Both

    /// The page keeps the first press: Cra offers the shortcut, and the next press is Cra's.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func useBothTakesTheSecondPressThePageKept() {
        var presses = UseBothPresses()
        let r1 = presses.beforePage("find", at: 10)
        #expect(!r1)
        let r2 = presses.pageKept("find", pressedAt: 10, now: 10.5, offerTime: 4.85)
        #expect(r2)
        let r3 = presses.beforePage("find", at: 12)
        #expect(r3)
        // The offer is spent: a third press goes to the page again.
        let r4 = presses.beforePage("find", at: 13)
        #expect(!r4)
    }

    /// The page leaves the press alone: it comes back, Cra runs it, and nothing is offered.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func useBothPressThePageLeftIsNotOffered() {
        var presses = UseBothPresses()
        let r5 = presses.beforePage("find", at: 10)
        #expect(!r5)
        presses.pageLeft("find")
        let r6 = presses.pageKept("find", pressedAt: 10, now: 10.5, offerTime: 4.85)
        #expect(!r6)
        let r7 = presses.beforePage("find", at: 11)
        #expect(!r7)
    }

    /// A slow page hands the press back after Cra offered it: Cra ran it then, so the offer goes.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func useBothLateAnswerDropsTheOffer() {
        var presses = UseBothPresses()
        _ = presses.beforePage("find", at: 10)
        let r8 = presses.pageKept("find", pressedAt: 10, now: 10.5, offerTime: 4.85)
        #expect(r8)
        presses.pageLeft("find")
        let r9 = presses.beforePage("find", at: 11)
        #expect(!r9)
    }

    /// The offer ends with the toast, is for that shortcut only, and a held key's repeats aren't presses.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func useBothOfferIsForThatShortcutWhileItStands() {
        var presses = UseBothPresses()
        _ = presses.beforePage("find", at: 10)
        _ = presses.pageKept("find", pressedAt: 10, now: 10.5, offerTime: 5)
        let r10 = presses.beforePage("find", at: 10.6, isRepeat: true)
        #expect(!r10)
        let r11 = presses.beforePage("reload", at: 11)
        #expect(!r11)
        let r12 = presses.beforePage("find", at: 15.5)
        #expect(r12)

        var late = UseBothPresses()
        _ = late.beforePage("find", at: 10)
        _ = late.pageKept("find", pressedAt: 10, now: 10.5, offerTime: 5)
        let r13 = late.beforePage("find", at: 15.6)
        #expect(!r13)
    }

    /// Only the check for the press that's waiting counts: an earlier press's check finds a newer one waiting.
    @Test func useBothCheckIsForItsOwnPress() {
        var presses = UseBothPresses()
        _ = presses.beforePage("find", at: 10)
        _ = presses.beforePage("find", at: 10.2)
        let r14 = presses.pageKept("find", pressedAt: 10, now: 10.5, offerTime: 4.85)
        #expect(!r14)
        let r15 = presses.pageKept("find", pressedAt: 10.2, now: 10.7, offerTime: 4.85)
        #expect(r15)
    }

    // MARK: keybindings.json

    static let w = [KeyChord(key: "w", modifiers: command)]
    static let f = [KeyChord(key: "f", modifiers: command)]

    /// Picking a priority keeps the action's shortcuts in the file to carry it; picking the default
    /// again over default shortcuts drops the action, so its Reset turns off.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func pickingAndUnpickingAPriority() {
        var o = KeyBindingOverrides()
        o.setPriority(.preferWebsites, for: "closeTab", current: Self.w, defaults: Self.w)
        #expect(o.priority(for: "closeTab") == .preferWebsites)
        #expect(o.shortcuts["closeTab"] == Self.w)
        o.setPriority(.preferCra, for: "closeTab", current: Self.w, defaults: Self.w)
        #expect(o == KeyBindingOverrides())

        // A shortcut the user recorded stays when the priority goes back to the default.
        let mine = [KeyChord(key: "k", modifiers: Self.command)]
        o.setPriority(.useBoth, for: "find", current: mine, defaults: Self.f)
        o.setPriority(.preferWebsites, for: "find", current: mine, defaults: Self.f)
        #expect(o.shortcuts["find"] == mine && o.priorities["find"] == nil)

        // No shortcut, no keys to give: nothing to store.
        o.setPriority(.preferCra, for: "share", current: [], defaults: [])
        #expect(o.priorities["share"] == nil && o.shortcuts["share"] == nil)
    }

    /// The priority rides on every chord of its action, and the file a Cra without the choice reads
    /// (`[String: [KeyChord]]`) still loads the same shortcuts from it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func priorityRidesOnTheChords() throws {
        let tab = [KeyChord(key: KeyChord.tab, modifiers: KeyChord.Modifiers.control.rawValue),
                   KeyChord(key: "]", modifiers: Self.command | KeyChord.Modifiers.shift.rawValue)]
        let o = KeyBindingOverrides(shortcuts: ["nextTab": tab, "newTab": [KeyChord(key: "t", modifiers: Self.command)]],
                                    priorities: ["nextTab": .useBoth])
        let data = try JSONEncoder().encode(o)
        let file = try #require(JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]])
        #expect(file["nextTab"]?.map { $0["priority"] as? String } == ["promptAfterConsumedByWebView", "promptAfterConsumedByWebView"])
        #expect(file["newTab"]?.first?["priority"] == nil)
        #expect(try JSONDecoder().decode([String: [KeyChord]].self, from: data) == o.shortcuts)
        #expect(try JSONDecoder().decode(KeyBindingOverrides.self, from: data) == o)
    }
}
