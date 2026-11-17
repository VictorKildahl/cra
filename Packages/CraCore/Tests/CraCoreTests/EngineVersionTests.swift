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

struct CraVersionTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/461"))
    func theCopiedVersionNamesBuildAndEngine() {
        #expect(CraVersion.line(short: "0.1.45", build: "202611161908", engine: "Chromium 158.0.8127.37")
            == "Cra 0.1.45 (202611161908) · Chromium 158.0.8127.37")
    }

    @Test func aMissingBuildOrEngineLeavesItOut() {
        #expect(CraVersion.line(short: "0.1.45", build: "", engine: "Chromium 158.0.8127.37") == "Cra 0.1.45 · Chromium 158.0.8127.37")
        #expect(CraVersion.line(short: "dev", build: "1", engine: "") == "Cra dev (1)")
    }
}
