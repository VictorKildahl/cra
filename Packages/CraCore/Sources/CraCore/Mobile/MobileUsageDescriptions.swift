import Foundation

/// The iPhone app's Info.plist usage descriptions, and what needs each. iOS ends an app on the spot when it reaches a
/// protected resource without a description, and some of these WebKit reaches on its own, from a page: "Save to
/// Photos" in a long-pressed image's menu (#713) and "Take Photo or Video" in a file upload's or a camera page's.
public enum MobileUsageDescriptions {
    /// Info.plist key → what asks for it.
    public static let required: [String: String] = [
        "NSPhotoLibraryAddUsageDescription": "WebKit's Save to Photos on a long-pressed image (#713)",
        "NSCameraUsageDescription": "WebKit's Take Photo or Video in a file upload, and a page's camera",
        "NSMicrophoneUsageDescription": "search by voice, and a page's microphone",
        "NSSpeechRecognitionUsageDescription": "search by voice",
    ]
}
