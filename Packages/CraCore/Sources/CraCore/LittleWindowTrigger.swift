import Foundation

/// Which clicked links open a Little Window because ⌥ and ⌘ were held (Arc's Settings ▸ Links "Open
/// Little Arc when clicking on links with ⌥⌘ held"). Only what a tab could show: a page's own address,
/// not another app's (spotify:), a file or Cra's scripting scheme.
public enum LittleWindowTrigger {
    public static func opens(_ url: String, optionCommand: Bool, settings: AppSettings) -> Bool {
        optionCommand && settings.littleWindowOnOptionCommandClick && SiteKey.site(of: url) != nil
    }
}
