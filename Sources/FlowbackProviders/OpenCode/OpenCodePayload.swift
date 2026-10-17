import Foundation

/// Incoming payload from the Flowback OpenCode plugin or OpenCode event stream
public struct OpenCodeHookPayload: Codable, Sendable {
    public let event: String?
    public let sessionId: String?
    public let session_id: String?
    public let projectId: String?
    public let directory: String?
    public let workspace: String?
    public let timestamp: String?
    public let status: String?
    public let tool: OpenCodeToolEvent?
    public let error: String?
    public let metadata: [String: String]?
    
    public init(
        event: String? = nil,
        sessionId: String? = nil,
        session_id: String? = nil,
        projectId: String? = nil,
        directory: String? = nil,
        workspace: String? = nil,
        timestamp: String? = nil,
        status: String? = nil,
        tool: OpenCodeToolEvent? = nil,
        error: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.event = event
        self.sessionId = sessionId
        self.session_id = session_id
        self.projectId = projectId
        self.directory = directory
        self.workspace = workspace
        self.timestamp = timestamp
        self.status = status
        self.tool = tool
        self.error = error
        self.metadata = metadata
    }
}

/// Tool invocation details from OpenCode plugin
public struct OpenCodeToolEvent: Codable, Sendable {
    public let name: String?
    public let callId: String?
    public let requiresPermission: Bool?
    public let status: String?
    
    public init(
        name: String? = nil,
        callId: String? = nil,
        requiresPermission: Bool? = nil,
        status: String? = nil
    ) {
        self.name = name
        self.callId = callId
        self.requiresPermission = requiresPermission
        self.status = status
    }
}
