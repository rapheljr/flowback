import Foundation

/// Priority order for agent attention requests
public enum AttentionPriority: Int, Comparable, Codable, Sendable {
    case informational = 0
    case waiting = 1
    case completed = 2
    case failure = 3
    case permissionRequired = 4
    
    public static func < (lhs: AttentionPriority, rhs: AttentionPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    public var displayName: String {
        switch self {
        case .informational: return "Info"
        case .waiting: return "Waiting"
        case .completed: return "Completed"
        case .failure: return "Failure"
        case .permissionRequired: return "Permission Required"
        }
    }
}

/// Request for user attention generated when an agent transitions or completes
public struct AttentionRequest: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let sessionID: AgentSessionID
    public let providerID: AgentProviderID
    public let priority: AttentionPriority
    public let title: String
    public let message: String
    public let workspace: String?
    public let requestedAt: Date
    public var isProcessed: Bool
    
    public init(
        id: String = UUID().uuidString,
        sessionID: AgentSessionID,
        providerID: AgentProviderID,
        priority: AttentionPriority,
        title: String,
        message: String,
        workspace: String? = nil,
        requestedAt: Date = Date(),
        isProcessed: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.providerID = providerID
        self.priority = priority
        self.title = title
        self.message = message
        self.workspace = workspace
        self.requestedAt = requestedAt
        self.isProcessed = isProcessed
    }
}
