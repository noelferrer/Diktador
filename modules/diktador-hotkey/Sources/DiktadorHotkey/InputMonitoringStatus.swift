/// Whether the running process has been granted macOS Input Monitoring access.
/// Required for `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` to
/// receive events while another app is frontmost.
public enum InputMonitoringStatus: Sendable, Equatable {
    case granted
    case denied
    case undetermined
}
