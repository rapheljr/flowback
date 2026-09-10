import Foundation

/// Primary focus strategy applied when agent lifecycle changes occur
public enum FocusPolicyType: String, Codable, Sendable, CaseIterable {
    case smart = "smart"
    case alwaysRestore = "always-restore"
    case restoreIfUserLeftOrigin = "restore-if-left-origin"
    case notificationOnly = "notification-only"
    case neverInterrupt = "never-interrupt"
    
    public var displayName: String {
        switch self {
        case .smart: return "Smart (Recommended)"
        case .alwaysRestore: return "Always Restore"
        case .restoreIfUserLeftOrigin: return "Restore If User Left Origin"
        case .notificationOnly: return "Notification Only"
        case .neverInterrupt: return "Never Interrupt"
        }
    }
    
    public var description: String {
        switch self {
        case .smart:
            return "Analyzes user activity, idle state, and protected applications before deciding to switch focus or notify."
        case .alwaysRestore:
            return "Always returns focus to the origin context when an agent finishes, unless protected apps are frontmost."
        case .restoreIfUserLeftOrigin:
            return "Restores focus only if the user navigated to a different application after the agent started."
        case .notificationOnly:
            return "Never switches focus automatically. Shows actionable notifications with a [Focus] button."
        case .neverInterrupt:
            return "Complete quiet mode. No focus switches or notifications."
        }
    }
}

/// Action to take on successful agent completion
public enum CompletionBehavior: String, Codable, Sendable {
    case restoreOrigin = "restore-origin"
    case notificationOnly = "notification-only"
    case askUser = "ask-user"
}

/// Action to take when an agent requires user permission
public enum PermissionBehavior: String, Codable, Sendable {
    case focusAgent = "focus-agent"
    case notificationOnly = "notification-only"
}

/// Action to take when an agent fails
public enum FailureBehavior: String, Codable, Sendable {
    case focusAgent = "focus-agent"
    case notificationOnly = "notification-only"
}

/// Policy for handling macOS Spaces / Virtual Desktops
public enum SpacePolicy: String, Codable, Sendable, CaseIterable {
    case neverSwitchSpaces = "never-switch"
    case activateApplicationOnly = "app-only"
    case activateApplicationAndWindow = "app-and-window"
    case allowSpaceSwitching = "allow-switching"
    
    public var displayName: String {
        switch self {
        case .neverSwitchSpaces: return "Never Switch Spaces"
        case .activateApplicationOnly: return "Activate Application Only"
        case .activateApplicationAndWindow: return "Activate Application & Window"
        case .allowSpaceSwitching: return "Allow Space Switching"
        }
    }
}

/// Temporary Focus Lock state
public struct FocusLockState: Codable, Sendable {
    public var isActive: Bool
    public var expiresAt: Date?
    public var label: String?
    
    public init(isActive: Bool = false, expiresAt: Date? = nil, label: String? = nil) {
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.label = label
    }
    
    public var isCurrentlyLocked: Bool {
        guard isActive else { return false }
        if let exp = expiresAt {
            return exp > Date()
        }
        return true // Indefinite lock
    }
    
    public var remainingSeconds: TimeInterval? {
        guard let exp = expiresAt else { return nil }
        return max(0, exp.timeIntervalSince(Date()))
    }
}
