import Foundation

/// Which pages to ask, in turn, to run one of Chrome's own browser commands (#855).
///
/// Chrome's Task Manager belongs to the browser, not to a page: Arc's Help ▸ Troubleshooting ▸ Open Task Manager
/// opens it whatever the window shows. Cra's engine runs a Chrome command through a page's hidden Chrome window, so
/// with no page in front (no tab selected, the new-tab bar up) it said "Open a Page First" while other pages were
/// open. The page in front goes first, then the rest of the window's pages, then every other page Cra has open;
/// each page once. Only when Cra has no page at all is there nothing to ask.
public enum ChromeCommandPages {
    public static func order<Page: AnyObject>(front: Page?, sameWindow: [Page], elsewhere: [Page]) -> [Page] {
        var seen = Set<ObjectIdentifier>()
        return ([front].compactMap { $0 } + sameWindow + elsewhere).filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}
