import Testing
import CraCore

/// Chromium 156's strings, from its locale packs (cef-156.0.26): IDS_CONTENT_CONTEXT_SEARCHLENSFORIMAGE
/// and IDS_CONTENT_CONTEXT_SEARCHWEBFORIMAGE.
@Suite struct PageMenuLabelsTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/276"))
    func imageSearchReadsInChromiumsLanguage() {
        #expect(PageMenuLabels.imageSearch(lensLabel: "Найти через Google", lensTemplate: "Найти через $1",
                                           webTemplate: "&Найти картинку ($1)") == "&Найти картинку (Google)")
        #expect(PageMenuLabels.imageSearch(lensLabel: "Bild an Google senden", lensTemplate: "Bild an $1 senden",
                                           webTemplate: "Mit $1 nach Bild &suchen") == "Mit Google nach Bild &suchen")
        #expect(PageMenuLabels.imageSearch(lensLabel: "Bing で画像を検索", lensTemplate: "$1 で画像を検索",
                                           webTemplate: "$1 で画像を検索(&S)") == "Bing で画像を検索(&S)")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/276"))
    func englishStillReadsLikeArc() {
        #expect(PageMenuLabels.imageSearch(lensLabel: "Search Image with Google", lensTemplate: "Search Image with $1",
                                           webTemplate: "&Search $1 for Image") == "&Search Google for Image")
        #expect(PageMenuLabels.imageSearch(lensLabel: "Search Image with &Bing", lensTemplate: "Search Image with $1",
                                           webTemplate: "&Search $1 for Image") == "&Search Bing for Image")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/276"))
    func aLabelThatIsNotTheTemplatesKeepsChromiumsItem() {
        #expect(PageMenuLabels.imageSearch(lensLabel: "Search image with Google", lensTemplate: "Найти через $1",
                                           webTemplate: "&Найти картинку ($1)") == nil)
        #expect(PageMenuLabels.imageSearch(lensLabel: "Search Image with ", lensTemplate: "Search Image with $1",
                                           webTemplate: "&Search $1 for Image") == nil)
        #expect(PageMenuLabels.imageSearch(lensLabel: "Search Image with Google", lensTemplate: "",
                                           webTemplate: "&Search $1 for Image") == nil)
    }

    @Test func mnemonicsGoAsInChromiumsMacMenus() {
        #expect(PageMenuLabels.withoutMnemonics("Open Link in New &Tab") == "Open Link in New Tab")
        #expect(PageMenuLabels.withoutMnemonics("新しいタブで開く(&T)") == "新しいタブで開く")
        #expect(PageMenuLabels.withoutMnemonics("Tom && Jerry") == "Tom & Jerry")
    }
}
