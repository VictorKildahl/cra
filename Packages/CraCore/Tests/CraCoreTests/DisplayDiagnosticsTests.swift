import CraCore
import Testing

/// Help ▸ Export Diagnostics: the displays and their refresh rates (#80).
struct DisplayDiagnosticsTests {
    let laptop = DisplayDiagnostics(width: 1800, height: 1169, scale: 2, maximumHz: 120, minimumHz: 24, builtIn: true, main: true)
    let monitor = DisplayDiagnostics(width: 3440, height: 1440, scale: 1, maximumHz: 200, minimumHz: 200, builtIn: false, main: false)

    /// The diagnostics export names each display with its refresh rate, a variable one with its range
    /// (#80).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/80"))
    func variableRateDisplayShowsItsRange() {
        #expect(laptop.line == "built-in 1800x1169@2x, 120 Hz (variable from 24), main")
    }

    /// A fixed-rate display shows its one rate (#80).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/80"))
    func fixedRateDisplayShowsOneRate() {
        #expect(monitor.line == "external 3440x1440@1x, 200 Hz")
    }

    /// Frame intervals read as whole hertz; none or a bad one reads 0 (#80).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/80"), arguments: [(1.0 / 120, 120), (1.0 / 59.94, 60), (0, 0), (-1, 0)])
    func intervalsBecomeWholeHertz(interval: Double, hz: Int) {
        #expect(DisplayDiagnostics.hz(interval: interval) == hz)
    }

    /// Displays at different top rates are flagged as mixed, the setup tied to pages that never paint
    /// on macOS 27 (#80).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/80"))
    func differentTopRatesAreMixed() {
        #expect(DisplayDiagnostics.mixedRates([laptop, monitor]))
        #expect(DisplayDiagnostics.summary([laptop, monitor]) == """
            Displays: 2, mixed refresh rates
              built-in 1800x1169@2x, 120 Hz (variable from 24), main
              external 3440x1440@1x, 200 Hz
            """)
    }

    /// The same top rate, or an unknown one, is not mixed (#80).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/80"))
    func sameTopRateOrUnknownIsNotMixed() {
        var other = monitor
        other.maximumHz = 120
        #expect(!DisplayDiagnostics.mixedRates([laptop, other]))
        other.maximumHz = 0
        #expect(!DisplayDiagnostics.mixedRates([laptop, other]))
        #expect(DisplayDiagnostics.summary([laptop]) == "Displays: 1\n  built-in 1800x1169@2x, 120 Hz (variable from 24), main")
        #expect(DisplayDiagnostics.summary([]) == "Displays: none")
    }
}
