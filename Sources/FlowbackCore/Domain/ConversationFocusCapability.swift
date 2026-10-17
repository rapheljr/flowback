import Foundation

/// Capability level supported for restoring focus to an agent session
public enum ConversationFocusCapability: String, Codable, Sendable, CaseIterable {
    /// Documented and implemented ability to focus the intended conversation directly
    case exactConversation = "exact_conversation"

    /// Can select the workspace and resume or select the intended conversation
    case workspaceAndConversation = "workspace_and_conversation"

    /// Can open a provider-supported web dashboard or Pull Request URL
    case externalURL = "external_url"

    /// Can activate the containing application or window, but cannot navigate to the exact conversation
    case windowOnly = "window_only"

    /// Insufficient identity or restoration data to guarantee a useful restoration target
    case unavailable = "unavailable"

    public var displayLabel: String {
        switch self {
        case .exactConversation:
            return "Exact Conversation"
        case .workspaceAndConversation:
            return "Workspace & Conversation"
        case .externalURL:
            return "External URL"
        case .windowOnly:
            return "Window Only"
        case .unavailable:
            return "Unavailable"
        }
    }

    public var isExactRestorationSupported: Bool {
        self == .exactConversation
    }
}
