import CraCore
import Foundation

/// The language Browse for Me, summaries and Translate answer in (App Settings ▸ Languages).
/// The browser sets `setting` whenever the settings change.
enum AnswerLanguage {
    static var setting: String?

    static var code: String { MobileLanguages.answerCode(setting: setting, preferred: Locale.preferredLanguages) }
    /// For the model's instructions, in English ("Danish").
    static var englishName: String { MobileLanguages.englishName(code) }
}
