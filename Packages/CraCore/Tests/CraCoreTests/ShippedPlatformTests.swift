import CraCore
import Foundation
import Testing

/// What closed issues about privacy, profiles and performance shipped, where no older test
/// pinned it on its own.
struct ShippedPlatformTests {
    /// Settings ▸ Privacy ▸ Secure DNS (#133) lists Automatic, Off, then these providers in this
    /// order, each with the template chrome://settings/security writes for it, then Custom….
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/133"))
    func secureDNSMenuProviders() {
        #expect(SecureDNSProvider.all.map(\.name) == [
            "Google (Public DNS)", "Cloudflare (1.1.1.1)", "Quad9 (9.9.9.9)", "OpenDNS",
            "CleanBrowsing (Family Filter)", "DNS4EU (Protective)",
        ])
        #expect(SecureDNSProvider.all.allSatisfy { SecureDNSPrefs.validTemplates($0.template) == $0.template })
    }

    /// Settings ▸ Performance (#91) records from the first launch, with site names kept until
    /// "Hide site names" is ticked, and a settings file without the keys reads the same way.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/91"))
    func performanceRecordingIsOnByDefault() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s.perfRecording && !s.perfHidesSiteNames)
        #expect(AppSettings().perfRecording && !AppSettings().perfHidesSiteNames)
    }

    /// The permission sheet (#137) names MIDI and the clipboard in Chrome's words, not as "a
    /// browser permission".
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/137"))
    func permissionSheetNamesMIDIAndTheClipboard() {
        let site = "https://synth.example/"
        #expect(PermissionPrompt.message(origin: site, kinds: 1 << 13) == "https://synth.example/ wants to control and reprogram your MIDI devices")
        #expect(PermissionPrompt.message(origin: site, kinds: 1 << 5) == "https://synth.example/ wants to see text and images copied to the clipboard")
    }
}
