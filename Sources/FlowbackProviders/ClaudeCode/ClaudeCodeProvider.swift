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
            isSupported: true,
            supportLevel: .adapter
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

        let convTitle = json["title"] as? String ?? json["prompt"] as? String ?? json["task"] as? String
        var metadata = ["raw_status": status]
        if let t = convTitle, !t.isEmpty { metadata["title"] = t }

        return AgentEvent(
            providerID: providerID,
            sessionID: AgentSessionID(sessionID),
            type: eventType,
            workspace: workspace,
            metadata: metadata,
            conversationID: sessionID,
            conversationTitle: convTitle,
            focusCapability: .workspaceAndConversation,
            isRemote: false
        )
    }

    public func installIntegration() async throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: homeClaudeDir, withIntermediateDirectories: true)
        let settingsPath = (homeClaudeDir as NSString).appendingPathComponent("settings.json")

        var settingsDict: [String: Any] = [:]
        if fm.fileExists(atPath: settingsPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settingsDict = existing
        }

        let cmd = "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; flowback hook claude-code"
        var hooks = (settingsDict["hooks"] as? [String: Any]) ?? [:]
        hooks["Stop"] = [
            [
                "type": "command",
                "command": cmd
            ]
        ]
        settingsDict["hooks"] = hooks

        let outputData = try JSONSerialization.data(withJSONObject: settingsDict, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        logger.info("Claude Code integration configured in \(settingsPath)")
    }

    public func uninstallIntegration() async throws {
        let fm = FileManager.default
        let settingsPath = (homeClaudeDir as NSString).appendingPathComponent("settings.json")
        guard fm.fileExists(atPath: settingsPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              var settingsDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settingsDict["hooks"] as? [String: Any] else {
            return
        }

        if let stopEntries = hooks["Stop"] as? [[String: Any]] {
            let filtered = stopEntries.filter { ($0["command"] as? String)?.contains("flowback hook claude-code") != true }
            if filtered.isEmpty {
                hooks.removeValue(forKey: "Stop")
            } else {
                hooks["Stop"] = filtered
            }
            if hooks.isEmpty {
                settingsDict.removeValue(forKey: "hooks")
            } else {
                settingsDict["hooks"] = hooks
            }
            let outputData = try JSONSerialization.data(withJSONObject: settingsDict, options: [.prettyPrinted, .sortedKeys])
            try outputData.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        }
        logger.info("Claude Code integration reset")
    }

    public func resumeCommand(for session: AgentSession) -> String? {
        guard let convID = session.conversationID ?? session.providerSessionID, !convID.isEmpty else {
            return nil
        }
        let formattedID = convID.contains(" ") ? "\"\(convID)\"" : convID
        return "claude resume \(formattedID)"
    }
}
