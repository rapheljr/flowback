import Foundation
import FlowbackCore
import OSLog

public final class GeminiCLIProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.geminiCLI
    public let displayName = "Gemini CLI"
    public let isSupported = true
    
    public init() {}
    
    public func checkHealth() async -> ProviderHealth {
        ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: false,
            statusMessage: "Gemini CLI integration ready via Flowback hook",
            isSupported: true
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let sessionID = (json["session_id"] as? String) ?? UUID().uuidString
        let status = (json["status"] as? String) ?? "completed"
        let workspace = json["workspace"] as? String
        
        let eventType: AgentEventType
        if status == "permission_required" {
            eventType = .agentPermissionRequired
        } else if status == "failed" {
            eventType = .agentFailed
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
