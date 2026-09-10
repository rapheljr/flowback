import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "GenericHookProvider")

public struct GenericHookPayload: Codable, Sendable {
    public let schemaVersion: Int
    public let event: String
    public let provider: String
    public let sessionId: String
    public let taskId: String?
    public let workspace: String?
    public let timestamp: String?
    public let metadata: [String: String]?
    
    public init(
        schemaVersion: Int = 1,
        event: String,
        provider: String,
        sessionId: String,
        taskId: String? = nil,
        workspace: String? = nil,
        timestamp: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.provider = provider
        self.sessionId = sessionId
        self.taskId = taskId
        self.workspace = workspace
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public final class GenericHookProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.genericHook
    public let displayName = "Generic Hook Receiver"
    public let isSupported = true
    
    public init() {}
    
    public func checkHealth() async -> ProviderHealth {
        ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: true,
            hookInstalled: true,
            hookExecutable: true,
            statusMessage: "Universal JSON hook endpoint ready on Unix socket",
            isSupported: true
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(GenericHookPayload.self, from: data) else {
            logger.warning("Malformed generic hook payload rejected")
            return nil
        }
        
        guard payload.schemaVersion == 1 else {
            logger.warning("Unsupported generic hook schema version \(payload.schemaVersion)")
            return nil
        }
        
        let provID = AgentProviderID(payload.provider)
        let sessID = AgentSessionID(payload.sessionId)
        let eventType = AgentEventType(rawValue: payload.event) ?? .agentCompleted
        
        return AgentEvent(
            providerID: provID,
            sessionID: sessID,
            type: eventType,
            workspace: payload.workspace,
            metadata: payload.metadata ?? [:]
        )
    }
    
    public func installIntegration() async throws {}
    public func uninstallIntegration() async throws {}
}
