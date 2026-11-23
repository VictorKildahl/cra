import AppKit

extension NSText {
    /// Selects the whole text and shows its start, as Arc, Chrome and Safari show a long address
    /// when it comes up selected. `selectAll` alone keeps the editor's scroll, so a field left
    /// scrolled to the end of the last address it held showed only the new one's tail (X report,
    /// 23 Nov 2026: a Google Sheets link read "…zhGOKyPN-tQ5yZ_09zEaPjy5HVRZsh_vKc/edit?gid=0#gid=0").
    func selectAllShowingStart() {
        selectAll(nil)
        scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}
