import Foundation

/// Primary abstraction representing an active or completed AI agent working session
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
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.providerID = providerID
        self.providerSessionID = providerSessionID
        self.state = state
        self.taskID = taskID
        self.workspace = workspace
        self.originContext = originContext
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.errorDescription = errorDescription
        self.metadata = metadata
    }
    
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
}
