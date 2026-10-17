import Foundation

/// Primary abstraction representing an active or completed AI agent working session or conversation
public struct AgentSession: Identifiable, Codable, Hashable, Sendable {
    public let id: AgentSessionID
    public let providerID: AgentProviderID
    public let providerSessionID: String?
    public var state: AgentState
    public var taskID: AgentTaskID?
    public var workspace: String?
    public var originContext: OriginContext?
    public let startedAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var errorDescription: String?
    public var metadata: [String: String]

    // Conversation-Aware Identity & Metadata
    public var conversationID: String?
    public var conversationTitle: String?
    public var taskSummary: String?
    public var executionID: String?
    public var parentSessionID: AgentSessionID?
    public var conversationURL: URL?
    public var focusCapability: ConversationFocusCapability
    public var isRemote: Bool

    public init(
        id: AgentSessionID = AgentSessionID(),
        providerID: AgentProviderID,
        providerSessionID: String? = nil,
        state: AgentState = .starting,
        taskID: AgentTaskID? = nil,
        workspace: String? = nil,
        originContext: OriginContext? = nil,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        errorDescription: String? = nil,
        metadata: [String: String] = [:],
        conversationID: String? = nil,
        conversationTitle: String? = nil,
        taskSummary: String? = nil,
        executionID: String? = nil,
        parentSessionID: AgentSessionID? = nil,
        conversationURL: URL? = nil,
        focusCapability: ConversationFocusCapability? = nil,
        isRemote: Bool? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.providerSessionID = providerSessionID ?? conversationID
        self.state = state
        self.taskID = taskID
        self.workspace = workspace
        self.originContext = originContext
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.errorDescription = errorDescription
        self.metadata = metadata

        self.conversationID = conversationID ?? providerSessionID

        // Sanitize incoming conversation title: empty or whitespace-only is treated as nil
        let cleanTitle = conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.conversationTitle = (cleanTitle?.isEmpty == false) ? cleanTitle : nil

        let cleanSummary = taskSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.taskSummary = (cleanSummary?.isEmpty == false) ? cleanSummary : nil

        self.executionID = executionID
        self.parentSessionID = parentSessionID
        self.conversationURL = conversationURL

        let defaultRemote = (providerID == .cursorBackground)
        self.isRemote = isRemote ?? defaultRemote

        if let cap = focusCapability {
            self.focusCapability = cap
        } else if providerID == .cursorBackground {
            self.focusCapability = .externalURL
        } else if providerID == .antigravityCLI || providerID == .claudeCode {
            self.focusCapability = .workspaceAndConversation
        } else {
            self.focusCapability = .windowOnly
        }
    }

    // MARK: - Backwards-Compatible Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case id
        case providerID
        case providerSessionID
        case state
        case taskID
        case workspace
        case originContext
        case startedAt
        case updatedAt
        case completedAt
        case errorDescription
        case metadata
        case conversationID
        case conversationTitle
        case taskSummary
        case executionID
        case parentSessionID
        case conversationURL
        case focusCapability
        case isRemote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(AgentSessionID.self, forKey: .id)
        self.providerID = try container.decode(AgentProviderID.self, forKey: .providerID)
        self.providerSessionID = try container.decodeIfPresent(String.self, forKey: .providerSessionID)
        self.state = try container.decode(AgentState.self, forKey: .state)
        self.taskID = try container.decodeIfPresent(AgentTaskID.self, forKey: .taskID)
        self.workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        self.originContext = try container.decodeIfPresent(OriginContext.self, forKey: .originContext)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]

        // Decode new fields with robust fallbacks
        let rawConvId = try container.decodeIfPresent(String.self, forKey: .conversationID)
        self.conversationID = rawConvId ?? self.providerSessionID ?? self.metadata["conversationId"] ?? self.metadata["sessionId"]

        let rawTitle = try container.decodeIfPresent(String.self, forKey: .conversationTitle) ?? self.metadata["title"] ?? self.metadata["conversation_title"]
        let cleanTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.conversationTitle = (cleanTitle?.isEmpty == false) ? cleanTitle : nil

        let rawSummary = try container.decodeIfPresent(String.self, forKey: .taskSummary) ?? self.metadata["summary"]
        let cleanSummary = rawSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.taskSummary = (cleanSummary?.isEmpty == false) ? cleanSummary : nil

        self.executionID = try container.decodeIfPresent(String.self, forKey: .executionID) ?? self.metadata["executionId"] ?? self.metadata["latestRunId"]

        if let parentStr = try container.decodeIfPresent(String.self, forKey: .parentSessionID) ?? self.metadata["parentSessionId"] {
            self.parentSessionID = AgentSessionID(parentStr)
        } else {
            self.parentSessionID = nil
        }

        if let url = try container.decodeIfPresent(URL.self, forKey: .conversationURL) {
            self.conversationURL = url
        } else if let urlStr = self.metadata["conversationUrl"] ?? self.metadata["prUrl"], let parsed = URL(string: urlStr) {
            self.conversationURL = parsed
        } else {
            self.conversationURL = nil
        }

        let decodedRemote = try container.decodeIfPresent(Bool.self, forKey: .isRemote)
        self.isRemote = decodedRemote ?? (self.providerID == .cursorBackground)

        if let cap = try container.decodeIfPresent(ConversationFocusCapability.self, forKey: .focusCapability) {
            self.focusCapability = cap
        } else if self.providerID == .cursorBackground {
            self.focusCapability = .externalURL
        } else if self.providerID == .antigravityCLI || self.providerID == .claudeCode {
            self.focusCapability = .workspaceAndConversation
        } else {
            self.focusCapability = .windowOnly
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(providerID, forKey: .providerID)
        try container.encodeIfPresent(providerSessionID, forKey: .providerSessionID)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(taskID, forKey: .taskID)
        try container.encodeIfPresent(workspace, forKey: .workspace)
        try container.encodeIfPresent(originContext, forKey: .originContext)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(errorDescription, forKey: .errorDescription)
        try container.encode(metadata, forKey: .metadata)

        try container.encodeIfPresent(conversationID, forKey: .conversationID)
        try container.encodeIfPresent(conversationTitle, forKey: .conversationTitle)
        try container.encodeIfPresent(taskSummary, forKey: .taskSummary)
        try container.encodeIfPresent(executionID, forKey: .executionID)
        try container.encodeIfPresent(parentSessionID?.rawValue, forKey: .parentSessionID)
        try container.encodeIfPresent(conversationURL, forKey: .conversationURL)
        try container.encode(focusCapability, forKey: .focusCapability)
        try container.encode(isRemote, forKey: .isRemote)
    }

    // MARK: - Display Helpers

    public var duration: TimeInterval {
        let end = completedAt ?? updatedAt
        return max(0, end.timeIntervalSince(startedAt))
    }

    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }

    public var projectName: String {
        if let ws = workspace, !ws.isEmpty {
            return (ws as NSString).lastPathComponent
        }
        if let origin = originContext?.workspacePath, !origin.isEmpty {
            return (origin as NSString).lastPathComponent
        }
        return "Unknown Project"
    }

    /// Primary human-readable title for the conversation
    public var displayTitle: String {
        if let title = conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let summary = taskSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        if projectName != "Unknown Project" {
            return projectName
        }
        return "Untitled conversation"
    }

    /// Human-friendly display name of the provider
    public var providerDisplayName: String {
        switch providerID {
        case .antigravity:
            return "Google Antigravity"
        case .antigravityCLI:
            return "Antigravity CLI"
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "OpenAI Codex"
        case .aider:
            return "Aider"
        case .openCode:
            return "OpenCode"
        case .windsurf:
            return "Windsurf"
        case .cursorBackground:
            return "Cursor Background Agent"
        case .genericHook:
            return "Generic Hook"
        default:
            return providerID.rawValue.capitalized
        }
    }
}
