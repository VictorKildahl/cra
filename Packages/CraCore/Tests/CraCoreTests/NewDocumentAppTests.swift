import CraCore
import Foundation
import Testing

/// Arc's per-profile "New documents" app and the command bar's "New Google Doc"-style command (#375).
struct NewDocumentAppTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/375")) func arcsOptionsInArcsOrder() {
        #expect(NewDocumentApp.allCases.map(\.name) == ["Confluence Page", "Google Doc", "Notion Page", "Word Doc"])
        #expect(NewDocumentApp.allCases.map(\.commandName) == ["New Confluence Page", "New Google Doc", "New Notion Page", "New Word Doc"])
        #expect(NewDocumentApp.allCases.map(\.url) == ["https://make.page", "https://doc.new", "https://app.notion.com/new", "https://word.new"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/375")) func noChoiceIsArcsDashAndNoCommand() {
        let s = AppSettings()
        #expect(s.newDocumentApp(profileID: nil) == nil)
        #expect(s.newDocumentApp(profileID: UUID()) == nil)
        #expect(s.newDocumentCommand(profileID: nil, incognito: false) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/375")) func eachProfileOffersOnlyItsOwnApp() throws {
        var s = AppSettings()
        let work = UUID()
        s.setNewDocumentApp(.notionPage, profileID: work)
        s.setNewDocumentApp(.googleDoc, profileID: nil)
        #expect(s.newDocumentCommand(profileID: work, incognito: false) == .notionPage)
        #expect(s.newDocumentCommand(profileID: nil, incognito: false) == .googleDoc)
        #expect(s.newDocumentCommand(profileID: UUID(), incognito: false) == nil)
        #expect(s.newDocumentCommand(profileID: nil, incognito: true) == nil, "an incognito window has no profile to make it in")
        // Saved and loaded again.
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.newDocumentApps == s.newDocumentApps)
        #expect(back.newDocumentApps == [work.uuidString: .notionPage, "Default": .googleDoc])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/375")) func pickingTheDashDropsTheEntry() {
        var s = AppSettings()
        s.setNewDocumentApp(.wordDoc, profileID: nil)
        s.setNewDocumentApp(nil, profileID: nil)
        #expect(s.newDocumentApps.isEmpty)
    }

    @Test func anAppThisCraDoesNotKnowIsDroppedNotTheFile() throws {
        let json = #"{"newDocumentApps": {"Default": "googleDoc", "A0000000-0000-0000-0000-000000000001": "figmaFile"}, "httpsOnly": true}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.newDocumentApps == ["Default": .googleDoc] && s.httpsOnly)
        let bad = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"newDocumentApps": 3, "httpsOnly": true}"#.utf8))
        #expect(bad.newDocumentApps.isEmpty && bad.httpsOnly)
    }

    @Test func theChoiceSyncsWithTheProfiles() {
        var s = AppSettings()
        s.setNewDocumentApp(.confluencePage, profileID: nil)
        #expect(s.forSync().newDocumentApp(profileID: nil) == .confluencePage)
        #expect(AppSettings().applyingSynced(s.forSync()).newDocumentApp(profileID: nil) == .confluencePage)
    }
}
