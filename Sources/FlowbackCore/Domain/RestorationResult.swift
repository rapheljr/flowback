import Foundation

/// Specific outcome of an attempted session or conversation restoration operation
public enum RestorationOutcome: String, Codable, Sendable, CaseIterable {
    /// Successfully navigated directly to the exact conversation or thread
    case exactConversationRestored = "exact_conversation_restored"

    /// Successfully activated the target workspace and resumed/selected the intended conversation
    case workspaceAndConversationRestored = "workspace_and_conversation_restored"

    /// Activated workspace window matching project, without conversation selection
    case workspaceActivatedOnly = "workspace_activated_only"

    /// Activated terminal workspace and presented resume command or hint
    case resumeHintPresented = "resume_hint_presented"

    /// Successfully opened the provider web dashboard or pull request URL
    case providerURLOpened = "provider_url_opened"

    /// Activated the containing application or window only; exact conversation navigation is not supported
    case windowActivatedOnly = "window_activated_only"

    /// Multiple windows or workspaces matched and Flowback could not disambiguate safely
    case targetAmbiguous = "target_ambiguous"

    /// Target conversation or window is closed, stale, or no longer exists
    case conversationUnavailable = "conversation_unavailable"

    /// Restoration is not supported by the provider or current environment
    case restorationUnsupported = "restoration_unsupported"

    /// Restoration was attempted but encountered an error
    case restorationFailed = "restoration_failed"

    /// Restoration operation was cancelled or superseded by a newer navigation request
    case operationCancelled = "operation_cancelled"

    /// Restoration operation timed out waiting for window or application response
    case operationTimedOut = "operation_timed_out"

    /// System accessibility or automation permissions were denied
    case permissionDenied = "permission_denied"

    public var isSuccessful: Bool {
        switch self {
        case .exactConversationRestored,
             .workspaceAndConversationRestored,
             .workspaceActivatedOnly,
             .resumeHintPresented,
             .providerURLOpened,
             .windowActivatedOnly:
            return true
        case .targetAmbiguous,
             .conversationUnavailable,
             .restorationUnsupported,
             .restorationFailed,
             .operationCancelled,
             .operationTimedOut,
             .permissionDenied:
            return false
        }
    }

    public var isExactConversation: Bool {
        switch self {
        case .exactConversationRestored:
            return true
        default:
            return false
        }
    }

    public var userFacingLabel: String {
        switch self {
        case .exactConversationRestored:
            return "Restored exact conversation"
        case .workspaceAndConversationRestored:
            return "Restored workspace & conversation"
        case .workspaceActivatedOnly:
            return "Activated workspace window"
        case .resumeHintPresented:
            return "Activated terminal with resume hint"
        case .providerURLOpened:
            return "Opened provider destination URL"
        case .windowActivatedOnly:
            return "Activated application window (window-only fallback)"
        case .targetAmbiguous:
            return "Ambiguous target: multiple candidate windows match"
        case .conversationUnavailable:
            return "Conversation target unavailable or closed"
        case .restorationUnsupported:
            return "Restoration unsupported for this provider"
        case .restorationFailed:
            return "Restoration failed"
        case .operationCancelled:
            return "Navigation cancelled or superseded"
        case .operationTimedOut:
            return "Restoration timed out"
        case .permissionDenied:
            return "System permissions denied"
        }
    }
}

/// Structured result describing what was attempted, what succeeded, and what fallback was used
public struct RestorationResult: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let outcome: RestorationOutcome
    public let sessionID: AgentSessionID
    public let providerID: AgentProviderID
    public let conversationID: String?
    public let conversationTitle: String?
    public let targetDescription: String
    public let message: String
    public let fallbackUsed: String?
    public let executedAt: Date

    public init(
        id: String = UUID().uuidString,
        outcome: RestorationOutcome,
        sessionID: AgentSessionID,
        providerID: AgentProviderID,
        conversationID: String? = nil,
        conversationTitle: String? = nil,
        targetDescription: String,
        message: String,
        fallbackUsed: String? = nil,
        executedAt: Date = Date()
    ) {
        self.id = id
        self.outcome = outcome
        self.sessionID = sessionID
        self.providerID = providerID
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.targetDescription = targetDescription
        self.message = message
        self.fallbackUsed = fallbackUsed
        self.executedAt = executedAt
    }

    public var isSuccessful: Bool {
        outcome.isSuccessful
    }
}
