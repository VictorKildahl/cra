import CraCore
import OSLog
import SwiftUI

extension MobileAppIcon {
    // Icon Composer previews are standalone bundle files. The other previews live in the asset catalog.
    private static let filePreviews: [Self: UIImage] = allCases.reduce(into: [:]) { images, icon in
        if let url = Bundle.main.url(forResource: icon.previewName, withExtension: "png") {
            images[icon] = UIImage(contentsOfFile: url.path)
        }
    }

    var previewImage: Image {
        if let image = Self.filePreviews[self] { return Image(uiImage: image) }
        return Image(previewName)
    }
}

@MainActor @Observable
final class AppIconSelection {
    static let shared = AppIconSelection()
    private(set) var selected = MobileAppIcon(alternateName: UIApplication.shared.alternateIconName)
    private var changing = false

    func select(_ icon: MobileAppIcon) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, !changing, app.alternateIconName != icon.alternateName else { return }
        changing = true
        Task {
            defer { changing = false }
            do {
                try await app.setAlternateIconName(icon.alternateName)
            } catch {
                Logger().error("Could not change the app icon: \(error.localizedDescription, privacy: .public)")
            }
            selected = MobileAppIcon(alternateName: app.alternateIconName)
        }
    }
}
