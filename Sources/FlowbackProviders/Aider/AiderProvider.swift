import Foundation
import FlowbackCore
import OSLog

public final class AiderProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.aider
    public let displayName = "Aider"
    public let isSupported = true
    
    public init() {}
    
    public func checkHealth() async -> ProviderHealth {
        ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: false,
            statusMessage: "Aider notification command integration available",
            isSupported: true,
            supportLevel: .adapter
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let sessionID = (json["session_id"] as? String) ?? UUID().uuidString
        let message = (json["message"] as? String) ?? "Agent updated"
        let workspace = json["workspace"] as? String
        
        return AgentEvent(
            providerID: providerID,
            sessionID: AgentSessionID(sessionID),
            type: .agentCompleted,
            workspace: workspace,
            metadata: ["message": message]
        )
    }
    
    public func installIntegration() async throws {}
    public func uninstallIntegration() async throws {}
}
