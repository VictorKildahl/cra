import Foundation

/// Which of an extension's icon files Cra draws at a size, the way Chromium's ExtensionIconSet
/// picks them for each screen scale: the smallest file with at least that many pixels
/// (MATCH_BIGGER), else the largest there is (MATCH_SMALLER).
///
/// Cra used to take the smallest file of at least 16 px whatever the screen, so a 16 pt
/// toolbar button on a Retina screen drew the 16 px file twice its size, blurred, where Chrome
/// draws the 32 or 48 px one (GitHub #349).
public enum ExtensionIcons {
    /// - Parameters:
    ///   - icons: a manifest's `icons` (or an action's `default_icon`): pixel size → file.
    ///     Keys that aren't sizes are ignored, as Chromium ignores them.
    ///   - points: the size the icon is drawn at.
    ///   - scales: the screen scales to cover, 1x first.
    /// - Returns: one file per scale, smallest scale first, each file once (a scale whose pick
    ///   is the previous scale's adds nothing).
    public static func files(_ icons: [String: String], points: Int, scales: [Int] = [1, 2]) -> [String] {
        let sized = icons.compactMap { key, file in Int(key).flatMap { $0 > 0 ? ($0, file) : nil } }
            .sorted { $0.0 < $1.0 }
        guard let largest = sized.last else { return [] }
        var picked: [String] = []
        for scale in scales.sorted() {
            let pixels = points * scale
            let file = sized.first(where: { $0.0 >= pixels })?.1 ?? largest.1
            if !picked.contains(file) { picked.append(file) }
        }
        return picked
    }
}
