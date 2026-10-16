import Foundation
import FlowbackCore
import OSLog

public final class CodexProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.codex
    public let displayName = "OpenAI Codex"
    public let isSupported = true
    
    public init() {}
    
    public func checkHealth() async -> ProviderHealth {
        ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: false,
            version: nil,
            hookInstalled: false,
            hookExecutable: false,
            statusMessage: "Codex CLI integration ready via hook dispatcher",
            isSupported: true,
            supportLevel: .adapter
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let sessionID = (json["session_id"] as? String) ?? (json["id"] as? String) ?? UUID().uuidString
        let status = (json["state"] as? String) ?? (json["status"] as? String) ?? "completed"
        let workspace = json["workspace"] as? String
        
        let eventType: AgentEventType
        if status == "error" || status == "failed" {
            eventType = .agentFailed
        } else if status == "permission_required" {
            eventType = .agentPermissionRequired
        } else if status == "running" {
            eventType = .agentRunning
        } else {
            eventType = .agentCompleted
        }
        
        return AgentEvent(
            providerID: providerID,
            sessionID: AgentSessionID(sessionID),
            type: eventType,
            workspace: workspace,
            metadata: ["status": status]
        )
    }
    
    public func installIntegration() async throws {}
    public func uninstallIntegration() async throws {}
}
