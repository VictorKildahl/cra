import CraCore
import Testing

struct EngineVersionTests {
    @Test func theChromiumEngineNamesNoCEF() {
        #expect(EngineVersion.label(chromium: "158.0.8127.37", cef: "") == "Chromium 158.0.8127.37")
    }

    @Test func aCEFBuildNamesBoth() {
        #expect(EngineVersion.label(chromium: "156.0.7801.2", cef: "156.0.27") == "Chromium 156.0.7801.2 · CEF 156.0.27")
        #expect(EngineVersion.label(chromium: "156", cef: "156.0.27", separator: ", ") == "Chromium 156, CEF 156.0.27")
    }
}
