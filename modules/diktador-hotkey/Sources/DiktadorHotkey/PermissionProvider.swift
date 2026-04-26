import Foundation
import IOKit.hid

/// Internal seam over the IOKit Input-Monitoring access APIs so the registry
/// can be tested with a stub. Promote to `public` only when callers outside
/// the module need to substitute it (none in v1).
internal protocol PermissionProvider: Sendable {
    func currentStatus() -> InputMonitoringStatus
    func requestAccess(completion: @escaping (InputMonitoringStatus) -> Void)
}

/// Real provider that wraps `IOHIDCheckAccess` / `IOHIDRequestAccess`.
/// macOS shows the consent prompt at most once per app-bundle / user pair;
/// subsequent `requestAccess` calls return the cached granted/denied state.
internal struct IOHIDPermissionProvider: PermissionProvider {
    func currentStatus() -> InputMonitoringStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .undetermined
        }
    }

    func requestAccess(completion: @escaping (InputMonitoringStatus) -> Void) {
        // IOHIDRequestAccess is synchronous and may block long enough for the
        // user to respond to the prompt. Move it off the main thread; deliver
        // the resolved status back on main for UI consumers.
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            DispatchQueue.main.async {
                completion(granted ? .granted : .denied)
            }
        }
    }
}
