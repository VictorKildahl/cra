import Testing
@testable import CraCore

@Suite struct ChromiumStartFeaturesTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/848"))
    func macOS27TurnsChromesOcclusionCheckerOff() {
        #expect(ChromiumStartFeatures.enabled(macOSMajor: 27) == ["MacOcclusionForceShutoff"])
        #expect(ChromiumStartFeatures.enabled(macOSMajor: 28) == ["MacOcclusionForceShutoff"])
        #expect(ChromiumStartFeatures.enabled(macOSMajor: 26).isEmpty)
        #expect(ChromiumStartFeatures.enabled(macOSMajor: 15).isEmpty)
    }

    @Test func aScenarioCanSayWhichMacOSItIs() {
        #expect(ChromiumStartFeatures.macOSMajor(environment: ["CRA_MACOS_MAJOR": "27"], actual: 26) == 27)
        #expect(ChromiumStartFeatures.macOSMajor(environment: [:], actual: 26) == 26)
        #expect(ChromiumStartFeatures.macOSMajor(environment: ["CRA_MACOS_MAJOR": "x"], actual: 26) == 26)
        #expect(ChromiumStartFeatures.major(productVersion: "27.2.1") == 27)
        #expect(ChromiumStartFeatures.major(productVersion: "26.7") == 26)
        #expect(ChromiumStartFeatures.major(productVersion: "") == nil)
    }
}
