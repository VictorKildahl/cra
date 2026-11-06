import CraCore
import Foundation
import Testing

/// Each profile's website languages under Settings ▸ Profiles (#209).
struct BrowserLanguagesTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/209")) func readsThePrefAsChromiumListsIt() {
        #expect(BrowserLanguages.codes("da,en-GB,en-US,en") == ["da", "en-GB", "en-US", "en"])
        // CraCEFRuntime.preference hands back JSON.
        #expect(BrowserLanguages.codes("\"zh-CN,zh,en\"") == ["zh-CN", "zh", "en"])
        #expect(BrowserLanguages.codes(" en-US , en ") == ["en-US", "en"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/209")) func dropsWhatIsNotALanguageList() {
        #expect(BrowserLanguages.codes("") == [])
        #expect(BrowserLanguages.codes("\"unterminated") == [])
        #expect(BrowserLanguages.codes("[\"en\"]") == [])
        #expect(BrowserLanguages.codes("en,,de;q=0.9,en") == ["en"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/209")) func readsAProfilesPreferencesFile() {
        let file = #"{"intl":{"accept_languages":"da-DK,da,en-US,en","selected_languages":"da-DK,da,en-US,en"},"profile":{}}"#
        #expect(BrowserLanguages.codes(preferencesFile: Data(file.utf8)) == ["da-DK", "da", "en-US", "en"])
        #expect(BrowserLanguages.codes(preferencesFile: Data(#"{"profile":{}}"#.utf8)) == nil)
        #expect(BrowserLanguages.codes(preferencesFile: Data("not json".utf8)) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/209")) func namesLanguagesInEnglish() {
        #expect(BrowserLanguages.name("da") == "Danish")
        #expect(BrowserLanguages.name("en-GB") == "English (United Kingdom)")
        #expect(BrowserLanguages.summary(["da", "en-US", "en"]) == "Danish, English (United States), English")
    }
}
