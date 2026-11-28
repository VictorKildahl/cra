import Foundation

/// View ▸ Zoom In and Zoom Out (⌘+ ⌘−), as Arc does them: Chrome's own steps (zoom::PageZoom::Zoom over
/// blink::kPresetBrowserZoomFactors), so a page goes 100 → 110 → 125 % and back 100 → 90 → 80 %, and Arc's zoom
/// pill names the step ("125%"). Cra stepped the zoom level by half a level (×1.2^0.5), which reads 110 % then
/// 120 % and never lands on 125 % (GitHub #856, measured in Arc 1.174.3 on 26 Nov 2026).
public enum PageZoomSteps {
    /// Chrome's preset zoom factors (third_party/blink/common/page/page_zoom.cc).
    public static let presetFactors: [Double] = [0.25, 1 / 3.0, 0.5, 2 / 3.0, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75,
                                                 2.0, 2.5, 3.0, 4.0, 5.0]

    /// Chromium's zoom level for a factor: each level is ×1.2 (blink::ZoomFactorToZoomLevel).
    public static func level(factor: Double) -> Double { log(factor) / log(1.2) }
    public static func factor(level: Double) -> Double { pow(1.2, level) }

    /// The next level in (or out) from `level`, Chrome's way: the nearest preset past it, skipping any within
    /// blink::ZoomValuesEqual's 0.001 of it. Nil at 25 % going out or 500 % going in.
    public static func next(from level: Double, zoomIn: Bool) -> Double? {
        let levels = presetFactors.map { Self.level(factor: $0) }
        let candidates = zoomIn ? levels.filter { $0 > level + 0.001 } : levels.filter { $0 < level - 0.001 }
        return zoomIn ? candidates.min() : candidates.max()
    }

    /// What Arc's pill says for a level: the factor in whole percent ("125%", "33%").
    public static func label(level: Double) -> String { "\(Int((factor(level: level) * 100).rounded()))%" }
}
