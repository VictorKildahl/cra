import CraCore
import Testing

/// Archive ▸ View History (⌘Y) is Chromium's History page for the space's profile, as in Arc (#590).
/// Tests/Scenarios/view-history.scenario checks that the key binding opens it.
struct HistoryPageTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/590")) func isChromiumsHistoryNotTheArchive() {
        #expect(HistoryPage.url == "chrome://history")
        // The archive has its own row, View Archive…; typing "archive" finds that one.
        #expect(!HistoryPage.triggers.contains("archive"))
        #expect(!HistoryPage.triggers.contains("closed tabs"))
        #expect(HistoryPage.triggers.contains("history"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/590")) func keepsTheIDKeyBindingsSaved() {
        // keybindings.json stores overrides by id; renaming it would drop a shortcut someone set.
        #expect(HistoryPage.action == "viewArchive")
        #expect(ShortcutPriority.defaultPriority(for: HistoryPage.action) == .preferCra)
    }
}
