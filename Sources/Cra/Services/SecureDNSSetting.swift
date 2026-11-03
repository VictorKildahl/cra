import CraCEF
import Observation

/// Settings ▸ Privacy ▸ Secure DNS (#133): Chromium's own setting in Local State, read live and
/// written back, with no copy in settings.json. AppDelegate refreshes it when Chromium reports
/// a change, wherever it was made (chrome://settings/security too).
@MainActor
@Observable
final class SecureDNSSetting {
    static let shared = SecureDNSSetting()

    /// What Chromium holds now; nil until Chromium is ready.
    private(set) var prefs: SecureDNSPrefs?
    /// A policy sets it, so the menu is read-only.
    private(set) var isManaged = false

    var inEffect: SecureDNS? { prefs.map { SecureDNS(mode: $0.mode, templates: $0.templates) } }

    private init() {}

    func refresh() {
        prefs = CraCEFRuntime.secureDNSMode().map { SecureDNSPrefs(mode: $0, templates: CraCEFRuntime.secureDNSTemplates() ?? "") }
        isManaged = CraCEFRuntime.secureDNSIsManaged()
    }

    /// False when Chromium refused it (not ready, managed, write failed).
    @discardableResult
    func apply(_ new: SecureDNSPrefs) -> Bool {
        let ok = CraCEFRuntime.setSecureDNSMode(new.mode, templates: new.templates)
        refresh()
        return ok
    }
}
