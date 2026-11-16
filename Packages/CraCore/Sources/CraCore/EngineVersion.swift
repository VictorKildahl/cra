/// The engine's version as Settings, About, the Help menu and Diagnostics name it: "Chromium 158.0.8127.37", with
/// "· CEF <version>" after it only for a build on CEF (the Chromium engine has none).
public enum EngineVersion {
    public static func label(chromium: String, cef: String, separator: String = " · ") -> String {
        cef.isEmpty ? "Chromium \(chromium)" : "Chromium \(chromium)\(separator)CEF \(cef)"
    }
}
