import Foundation
import FlowbackCore
import OSLog

public final class AiderProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.aider
    public let displayName = "Aider"
    public let isSupported = true

    public init() {}

    public func checkHealth() async -> ProviderHealth {
        let candidatePaths = [
            "/opt/homebrew/bin/aider",
            "/usr/local/bin/aider",
            ("~/.local/bin/aider" as NSString).expandingTildeInPath,
            "/usr/bin/aider"
        ]
        let detectedPath = candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        let isInstalled = detectedPath != nil
        let msg = isInstalled
            ? "Aider CLI detected at \(detectedPath ?? "aider"); notification command integration available"
            : "Aider notification command integration available"

        return ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: isInstalled,
            hookInstalled: isInstalled,
            hookExecutable: isInstalled,
            configurationPath: detectedPath,
            statusMessage: msg,
            isSupported: true,
            supportLevel: .adapter
        )
    }

    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let sessionID = (json["session_id"] as? String) ?? UUID().uuidString
        let message = (json["message"] as? String) ?? "Agent updated"
        let workspace = json["workspace"] as? String

        let rawStatus = ((json["status"] as? String) ?? (json["event"] as? String) ?? (json["state"] as? String) ?? "running").lowercased()
        let eventType: AgentEventType
        switch rawStatus {
        case "completed", "finished", "done", "success":
            eventType = .agentCompleted
        case "error", "failed":
            eventType = .agentFailed
        case "cancelled", "stopped", "aborted":
            eventType = .agentCancelled
        case "waiting", "idle", "paused":
            eventType = .agentWaiting
        case "permission_required", "confirm", "confirmation_required":
            eventType = .agentPermissionRequired
        case "running", "started", "prompt":
            eventType = .agentRunning
        default:
            eventType = .agentRunning
        }

        let title = json["title"] as? String ?? json["prompt"] as? String ?? json["message"] as? String
        var metadata = ["message": message, "status": rawStatus]
        if let t = title, !t.isEmpty { metadata["title"] = t }

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

    public func installIntegration() async throws {}
    public func uninstallIntegration() async throws {}
}
