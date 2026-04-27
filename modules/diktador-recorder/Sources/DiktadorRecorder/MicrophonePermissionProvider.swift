import AVFoundation
import Foundation

internal protocol MicrophonePermissionProvider: Sendable {
    func currentStatus() -> MicrophonePermissionStatus
    func requestAccess(completion: @escaping (MicrophonePermissionStatus) -> Void)
}

/// Real provider that wraps `AVCaptureDevice.authorizationStatus(for:)` /
/// `AVCaptureDevice.requestAccess(for:)`. macOS shows the consent prompt at
/// most once per app-bundle / user pair; subsequent `requestAccess` calls
/// return the cached granted/denied state without re-prompting.
internal struct AVPermissionProvider: MicrophonePermissionProvider {
    func currentStatus() -> MicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    func requestAccess(completion: @escaping (MicrophonePermissionStatus) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted ? .granted : .denied)
            }
        }
    }
}
