import Foundation
import FlowbackCore
import OSLog

public final class CodexProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.codex
    public let displayName = "OpenAI Codex"
    public let isSupported = true

    public init() {}

    public func checkHealth() async -> ProviderHealth {
        let candidatePaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            ("~/.local/bin/codex" as NSString).expandingTildeInPath,
            "/usr/bin/codex"
        ]
        let detectedPath = candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        let isInstalled = detectedPath != nil
        let msg = isInstalled
            ? "Codex CLI detected at \(detectedPath ?? "codex"); ready via hook dispatcher"
            : "Codex CLI integration ready via hook dispatcher"

        return ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: isInstalled,
            version: nil,
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
        let sessionID = (json["session_id"] as? String) ?? (json["id"] as? String) ?? UUID().uuidString
        let status = ((json["state"] as? String) ?? (json["status"] as? String) ?? "running").lowercased()
        let workspace = json["workspace"] as? String

        let eventType: AgentEventType
        switch status {
        case "error", "failed":
            eventType = .agentFailed
        case "permission_required", "confirmation_required":
            eventType = .agentPermissionRequired
        case "running", "started", "in_progress":
            eventType = .agentRunning
        case "waiting", "paused", "idle":
            eventType = .agentWaiting
        case "cancelled", "aborted":
            eventType = .agentCancelled
        case "completed", "finished", "done", "success":
            eventType = .agentCompleted
        default:
            eventType = .agentRunning
        }

        let title = json["title"] as? String ?? json["prompt"] as? String ?? json["task"] as? String
        var metadata = ["status": status]
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
