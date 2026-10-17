import Foundation

/// Incoming JSON payload from Windsurf Cascade hooks via stdin
public struct WindsurfHookPayload: Codable, Sendable {
    public let agent_action_name: String?
    public let trajectory_id: String?
    public let execution_id: String?
    public let step_index: Int?
    public let timestamp: String?
    public let workspace_root: String?
    public let model_name: String?
    public let tool_info: WindsurfToolInfo?
    public let error: String?
    
    public init(
        agent_action_name: String? = nil,
        trajectory_id: String? = nil,
        execution_id: String? = nil,
        step_index: Int? = nil,
        timestamp: String? = nil,
        workspace_root: String? = nil,
        model_name: String? = nil,
        tool_info: WindsurfToolInfo? = nil,
        error: String? = nil
    ) {
        self.agent_action_name = agent_action_name
        self.trajectory_id = trajectory_id
        self.execution_id = execution_id
        self.step_index = step_index
        self.timestamp = timestamp
        self.workspace_root = workspace_root
        self.model_name = model_name
        self.tool_info = tool_info
        self.error = error
    }
}

/// Tool/action context details embedded inside Cascade hook payloads
public struct WindsurfToolInfo: Codable, Sendable {
    public let prompt: String?
    public let response: String?
    public let transcript_path: String?
    public let command: String?
    public let path: String?
    public let error: String?
    public let workspace: String?
    public let requires_confirmation: Bool?
    public let decision: String?
    
    public init(
        prompt: String? = nil,
        response: String? = nil,
        transcript_path: String? = nil,
        command: String? = nil,
        path: String? = nil,
        error: String? = nil,
        workspace: String? = nil,
        requires_confirmation: Bool? = nil,
        decision: String? = nil
    ) {
        self.prompt = prompt
        self.response = response
        self.transcript_path = transcript_path
        self.command = command
        self.path = path
        self.error = error
        self.workspace = workspace
        self.requires_confirmation = requires_confirmation
        self.decision = decision
    }
}
