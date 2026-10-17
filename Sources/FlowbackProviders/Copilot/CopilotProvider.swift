import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "CopilotProvider")

/// Provider integration for GitHub Copilot CLI and agent sessions
public final class CopilotProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.copilot
    public let displayName = "GitHub Copilot"
    public let isSupported = true
    public let supportLevel = ProviderSupportLevel.adapter

    private let configDirectory: String

    public init(configDirectory: String = ("~/.copilot" as NSString).expandingTildeInPath) {
        self.configDirectory = configDirectory
    }

    public func checkHealth() async -> ProviderHealth {
        let fm = FileManager.default
        let configExists = fm.fileExists(atPath: configDirectory)
        let ghConfigExists = fm.fileExists(atPath: ("~/.config/github-copilot" as NSString).expandingTildeInPath)
        let isInstalled = configExists || ghConfigExists

        let statusMessage: String
        if isInstalled {
            statusMessage = "GitHub Copilot environment detected"
        } else {
            statusMessage = "GitHub Copilot configuration directory (~/.copilot) not detected"
        }

        return ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: isInstalled,
            statusMessage: statusMessage,
            isSupported: true,
            supportLevel: supportLevel
        )
    }

    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let sessionID = (json["session_id"] as? String)
            ?? (json["sessionId"] as? String)
            ?? (json["conversation_id"] as? String)
            ?? UUID().uuidString

        let rawStatus = ((json["status"] as? String)
            ?? (json["event"] as? String)
            ?? (json["type"] as? String)
            ?? "running").lowercased()

        let eventType: AgentEventType
        switch rawStatus {
        case "completed", "finished", "done", "success", "turn_completed":
            eventType = .agentCompleted
        case "error", "failed":
            eventType = .agentFailed
        case "cancelled", "stopped", "aborted":
            eventType = .agentCancelled
        case "waiting", "idle", "paused", "turn_waiting":
            eventType = .agentWaiting
        case "permission_required", "confirm", "confirmation_required":
            eventType = .agentPermissionRequired
        case "running", "started", "turn_start", "assistant.turn_start":
            eventType = .agentRunning
        default:
            eventType = .agentRunning
        }

        let title = (json["title"] as? String)
            ?? (json["prompt"] as? String)
            ?? (json["summary"] as? String)
            ?? (json["message"] as? String)

        let workspace = json["workspace"] as? String ?? json["cwd"] as? String

        var metadata: [String: String] = [
            "status": rawStatus
        ]
        if let model = json["model"] as? String {
            metadata["model"] = model
        }
        if let message = json["message"] as? String {
            metadata["message"] = message
        }

        return AgentEvent(
            providerID: providerID,
            sessionID: AgentSessionID(sessionID),
            type: eventType,
            workspace: workspace,
            metadata: metadata,
            conversationID: sessionID,
            conversationTitle: title,
            focusCapability: .windowOnly,
            isRemote: false
        )
    }

    public func resumeCommand(for session: AgentSession) -> String? {
        if let ws = session.workspace, !ws.isEmpty {
            return "cd \"\(ws)\" && gh copilot"
        }
        return "gh copilot"
    }

    public func installIntegration() async throws {}
    public func uninstallIntegration() async throws {}
}
