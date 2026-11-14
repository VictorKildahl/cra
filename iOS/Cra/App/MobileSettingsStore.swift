import CraCore
import Foundation

/// `settings.json` in the app's data folder (`MobileSettings` in CraCore).
final class MobileSettingsStore {
    private let fileURL: URL
    private(set) var value: MobileSettings
    var onChange: (() -> Void)?

    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(MobileSettings.self, from: data) {
            value = loaded
        } else {
            value = MobileSettings()
        }
        AnswerLanguage.setting = value.answerLanguage
    }

    func update(_ change: (inout MobileSettings) -> Void) {
        var next = value
        change(&next)
        guard next != value else { return }
        value = next
        AnswerLanguage.setting = next.answerLanguage
        if let data = try? JSONEncoder().encode(next) { try? data.write(to: fileURL, options: .atomic) }
        onChange?()
    }
}
