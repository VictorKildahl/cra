import CraCore
import Testing

/// Settings ▸ Max says why its features are off from what FoundationModels reports and the Mac.
@Suite struct AppleIntelligenceStatusTests {
    typealias Status = AppleIntelligenceStatus

    @Test func reasonsMapToSettingsStatus() {
        #expect(Status(reason: nil, hardware: .appleSilicon) == .available)
        #expect(Status(reason: .appleIntelligenceNotEnabled, hardware: .appleSilicon) == .off)
        #expect(Status(reason: .modelNotReady, hardware: .appleSilicon) == .preparing)
        #expect(Status(reason: .other, hardware: .appleSilicon) == .unavailable)
        #expect(Status(reason: .deviceNotEligible, hardware: .intel) == .needsAppleSilicon)
    }

    /// macOS 27.3 beta 2 brings Apple Intelligence to Macs in China without giving apps its model:
    /// FoundationModels says the device isn't eligible, and Settings ▸ Max told an Apple silicon
    /// Mac that it needed Apple silicon.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/538"))
    func appleSiliconMacWithoutTheModelIsNotToldItNeedsAppleSilicon() {
        let status = Status(reason: .deviceNotEligible, hardware: .appleSilicon)
        #expect(status == .notOfferedToApps)
        #expect(!status.explanation.contains("needs a Mac with Apple silicon"))
        // System Settings can't turn it on, so Settings ▸ Max offers no way there.
        #expect(!status.canOpenSettings)
    }

    @Test func intelCopyOnAppleSiliconPointsAtTheAppleSiliconCopy() {
        let status = Status(reason: .deviceNotEligible, hardware: .rosetta)
        #expect(status == .needsAppleSiliconCopy)
        #expect(status.explanation.contains("Apple silicon"))
        #expect(!status.canOpenSettings)
    }

    @Test func onlyFixableStatusesLinkToSystemSettings() {
        let fixable: [Status] = [.off, .preparing, .unavailable]
        let all: [Status] = [.available, .off, .preparing, .needsAppleSilicon, .needsAppleSiliconCopy,
                             .notOfferedToApps, .needsNewerMacOS, .unavailable]
        for status in all { #expect(status.canOpenSettings == fixable.contains(status), "\(status)") }
        #expect(Set(all.map(\.explanation)).count == all.count, "each status says something of its own")
    }
}
