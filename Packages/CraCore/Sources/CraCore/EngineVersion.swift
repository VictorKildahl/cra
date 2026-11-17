/// The engine's version as Settings, About, the Help menu and Diagnostics name it: "Chromium 158.0.8127.37", with
/// "· CEF <version>" after it only for a build on CEF (the Chromium engine has none).
public enum EngineVersion {
    public static func label(chromium: String, cef: String, separator: String = " · ") -> String {
        cef.isEmpty ? "Chromium \(chromium)" : "Chromium \(chromium)\(separator)CEF \(cef)"
    }
}

/// Cra's version on one line, what a bug report's "Cra version" asks for: "Cra 0.1.45 (202611161908) · Chromium
/// 158.0.8127.37". A click on the version in Settings ▸ Advanced ▸ About copies it (GitHub #461). `engine` is
/// `EngineVersion.label`; an empty build (a copy without one) leaves its brackets out.
public enum CraVersion {
    public static func line(short: String, build: String, engine: String) -> String {
        let version = build.isEmpty ? "Cra \(short)" : "Cra \(short) (\(build))"
        return engine.isEmpty ? version : "\(version) · \(engine)"
    }
}
