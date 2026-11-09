import CoreGraphics
import CraCore
import Foundation
import Testing

/// Arc's preview for a pick in Library ▸ Media, measured on Victor's Arc (8 Nov 2026).
struct MediaPreviewTests {
    @Test func thePanelSitsWhereArcsDid() {
        let p = MediaPreview.panel(in: CGRect(x: 0, y: 0, width: 1728, height: 1084))
        #expect(p == CGRect(x: 199, y: 133, width: 1330, height: 818))
    }

    @Test func thePictureFitsUnderTheHeader() {
        let panel = CGRect(x: 199, y: 133, width: 1330, height: 818)
        // Arc's square picture: 739 pt tall under the 46 pt header, centred across.
        let r = MediaPreview.media(CGSize(width: 1024, height: 1024), in: panel)
        #expect(r.height == 742.0)
        #expect(r.width == r.height)
        #expect(abs(r.midX - panel.midX) <= 0.5)
        #expect(r.minY == 148.0)
        // A wide one fills the width instead.
        let wide = MediaPreview.media(CGSize(width: 4000, height: 1000), in: panel)
        #expect(wide.width == 1300.0)
    }

    @Test func arrowsStopAtTheEnds() {
        #expect(MediaPreview.step(0, by: -1, count: 3) == nil)
        #expect(MediaPreview.step(0, by: 1, count: 3) == 1)
        #expect(MediaPreview.step(2, by: 1, count: 3) == nil)
    }

    @Test func theHeadersAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(MediaPreview.age(now.addingTimeInterval(-86_400), now: now) == "1 day ago")
        #expect(MediaPreview.age(now.addingTimeInterval(-10), now: now) == "Just now")
    }
}
