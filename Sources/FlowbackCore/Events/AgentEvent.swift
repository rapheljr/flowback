import Foundation

/// Specific type of agent lifecycle event
public enum AgentEventType: String, Codable, Sendable, CaseIterable {
    case agentStarted = "agent.started"
    case agentRunning = "agent.running"
    case agentWaiting = "agent.waiting"
    case agentPermissionRequired = "agent.permission_required"
    case agentProgress = "agent.progress"
    case agentCompleted = "agent.completed"
    case agentFailed = "agent.failed"
    case agentCancelled = "agent.cancelled"
    case agentStopped = "agent.stopped"
    case agentIdle = "agent.idle"
    case sessionContextChanged = "session.context_changed"
    case sessionDisappeared = "session.disappeared"
    case providerConnected = "provider.connected"
    case providerDisconnected = "provider.disconnected"
    case conversationTitleUpdated = "conversation.title_updated"

    public var mappedState: AgentState? {
        switch self {
        case .agentStarted: return .starting
        case .agentRunning, .agentProgress: return .running
        case .agentWaiting: return .waiting
        case .agentPermissionRequired: return .permissionRequired
        case .agentCompleted, .agentIdle: return .completed
        case .agentFailed: return .failed
        case .agentCancelled, .agentStopped, .sessionDisappeared: return .cancelled
        case .sessionContextChanged, .providerConnected, .providerDisconnected, .conversationTitleUpdated: return nil
        }
    }

    /// Determines whether the event requires focus arbitration evaluation or actionable attention
    public var isActionableForAttention: Bool {
        switch self {
        case .agentCompleted, .agentFailed, .agentPermissionRequired, .agentWaiting, .agentIdle:
            return true
        default:
            return false
        }
    }
}

/// Normalized agent event consumed by the Flowback EventBus
public struct AgentEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let timestamp: Date
    public let providerID: AgentProviderID
    public let sessionID: AgentSessionID
    public let type: AgentEventType
    public let workspace: String?
    public let origin: OriginContext?
    public let metadata: [String: String]

    // Conversation metadata
    public let conversationID: String?
    public let conversationTitle: String?
    public let taskSummary: String?
    public let executionID: String?
    public let parentSessionID: AgentSessionID?
    public let conversationURL: URL?
    public let focusCapability: ConversationFocusCapability?
    public let isRemote: Bool?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        providerID: AgentProviderID,
        sessionID: AgentSessionID,
        type: AgentEventType,
        workspace: String? = nil,
        origin: OriginContext? = nil,
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
        self.timestamp = timestamp
        self.providerID = providerID
        self.sessionID = sessionID
        self.type = type
        self.workspace = workspace
        self.origin = origin
        self.metadata = metadata

        self.conversationID = conversationID ?? metadata["conversationId"] ?? metadata["sessionId"]

        let cleanTitle = conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? metadata["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? metadata["conversation_title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.conversationTitle = (cleanTitle?.isEmpty == false) ? cleanTitle : nil

        let cleanSummary = taskSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? metadata["summary"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.taskSummary = (cleanSummary?.isEmpty == false) ? cleanSummary : nil

        self.executionID = executionID ?? metadata["executionId"] ?? metadata["latestRunId"]

        if let p = parentSessionID {
            self.parentSessionID = p
        } else if let pStr = metadata["parentSessionId"], !pStr.isEmpty {
            self.parentSessionID = AgentSessionID(pStr)
        } else {
            self.parentSessionID = nil
        }

        if let url = conversationURL {
            self.conversationURL = url
        } else if let uStr = metadata["conversationUrl"] ?? metadata["prUrl"], let parsed = URL(string: uStr) {
            self.conversationURL = parsed
        } else {
            self.conversationURL = nil
        }

        self.focusCapability = focusCapability
        self.isRemote = isRemote ?? (providerID == .cursorBackground)
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, providerID, sessionID, type, workspace, origin, metadata
        case conversationID, conversationTitle, taskSummary, executionID, parentSessionID, conversationURL, focusCapability, isRemote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.providerID = try container.decode(AgentProviderID.self, forKey: .providerID)
        self.sessionID = try container.decode(AgentSessionID.self, forKey: .sessionID)
        self.type = try container.decode(AgentEventType.self, forKey: .type)
        self.workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        self.origin = try container.decodeIfPresent(OriginContext.self, forKey: .origin)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]

        self.conversationID = try container.decodeIfPresent(String.self, forKey: .conversationID)
            ?? self.metadata["conversationId"] ?? self.metadata["sessionId"]

        let rawTitle = try container.decodeIfPresent(String.self, forKey: .conversationTitle)
            ?? self.metadata["title"] ?? self.metadata["conversation_title"]
        let cleanTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.conversationTitle = (cleanTitle?.isEmpty == false) ? cleanTitle : nil

        let rawSummary = try container.decodeIfPresent(String.self, forKey: .taskSummary) ?? self.metadata["summary"]
        let cleanSummary = rawSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.taskSummary = (cleanSummary?.isEmpty == false) ? cleanSummary : nil

        self.executionID = try container.decodeIfPresent(String.self, forKey: .executionID)
            ?? self.metadata["executionId"] ?? self.metadata["latestRunId"]

        if let parentStr = try container.decodeIfPresent(String.self, forKey: .parentSessionID) ?? self.metadata["parentSessionId"] {
            self.parentSessionID = AgentSessionID(parentStr)
        } else {
            self.parentSessionID = nil
        }

        if let url = try container.decodeIfPresent(URL.self, forKey: .conversationURL) {
            self.conversationURL = url
        } else if let uStr = self.metadata["conversationUrl"] ?? self.metadata["prUrl"], let parsed = URL(string: uStr) {
            self.conversationURL = parsed
        } else {
            self.conversationURL = nil
        }

        self.focusCapability = try container.decodeIfPresent(ConversationFocusCapability.self, forKey: .focusCapability)
        self.isRemote = try container.decodeIfPresent(Bool.self, forKey: .isRemote) ?? (self.providerID == .cursorBackground)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(workspace, forKey: .workspace)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(conversationID, forKey: .conversationID)
        try container.encodeIfPresent(conversationTitle, forKey: .conversationTitle)
        try container.encodeIfPresent(taskSummary, forKey: .taskSummary)
        try container.encodeIfPresent(executionID, forKey: .executionID)
        try container.encodeIfPresent(parentSessionID?.rawValue, forKey: .parentSessionID)
        try container.encodeIfPresent(conversationURL, forKey: .conversationURL)
        try container.encodeIfPresent(focusCapability, forKey: .focusCapability)
        try container.encodeIfPresent(isRemote, forKey: .isRemote)
    }

    /// Unique deduplication key for idempotency within short time windows
    public var deduplicationKey: String {
        if let custom = metadata["deduplicationKey"], !custom.isEmpty {
            return custom
        }
        let cleanWs = workspace ?? ""
        let convPart = conversationID ?? sessionID.rawValue
        return "\(providerID.rawValue):\(convPart):\(type.rawValue):\(cleanWs)"
    }
}
