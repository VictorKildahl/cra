import Foundation

/// Switches for the paths that rest on private or fragile API, so a scenario can run each
/// one and a new macOS that breaks the private path fails a gate instead of shipping.
/// CRA_FLAGS="backdrop=material" sets them for a test instance; the log names the choice once.
struct FeatureFlags: Equatable {
    enum Backdrop: String { case layer, material }
    /// `layer`: the sidebar's behind-window blur is a CABackdropLayer with Core Animation's
    /// private gaussian CAFilter (ShellView), calibrated against Arc; it falls back to
    /// `material` when the runtime lacks those classes. `material`: NSVisualEffectView only.
    var backdrop: Backdrop = .layer

    init(backdrop: Backdrop = .layer) { self.backdrop = backdrop }

    /// "backdrop=material&…"; unknown keys and values keep the defaults.
    init(parsing spec: String) {
        self.init()
        for pair in spec.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if kv[0] == "backdrop", let v = Backdrop(rawValue: kv[1]) { backdrop = v }
        }
    }

    static let current = FeatureFlags(parsing: ProcessInfo.processInfo.environment["CRA_FLAGS"] ?? "")

    var summary: String { "backdrop=\(backdrop.rawValue)" }
}
