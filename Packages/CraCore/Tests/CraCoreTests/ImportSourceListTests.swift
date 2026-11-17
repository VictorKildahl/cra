import CraCore
import Testing

struct ImportSourceListTests {
    static let all = ["arc", "dia", "chrome", "brave", "edge", "opera", "operagx", "vivaldi", "chromium", "helium", "firefox", "zen", "safari"]

    /// The browser step lists every browser Cra imports from, not only the ones on this Mac:
    /// those with data first, the rest after in Cra's order (Victor, 12 Nov 2026).
    @Test func listsEveryBrowserWithTheAvailableOnesFirst() {
        let list = ImportSourceList.ordered(Self.all, available: ["arc", "chrome", "firefox", "safari", "dia"])
        #expect(list.count == 13)
        #expect(list == ["arc", "dia", "chrome", "firefox", "safari",
                         "brave", "edge", "opera", "operagx", "vivaldi", "chromium", "helium", "zen"])
        #expect(ImportSourceList.ordered(Self.all, available: []) == Self.all)
    }

    static let arc = "company.thebrowser.Browser", dia = "company.thebrowser.dia", chrome = "com.google.Chrome", safari = "com.apple.Safari"
    static let fallbacks = [arc, dia, chrome, safari]
    static func neighbours(_ defaultBrowser: String?, _ installed: Set<String>) -> (left: String?, right: String?) {
        ImportSourceList.dockNeighbours(defaultBrowser: defaultBrowser, installed: installed,
                                        isCra: { $0.hasPrefix("dk.kildahl.cra") }, fallbacks: fallbacks)
    }

    /// With Cra already the default browser the Dock art showed Cra's tile twice, once as the
    /// default on the left (Victor, 12 Nov 2026). Another browser stands in for it.
    @Test func craIsNeverItsOwnNeighbour() {
        let n = Self.neighbours("dk.kildahl.cra", [Self.arc, Self.dia, Self.safari, "dk.kildahl.cra"])
        #expect(n.left == Self.dia)
        #expect(n.right == Self.arc)
        let take = Self.neighbours("dk.kildahl.cra", [Self.arc, Self.dia, "dk.kildahl.cra.take"])
        #expect(take.left == Self.dia && take.right == Self.arc)
    }

    /// The default browser lands on the left as before; Arc on the right, or Dia when Arc is the default.
    @Test func theDefaultBrowserStaysOnTheLeft() {
        let safari = Self.neighbours(Self.safari, [Self.arc, Self.dia, Self.safari])
        #expect(safari.left == Self.safari && safari.right == Self.arc)
        let arc = Self.neighbours(Self.arc, [Self.arc, Self.dia, Self.safari])
        #expect(arc.left == Self.arc && arc.right == Self.dia)
        let none = Self.neighbours(nil, [Self.safari])
        #expect(none.left == nil && none.right == Self.safari)
    }
}
