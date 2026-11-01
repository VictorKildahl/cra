import Foundation

/// What Help ▸ Export Diagnostics keeps. The zip goes to a public GitHub issue, so it names
/// sites, not pages, and not the user.
public enum DiagnosticsRedaction {
    /// Addresses keep their scheme and host, without a `user:password@`; the home folder becomes
    /// `~`, also in the `\/`-escaped form JSON (crash reports) writes. The single sign-on hosts IT
    /// allowlisted (Chromium's command line in gpu.json) name the user's employer.
    public static func redact(_ text: String, home: String) -> String {
        var s = text
        if !home.isEmpty {
            s = s.replacingOccurrences(of: home, with: "~")
                .replacingOccurrences(of: home.replacingOccurrences(of: "/", with: #"\/"#), with: "~")
        }
        for (pattern, template) in [(#"\b([A-Za-z][A-Za-z0-9+.-]*://)[^/\s"'<>)\]@]*@"#, "$1"),
                                    (#"\b((?:https?|wss?|ftp|chrome-extension)://[^/\s"'<>)\]]+)[/?#][^\s"'<>)\]]*"#, "$1/…"),
                                    (#"(--auth-server-allowlist=)[^\s"]+"#, "$1(set by IT)")] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s
    }

    /// macOS names a crash report after the process that crashed: `Cra-<date>.ips` and
    /// `Cra Helper (Renderer)-<date>.ips`. Other apps' names can start with "Cra" too (Craft).
    public static func isCraCrashReport(_ fileName: String) -> Bool {
        fileName.hasPrefix("Cra-") || fileName.hasPrefix("Cra Helper")
    }
}
