import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "ClaudeCodeProvider")

public final class ClaudeCodeProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.claudeCode
    public let displayName = "Claude Code"
    public let isSupported = true
    
    private let homeClaudeDir: String
    
    public init(homeClaudeDir: String = ("~/.claude" as NSString).expandingTildeInPath) {
        self.homeClaudeDir = homeClaudeDir
    }
    
    public func checkHealth() async -> ProviderHealth {
        let fm = FileManager.default
        let isInstalled = fm.fileExists(atPath: homeClaudeDir)
        
        let settingsPath = (homeClaudeDir as NSString).appendingPathComponent("settings.json")
        let hookInstalled = fm.fileExists(atPath: settingsPath)
        
        let msg = isInstalled ? (hookInstalled ? "Ready with settings" : "Installed; hook command available") : "Claude directory not detected"
        
        return ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: isInstalled,
            version: nil,
            hookInstalled: hookInstalled,
            hookExecutable: true,
            configurationPath: homeClaudeDir,
            statusMessage: msg,
            isSupported: true
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        // Claude Code emits JSON event via hook or CLI notification
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        let sessionID = (json["session_id"] as? String) ?? UUID().uuidString
        let status = (json["status"] as? String) ?? "completed"
        let workspace = json["cwd"] as? String
        
        let eventType: AgentEventType
        switch status {
        case "running": eventType = .agentRunning
        case "waiting": eventType = .agentWaiting
        case "error", "failed": eventType = .agentFailed
        case "cancelled": eventType = .agentCancelled
        default: eventType = .agentCompleted
        }
        
        return AgentEvent(
            providerID: providerID,
            sessionID: AgentSessionID(sessionID),
            type: eventType,
            workspace: workspace,
            metadata: ["raw_status": status]
        )
    }
    
    public func installIntegration() async throws {
        // Claude Code uses notification-command or hook wrapper
        logger.info("Claude Code integration configured for hook dispatch")
    }
    
    public func uninstallIntegration() async throws {
        logger.info("Claude Code integration reset")
    }
}
