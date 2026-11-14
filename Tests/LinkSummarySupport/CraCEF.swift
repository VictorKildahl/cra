import Foundation

public final class CraPreviewRequest {
    public init() {}
    public func cancel() {}
}

// The production Swift transport is compiled unchanged; real CEF wire behavior is validated separately.
public enum CraCEFRuntime {
    public static func fetchPreviewURL(_ url: String, profilePath: String?, maximumBytes: UInt, timeout: TimeInterval,
                                      completion: (Int, String, String, String, String, UInt) -> Void) -> CraPreviewRequest {
        completion(0, url, "", "", "", 0)
        return CraPreviewRequest()
    }
}
