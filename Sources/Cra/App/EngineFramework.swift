import Foundation

/// The Chromium framework in Cra.app/Contents/Frameworks, whichever engine Cra is built on: CEF's ("Chromium
/// Embedded Framework") or Chrome's own with Cra's branding ("Cra Framework", docs/chromium-engine.md).
enum EngineFramework {
    static let names = ["Cra Framework", "Chromium Embedded Framework"]

    /// The framework bundle.
    static var bundleURL: URL? {
        guard let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        return names.lazy.map { frameworks.appendingPathComponent("\($0).framework") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The framework's binary.
    static var binaryURL: URL? {
        guard let bundle = bundleURL else { return nil }
        return bundle.appendingPathComponent(bundle.deletingPathExtension().lastPathComponent)
    }
}
