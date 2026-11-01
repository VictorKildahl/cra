import Foundation

/// What favicons are cached under: the page's host, lowercased (Arc: SidebarItemsFaviconCache).
public enum FaviconKey {
    public static func key(for urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }
}
