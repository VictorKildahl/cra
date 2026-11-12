import Foundation

// LinkSummaryService is compiled unchanged; real CEF transport behavior is validated separately.
public enum CraCEFRuntime {
    public static func fetchURL(_ url: String, headers: [String: String], profilePath: String?,
                                completion: (Int, String, String, String) -> Void) {
        completion(0, url, "", "")
    }
}
