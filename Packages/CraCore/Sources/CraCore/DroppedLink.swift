import Foundation

/// A link dragged into the sidebar's list from a page or another app (#419). Arc's sidebar takes
/// one external item (`SidebarDragItem.external(String)`), so the first web address wins; files,
/// `javascript:` and loose text are left to whatever else takes the drop.
public enum DroppedLink {
    /// `urls` are the pasteboard's URL objects, `text` its plain string. A page's link drag
    /// carries both; a dragged selection only has the text.
    public static func address(urls: [String], text: String?) -> String? {
        (urls + [text].compactMap { $0 }).lazy.compactMap(Easel.webAddress).first
    }
}
