import AppKit
import CraCEF

/// One Chromium page per profile made ahead, which the next tab that needs a page takes (SparePage
/// in CraCore): the ~34 ms CEF spends making a page's window then falls between clicks, not on one.
/// Shared by every window's BrowserManager. A spare has no delegate and no tab; its window stays
/// hidden and extensions don't see it (Cra.setSpare) until a tab takes it.
@MainActor
final class SparePages {
    static let shared = SparePages()

    /// CRA_SPARE_PAGES=0 turns spares off (for measuring and for a CEF without Cra.setSpare).
    static let isEnabled = ProcessInfo.processInfo.environment["CRA_SPARE_PAGES"] != "0"

    private var spares: [String: CraBrowser] = [:]
    private var pending: [String: ScheduledWork] = [:]

    /// A spare for `profilePath` that Chromium has finished making, or nil. It is no longer kept.
    func take(profilePath: String?) -> CraBrowser? {
        let key = SparePage.key(profilePath: profilePath)
        guard Self.isEnabled, let b = spares[key] else { return nil }
        guard b.isCreated, !b.isClosed else { return nil }
        spares[key] = nil
        return b
    }

    /// Makes `profilePath`'s next spare `SparePage.refillDelay` from now, unless it has one.
    func refill(profilePath: String?, frame: NSRect, clock: Scheduler) {
        let key = SparePage.key(profilePath: profilePath)
        guard Self.isEnabled, CraCEFRuntime.supportsSparePages(), spares[key] == nil, pending[key] == nil else { return }
        pending[key] = clock.after(SparePage.refillDelay) { [weak self] in
            guard let self else { return }
            self.pending[key] = nil
            if let old = self.spares[key], !old.isClosed { return }
            self.spares[key] = CraBrowser(spareWithFrame: frame, profilePath: profilePath)
        }
    }

    /// Every spare and every pending refill goes (tests start from none).
    func dropAll() {
        for w in pending.values { w.cancel() }
        pending = [:]
        for b in spares.values { b.close() }
        spares = [:]
    }

    /// A profile was deleted: its spare goes too.
    func drop(profilePath: String?) {
        let key = SparePage.key(profilePath: profilePath)
        pending.removeValue(forKey: key)?.cancel()
        spares.removeValue(forKey: key)?.close()
    }
}
