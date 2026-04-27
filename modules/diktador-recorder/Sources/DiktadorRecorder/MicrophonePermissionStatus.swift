/// Whether the running process has been granted macOS Microphone access.
public enum MicrophonePermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case undetermined
}
