import CraCore
import Foundation
import Testing

struct FolderSymbolTests {
    @Test func previousLeafIdentifierStillLoads() throws {
        let symbol = try JSONDecoder().decode(FolderSymbol.self, from: Data(#""pizza""#.utf8))
        #expect(symbol.rawValue == "leaf")
    }

    @Test(arguments: FolderSymbol.allCases)
    func selectedSymbolSurvivesReload(_ symbol: FolderSymbol) throws {
        var folder = SidebarItem.folder("Reading", parent: nil)
        folder.folderIcon = FolderIcon(color: .white, symbol: symbol)
        let reloaded = try JSONDecoder().decode(SidebarItem.self, from: JSONEncoder().encode(folder))
        #expect(reloaded == folder)
        #expect(reloaded.folderIcon?.symbol == symbol)
        #expect(reloaded.folderIcon?.color == .white)
    }

    @Test func removingSymbolKeepsFolderColorAndOldFormat() throws {
        var folder = SidebarItem.folder("Reading", parent: nil)
        folder.folderIcon = FolderIcon(color: .black)
        let original = try JSONEncoder().encode(folder)
        #expect(!String(decoding: original, as: UTF8.self).contains("folderSymbol"))
        #expect(try JSONDecoder().decode(SidebarItem.self, from: original).folderIcon?.symbol == nil)
        folder.folderIcon?.symbol = .code
        folder.folderIcon?.symbol = nil
        #expect(try JSONDecoder().decode(SidebarItem.self, from: JSONEncoder().encode(folder)).folderIcon?.color == .black)
        let removed = try JSONEncoder().encode(folder)
        #expect(!String(decoding: removed, as: UTF8.self).contains("folderSymbol"))
        #expect(try JSONDecoder().decode(SidebarItem.self, from: removed) == JSONDecoder().decode(SidebarItem.self, from: original))
    }

    @Test(arguments: FolderIconStyle.allCases)
    func legacyColorEncodingStaysCompatible(_ color: FolderIconStyle) throws {
        let legacy = try JSONEncoder().encode(color)
        let icon = try JSONDecoder().decode(FolderIcon.self, from: legacy)
        #expect(icon == FolderIcon(color: color))
        #expect(try JSONEncoder().encode(icon) == legacy)
    }

    @Test func symbolWithoutColorFollowsTheTheme() throws {
        let icon = FolderIcon(symbol: .code)
        #expect(!icon.isEmpty)
        #expect(FolderIcon().isEmpty)
        #expect(try JSONDecoder().decode(FolderIcon.self, from: JSONEncoder().encode(icon)) == icon)
        #expect(try JSONDecoder().decode(FolderIcon.self, from: Data("{}".utf8)).isEmpty)
    }
}
