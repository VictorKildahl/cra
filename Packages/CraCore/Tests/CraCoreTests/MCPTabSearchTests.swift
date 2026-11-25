import CraCore
import Testing

struct MCPTabSearchTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/796")) func everyQueryWordCanMatchTitleOrURL() {
        #expect(MCPTabSearch.matches(query: "example wiki", title: "Example — Wikipedia", url: "https://example.org/wiki/Example",
                                     space: "Personal", folder: nil, section: "today"))
        #expect(MCPTabSearch.matches(query: "example report", title: "Quarterly report", url: "https://example.com/quarterly",
                                     space: "Personal", folder: nil, section: "today"))
        #expect(!MCPTabSearch.matches(query: "example missing", title: "Example — Wikipedia", url: "https://example.org/wiki/Example",
                                      space: "Personal", folder: nil, section: "today"))
        #expect(!MCPTabSearch.matches(query: "   ", title: "Example — Wikipedia", url: "https://example.org/wiki/Example",
                                      space: "Personal", folder: nil, section: "today"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/796")) func queryAndSidebarFiltersIgnoreCase() {
        #expect(MCPTabSearch.matches(query: "EXAMPLE", title: "Example Page", url: "https://example.com",
                                     space: "Personal", folder: "Research / Reading", section: "pinned",
                                     spaceFilter: "personal", folderFilter: "research / reading", sectionFilter: "PINNED"))
        #expect(!MCPTabSearch.matches(query: "example", title: "Example Page", url: "https://example.com",
                                      space: "Personal", folder: "Research / Reading", section: "pinned",
                                      folderFilter: "Reading"))
    }
}
