import CraCore
import Foundation
import Testing

/// Settings ▸ Profiles ▸ "Check spelling while typing" (GitHub #715): Chromium's per-profile
/// browser.enable_spellchecking, as chrome://settings/languages ▸ Spell check sets it.
struct SpellCheckTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/715"))
    func onUnlessTheProfileTurnedItOff() {
        #expect(SpellCheck.pref == "browser.enable_spellchecking")
        #expect(SpellCheck.isOn(prefJSON: "true"))
        #expect(!SpellCheck.isOn(prefJSON: "false"))
        // Chromium's default, and a profile that hasn't loaded and never saved it: on.
        #expect(SpellCheck.isOn(prefJSON: nil))
        #expect(SpellCheck.isOn(prefJSON: "nonsense"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/715"))
    func aProfileNotLoadedIsReadFromItsPreferencesFile() {
        let off = Data(#"{"browser":{"enable_spellchecking":false,"has_seen_welcome_page":true}}"#.utf8)
        let other = Data(#"{"browser":{"has_seen_welcome_page":true}}"#.utf8)
        #expect(!SpellCheck.isOn(preferencesFile: off))
        #expect(SpellCheck.isOn(preferencesFile: other))
        #expect(SpellCheck.isOn(preferencesFile: Data("{".utf8)))
        #expect(SpellCheck.json(on: false) == "false" && SpellCheck.json(on: true) == "true")
    }
}
