import CraCore
import Foundation
import Testing

/// App Settings ▸ Apple Intelligence on the iPhone: Browse for Me and Summarize can be switched off where
/// Apple Intelligence can't be used (#792, not in Arc Search, whose Browse for Me ran on Arc's servers).
struct MobileAISwitchTests {
    /// Switched off, the phone is treated as one that can't run them: nothing offers them, nothing asks to turn
    /// Apple Intelligence on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/792")) func switchedOffNothingOffersThem() {
        for device in [MobileAIState.ready, .turnedOff, .preparing, .unsupported] {
            let shown = device.shown(userWantsThem: false)
            #expect(shown == .unsupported)
            #expect(!shown.offersFeatures)
            #expect(!shown.canRun)
            #expect(MobileAI.prompt(for: shown) == nil)
        }
    }

    /// On (the default), the phone's own state decides, as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/792")) func switchedOnThePhoneDecides() {
        for device in [MobileAIState.ready, .turnedOff, .preparing, .unsupported] {
            #expect(device.shown(userWantsThem: true) == device)
        }
    }

    /// The switch shows only on a phone that can run Apple Intelligence; elsewhere there is nothing to switch.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/792")) func theSwitchShowsWhereTheFeaturesCould() {
        #expect(MobileAIState.ready.offersSwitch)
        #expect(MobileAIState.turnedOff.offersSwitch)
        #expect(MobileAIState.preparing.offersSwitch)
        #expect(!MobileAIState.unsupported.offersSwitch)
    }

    /// On by default, and a settings.json from an older build (no key) loads with it on; off is kept.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/792")) func onByDefaultAndKept() throws {
        #expect(MobileSettings().appleIntelligence)
        let old = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"searchEngine":"google","homeDots":true}"#.utf8))
        #expect(old.appleIntelligence)
        var off = MobileSettings()
        off.appleIntelligence = false
        let again = try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(off))
        #expect(!again.appleIntelligence)
    }
}
