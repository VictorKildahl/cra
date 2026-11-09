import AVFoundation

/// What macOS has said about Cra using the camera and microphone, for cra.log (#286). Reading
/// it asks nothing: macOS's own question comes up only when a page opens the device.
enum CaptureAccess {
    static var camera: PermissionAsk.DeviceAccess { access(.video) }
    static var microphone: PermissionAsk.DeviceAccess { access(.audio) }

    private static func access(_ media: AVMediaType) -> PermissionAsk.DeviceAccess {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notAsked
        @unknown default: return .notAsked
        }
    }
}
