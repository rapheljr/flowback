import Foundation

/// System-level context and focus changes observed by Flowback
public enum FocusEventType: String, Codable, Sendable {
    case applicationLaunched = "system.app_launched"
    case applicationTerminated = "system.app_terminated"
    case frontmostChanged = "system.frontmost_changed"
    case windowChanged = "system.window_changed"
    case userActive = "system.user_active"
    case userIdle = "system.user_idle"
    case spaceChanged = "system.space_changed"
    case screenLocked = "system.screen_locked"
    case screenUnlocked = "system.screen_unlocked"
}

public struct FocusEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let timestamp: Date
    public let type: FocusEventType
    public let bundleIdentifier: String?
    public let processIdentifier: Int32?
    public let windowIdentifier: UInt32?
    public let windowTitle: String?
    public let idleSeconds: Double?
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        type: FocusEventType,
        bundleIdentifier: String? = nil,
        processIdentifier: Int32? = nil,
        windowIdentifier: UInt32? = nil,
        windowTitle: String? = nil,
        idleSeconds: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.windowIdentifier = windowIdentifier
        self.windowTitle = windowTitle
        self.idleSeconds = idleSeconds
        self.metadata = metadata
    }
}
