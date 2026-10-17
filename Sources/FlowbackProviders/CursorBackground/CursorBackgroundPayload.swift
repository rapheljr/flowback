import Foundation

/// Cursor Cloud Agents API models (v1)
public struct CursorCloudAgent: Codable, Sendable {
    public let id: String
    public let status: String?
    public let repository: String?
    public let repos: [CursorRepoInfo]?
    public let targetRef: String?
    public let branchName: String?
    public let prUrl: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let latestRunId: String?
    public let parentAgentId: String?
    public let summary: String?
    public let error: String?
    
    public init(
        id: String,
        status: String? = nil,
        repository: String? = nil,
        repos: [CursorRepoInfo]? = nil,
        targetRef: String? = nil,
        branchName: String? = nil,
        prUrl: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        latestRunId: String? = nil,
        parentAgentId: String? = nil,
        summary: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.status = status
        self.repository = repository
        self.repos = repos
        self.targetRef = targetRef
        self.branchName = branchName
        self.prUrl = prUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.latestRunId = latestRunId
        self.parentAgentId = parentAgentId
        self.summary = summary
        self.error = error
    }
}

public struct CursorRepoInfo: Codable, Sendable {
    public let url: String?
    public let startingRef: String?
    
    public init(url: String? = nil, startingRef: String? = nil) {
        self.url = url
        self.startingRef = startingRef
    }
}

public struct CursorAgentRun: Codable, Sendable {
    public let id: String
    public let agentId: String?
    public let status: String?
    public let createdAt: String?
    public let finishedAt: String?
    public let error: String?
    
    public init(
        id: String,
        agentId: String? = nil,
        status: String? = nil,
        createdAt: String? = nil,
        finishedAt: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.status = status
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.error = error
    }
}

public struct CursorListAgentsResponse: Codable, Sendable {
    public let agents: [CursorCloudAgent]?
    public let nextCursor: String?
    
    public init(agents: [CursorCloudAgent]? = nil, nextCursor: String? = nil) {
        self.agents = agents
        self.nextCursor = nextCursor
    }
}
