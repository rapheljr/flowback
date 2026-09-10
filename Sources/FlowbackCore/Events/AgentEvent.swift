import Foundation

/// Specific type of agent lifecycle event
public enum AgentEventType: String, Codable, Sendable {
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
    case providerConnected = "provider.connected"
    case providerDisconnected = "provider.disconnected"
    
    public var mappedState: AgentState? {
        switch self {
        case .agentStarted: return .starting
        case .agentRunning, .agentProgress: return .running
        case .agentWaiting: return .waiting
        case .agentPermissionRequired: return .permissionRequired
        case .agentCompleted, .agentIdle: return .completed
        case .agentFailed: return .failed
        case .agentCancelled, .agentStopped: return .cancelled
        case .providerConnected, .providerDisconnected: return nil
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
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        providerID: AgentProviderID,
        sessionID: AgentSessionID,
        type: AgentEventType,
        workspace: String? = nil,
        origin: OriginContext? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.providerID = providerID
        self.sessionID = sessionID
        self.type = type
        self.workspace = workspace
        self.origin = origin
        self.metadata = metadata
    }
    
    /// Unique deduplication key for idempotency within short time windows
    public var deduplicationKey: String {
        let cleanWs = workspace ?? ""
        return "\(providerID.rawValue):\(sessionID.rawValue):\(type.rawValue):\(cleanWs)"
    }
}
