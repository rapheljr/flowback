import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "AntigravityProvider")

public final class AntigravityProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.antigravity
    public let displayName = "Google Antigravity"
    public let isSupported = true
    
    private let globalConfigPath: String
    private let appBundlePath: String
    
    public init(
        globalConfigPath: String = ("~/.gemini/config" as NSString).expandingTildeInPath,
        appBundlePath: String = "/Applications/Antigravity IDE.app"
    ) {
        self.globalConfigPath = globalConfigPath
        self.appBundlePath = appBundlePath
    }
    
    public func checkHealth() async -> ProviderHealth {
        let fm = FileManager.default
        let appExists = fm.fileExists(atPath: appBundlePath)
        let configExists = fm.fileExists(atPath: globalConfigPath)
        let isInstalled = appExists || configExists
        
        let hooksPath = (globalConfigPath as NSString).appendingPathComponent("hooks.json")
        var hookInstalled = false
        let hookExecutable = true
        
        if fm.fileExists(atPath: hooksPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            hookInstalled = json["flowback-agent-focus"] != nil
        }
        
        var version: String? = nil
        if appExists {
            let infoPlistPath = (appBundlePath as NSString).appendingPathComponent("Contents/Info.plist")
            if let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
                version = plist["CFBundleShortVersionString"] as? String
            }
        }
        
        let statusMessage: String
        if !isInstalled {
            statusMessage = "Antigravity not detected on system"
        } else if !hookInstalled {
            statusMessage = "Installed, but Flowback hook not configured in hooks.json"
        } else {
            statusMessage = "Integration active and healthy"
        }
        
        return ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: isInstalled,
            version: version,
            hookInstalled: hookInstalled,
            hookExecutable: hookExecutable,
            configurationPath: hooksPath,
            statusMessage: statusMessage,
            isSupported: true
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(AntigravityStopPayload.self, from: data) else {
            logger.warning("Could not decode Antigravity stop payload")
            return nil
        }
        
        let primaryWorkspace = payload.workspacePaths?.first
        var metadata: [String: String] = [
            "conversationId": payload.conversationId,
            "terminationReason": payload.terminationReason ?? "unknown",
            "modelName": payload.modelName ?? "auto"
        ]
        
        if let execNum = payload.executionNum {
            metadata["executionNum"] = "\(execNum)"
        }
        if let err = payload.error, !err.isEmpty {
            metadata["error"] = err
        }
        if let fullyIdle = payload.fullyIdle {
            metadata["fullyIdle"] = "\(fullyIdle)"
        }
        
        let eventType: AgentEventType
        if let err = payload.error, !err.isEmpty {
            eventType = .agentFailed
        } else if payload.fullyIdle == true {
            eventType = .agentCompleted
        } else {
            // Stop fired, but background tasks are still running
            eventType = .agentRunning
        }
        
        return AgentEvent(
            timestamp: Date(),
            providerID: providerID,
            sessionID: AgentSessionID(payload.conversationId),
            type: eventType,
            workspace: primaryWorkspace,
            metadata: metadata
        )
    }
    
    public func installIntegration() async throws {
        let fm = FileManager.default
        let hooksPath = (globalConfigPath as NSString).appendingPathComponent("hooks.json")
        
        // Ensure config directory exists
        try fm.createDirectory(atPath: globalConfigPath, withIntermediateDirectories: true)
        
        var hooksDict: [String: Any] = [:]
        if fm.fileExists(atPath: hooksPath) {
            // Backup existing hooks
            let backupPath = "\(hooksPath).bak.\(Int(Date().timeIntervalSince1970))"
            try? fm.copyItem(atPath: hooksPath, toPath: backupPath)
            
            if let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                hooksDict = existing
            }
        }
        
        // Define Flowback hook block
        let flowbackHook: [String: Any] = [
            "enabled": true,
            "Stop": [
                [
                    "type": "command",
                    "command": "flowback hook antigravity",
                    "timeout": 5
                ]
            ]
        ]
        
        hooksDict["flowback-agent-focus"] = flowbackHook
        
        let outputData = try JSONSerialization.data(withJSONObject: hooksDict, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: hooksPath))
        logger.info("Successfully installed Flowback Stop hook to \(hooksPath)")
    }
    
    public func uninstallIntegration() async throws {
        let fm = FileManager.default
        let hooksPath = (globalConfigPath as NSString).appendingPathComponent("hooks.json")
        guard fm.fileExists(atPath: hooksPath) else { return }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
              var hooksDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        if hooksDict.removeValue(forKey: "flowback-agent-focus") != nil {
            let outputData = try JSONSerialization.data(withJSONObject: hooksDict, options: [.prettyPrinted, .sortedKeys])
            try outputData.write(to: URL(fileURLWithPath: hooksPath))
            logger.info("Removed Flowback hook from \(hooksPath)")
        }
    }
}
