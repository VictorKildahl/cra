import AppKit

// Shared by the live folder's rows and menu (SidebarRowViews, SidebarMenus) and the folder glyph
// harness (scripts/test-folder-glyph.sh), which compiles this file on its own.

/// GitHub's mark (Primer Octicons mark-github, MIT) for the live folder and its tabs (Arc: the
/// GithubFavicon asset and customInfo.iconType "github"), on that asset's 32 pt canvas.
/// github.com's own favicon is no stand-in: Cra caches favicons per host and GitHub swaps in a
/// red ✕ while a pull request's checks fail.
enum GitHubMark {
    static let image: NSImage = {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="32" height="32"><path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/></svg>"#
        let img = NSImage(data: Data(svg.utf8)) ?? NSImage()
        img.isTemplate = true
        return img
    }()
}

/// GitLab's tanuki in one colour, tinted like GitHubMark: Arc draws its GitHub folder's mark in the
/// folder's ink, so the GitLab folder does the same rather than show the full-colour logo.
enum GitLabMark {
    static let image: NSImage = {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 25 24" width="32" height="32"><path d="m24.507 9.5-.034-.09L21.082.562a.896.896 0 0 0-1.694.091l-2.29 7.01H7.825L5.535.653a.898.898 0 0 0-1.694-.09L.451 9.411.416 9.5a6.297 6.297 0 0 0 2.09 7.278l.012.01.03.022 5.16 3.867 2.56 1.935 1.554 1.176a1.051 1.051 0 0 0 1.268 0l1.555-1.176 2.56-1.935 5.197-3.89.014-.01A6.297 6.297 0 0 0 24.507 9.5Z"/></svg>"#
        let img = NSImage(data: Data(svg.utf8)) ?? NSImage()
        img.isTemplate = true
        return img
    }()
}
