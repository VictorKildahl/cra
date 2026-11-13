import Foundation

extension LinkSummaryPreviewController {
    /// Installed once by bootstrap. Off/on transitions must revoke the current generation before
    /// observation delivery can coalesce them; fresh eligibility alone cannot detect that ABA.
    func bindEligibility(to store: SidebarStore) {
        store.fiveSecondPreviewsChanged = { [weak self] enabled in
            if !enabled { self?.stop() }
        }
        TidyTabsService.shared.previewsUnavailable = { [weak self] in self?.stop() }
    }
}
