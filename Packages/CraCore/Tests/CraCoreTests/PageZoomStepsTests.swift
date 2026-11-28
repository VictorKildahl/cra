import Testing
@testable import CraCore

@Suite struct PageZoomStepsTests {
    private func walk(_ steps: Int, zoomIn: Bool, from start: Double = 0) -> [String] {
        var level = start, seen: [String] = []
        for _ in 0..<steps {
            guard let next = PageZoomSteps.next(from: level, zoomIn: zoomIn) else { seen.append("end"); break }
            level = next
            seen.append(PageZoomSteps.label(level: level))
        }
        return seen
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/856"))
    func zoomGoesThroughChromesStepsAsInArc() {
        // Arc 1.174.3: two Zoom Ins from 100 % show 110 % then 125 %; three Zoom Outs from there end at 90 %.
        #expect(walk(2, zoomIn: true) == ["110%", "125%"])
        #expect(walk(3, zoomIn: false, from: PageZoomSteps.level(factor: 1.25)) == ["110%", "100%", "90%"])
        #expect(walk(9, zoomIn: false) == ["90%", "80%", "75%", "67%", "50%", "33%", "25%", "end"])
        #expect(walk(10, zoomIn: true) == ["110%", "125%", "150%", "175%", "200%", "250%", "300%", "400%", "500%", "end"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/856"))
    func aLevelBetweenStepsGoesToTheNearestStepPastIt() {
        // Cra's old half-level steps (120 %, 109.5 %) and a pinch-free odd level land on Chrome's next step.
        #expect(PageZoomSteps.label(level: PageZoomSteps.next(from: 1.0, zoomIn: true)!) == "125%")      // 120 % → 125 %
        #expect(PageZoomSteps.label(level: PageZoomSteps.next(from: 0.5, zoomIn: false)!) == "100%")     // 109.5 % → 100 %
        #expect(PageZoomSteps.label(level: 0) == "100%")
        #expect(PageZoomSteps.label(level: PageZoomSteps.level(factor: 2 / 3.0)) == "67%")
    }
}
