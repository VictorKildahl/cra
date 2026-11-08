import CraCore
import Foundation
import Testing

/// The sidebar's ⌘S motion against Arc 1.172.1's frames (8 Nov 2026).
struct SidebarMotionTests {
    /// Arc's hide and show, the share of the travel after each 60 fps frame.
    static let arc: [[Double]] = [[0.43, 0.72, 0.89, 0.975, 1], [0.42, 0.71, 0.89, 0.97, 1], [0.35, 0.67, 0.86, 0.96, 1], [0.34, 0.66, 0.92, 0.99, 1]]

    /// Each run, at the best of ten sub-frame phases (when the animation began within its first frame).
    static func error(_ curve: (Double, Double, Double, Double)) -> Double {
        arc.map { run in
            (1...10).map { Double($0) / 600 }.map { phase in
                run.enumerated().map { k, v in
                    let p = SidebarMotion.progress(at: phase + Double(k) / 60, curve: curve)
                    return (p - v) * (p - v)
                }.reduce(0, +)
            }.min()!
        }.reduce(0, +)
    }

    @Test func followsArcsFrames() {
        #expect(Self.error(SidebarMotion.curve) < 0.006)
        // The Arc 1.170 fit runs well ahead of Arc 1.172.1 in the first frames.
        #expect(Self.error((0.15, 0.7, 0.3, 1)) > 0.02)
    }

    @Test func endsInFiveFrames() {
        #expect(SidebarMotion.progress(at: 0) < 1e-9)
        #expect(SidebarMotion.progress(at: 5.0 / 60) > 0.97)
        #expect(SidebarMotion.progress(at: 1) > 1 - 1e-9)
    }
}
