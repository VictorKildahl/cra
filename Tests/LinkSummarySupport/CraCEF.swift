import Foundation

// The production Swift transport is compiled unchanged; `answer` stands in for the engine's
// restricted fetch (redirects come back as their status with Location already resolved).
public enum CraCEFRuntime {
    public nonisolated(unsafe) static var answer: (String) -> (Int, String, String, String) = { (0, $0, "", "") }
    public nonisolated(unsafe) static var requests: [(url: String, accept: String?, profile: String?)] = []

    public static func fetchPluginURL(_ url: String, headers: [String: String]?, profilePath: String?,
                                      completion: @escaping (Int, String, String, String) -> Void) {
        requests.append((url, headers?["Accept"], profilePath))
        let (status, finalURL, mime, body) = answer(url)
        DispatchQueue.main.async { completion(status, finalURL, mime, body) }
    }
}
