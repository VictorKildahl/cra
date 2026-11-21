import Foundation
import Testing
@testable import CraCore

/// Every profile renameable, Default too, under the name Chromium shows (#666).
struct ProfileNamesTests {
    let work = BrowserProfile(id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!, name: "Work")

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/666"))
    func defaultHasANameOfItsOwn() {
        #expect(ProfileNames.name(of: nil, profiles: [work], defaultProfileName: nil) == "Default")
        #expect(ProfileNames.name(of: nil, profiles: [work], defaultProfileName: "HEXA") == "HEXA")
        #expect(ProfileNames.name(of: nil, profiles: [], defaultProfileName: "  ") == "Default")
        #expect(ProfileNames.name(of: work.id, profiles: [work], defaultProfileName: "HEXA") == "Work")
        #expect(ProfileNames.name(of: UUID(), profiles: [work], defaultProfileName: "HEXA") == "Default")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/666"))
    func aRenameIsTrimmedAndNeverEmpty() {
        #expect(ProfileNames.cleaned("  HEXA \n") == "HEXA")
        #expect(ProfileNames.cleaned(" \t") == nil)
        // sidebar.json keeps nothing until Default is renamed, and forgets a rename back.
        #expect(ProfileNames.stored(defaultProfileName: " Personal ") == "Personal")
        #expect(ProfileNames.stored(defaultProfileName: "Default") == nil)
        #expect(ProfileNames.stored(defaultProfileName: "") == nil)
    }

    /// The prefs Chromium names a profile by, as chrome://settings writes them, quotes and all.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/666"))
    func chromiumGetsTheSameName() throws {
        let prefs = ProfileNames.chromiumPrefs(name: #"Jo's "Work" ✨"#)
        #expect(prefs.map(\.pref) == ["profile.name", "profile.using_default_name"])
        let value = try JSONSerialization.jsonObject(with: Data(prefs[0].json.utf8), options: .fragmentsAllowed) as? String
        #expect(value == #"Jo's "Work" ✨"#)
        #expect(prefs[1].json == "false")
    }

    /// sidebar.json keeps Default's name beside the other profiles; a file without one loads as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/666"))
    func sidebarKeepsDefaultsName() throws {
        var doc = SidebarDocument.fresh()
        let plain = try JSONEncoder().encode(doc)
        #expect(!String(decoding: plain, as: UTF8.self).contains("defaultProfileName"))
        #expect(try JSONDecoder().decode(SidebarDocument.self, from: plain).defaultProfileName == nil)
        doc.defaultProfileName = "HEXA"
        let named = try JSONDecoder().decode(SidebarDocument.self, from: JSONEncoder().encode(doc))
        #expect(named.defaultProfileName == "HEXA" && named == doc)
    }
}
