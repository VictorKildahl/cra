import CraCore
import Foundation
import Testing

struct FolderSymbolTests {
    @Test(arguments: FolderSymbol.allCases)
    func selectedSymbolSurvivesReload(_ symbol: FolderSymbol) throws {
        var folder = SidebarItem.folder("Reading", parent: nil)
        folder.folderIcon = .white
        folder.folderSymbol = symbol
        let reloaded = try JSONDecoder().decode(SidebarItem.self, from: JSONEncoder().encode(folder))
        #expect(reloaded == folder)
        #expect(reloaded.folderSymbol == symbol)
        #expect(reloaded.folderIcon == .white)
    }

    /// Cra 0.1.35 decodes `folderIcon` as a plain colour string and fails the whole sidebar.json
    /// on anything else, which starts it with an empty sidebar. The symbol sits beside it instead.
    @Test func symbolLeavesTheColourKeyReadableByAnOlderCra() throws {
        var folder = SidebarItem.folder("Reading", parent: nil)
        folder.folderIcon = .black
        folder.folderSymbol = .code
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(folder)) as? [String: Any]
        #expect(json?["folderIcon"] as? String == "black")
        #expect(json?["folderSymbol"] as? String == "code")
    }

    @Test func noSymbolWritesNoKey() throws {
        var folder = SidebarItem.folder("Reading", parent: nil)
        folder.folderIcon = .white
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(folder)) as? [String: Any]
        #expect(json?["folderSymbol"] == nil)
        #expect(json?["folderIcon"] as? String == "white")
    }

    @Test func symbolWithoutColourFollowsTheTheme() throws {
        var folder = SidebarItem.folder("Reading", parent: nil)
        folder.folderSymbol = .star
        let reloaded = try JSONDecoder().decode(SidebarItem.self, from: JSONEncoder().encode(folder))
        #expect(reloaded.folderIcon == nil)
        #expect(reloaded.folderSymbol == .star)
    }
}
