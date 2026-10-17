import Foundation
import AppKit
import CoreGraphics
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "WindsurfProvider")

public final class WindsurfProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.windsurf
    public let displayName = "Windsurf"
    public let isSupported = true
    public let supportLevel = ProviderSupportLevel.nativeLifecycle
    
    private let globalConfigDir: String
    private let appBundlePath: String
    private let transcriptsDirs: [String]?
    
    public init(
        globalConfigDir: String = ("~/.codeium/windsurf" as NSString).expandingTildeInPath,
        appBundlePath: String = "/Applications/Windsurf.app",
        transcriptsDirs: [String]? = nil
    ) {
        self.globalConfigDir = globalConfigDir
        self.appBundlePath = appBundlePath
        self.transcriptsDirs = transcriptsDirs
    }
    
    public func checkHealth() async -> ProviderHealth {
        let fm = FileManager.default
        let appExists = fm.fileExists(atPath: appBundlePath)
        let configExists = fm.fileExists(atPath: globalConfigDir)
        let isInstalled = appExists || configExists
        
        let hooksPath = (globalConfigDir as NSString).appendingPathComponent("hooks.json")
        var hookInstalled = false
        let hookExecutable = true
        
        if fm.fileExists(atPath: hooksPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hooks = json["hooks"] as? [String: Any] {
            // Check if any Cascade hook points to flowback
            for (_, hookList) in hooks {
                if let arr = hookList as? [[String: Any]] {
                    if arr.contains(where: { ($0["command"] as? String)?.contains("flowback hook windsurf") == true }) {
                        hookInstalled = true
                        break
                    }
                }
            }
        }
        
        var version: String?
        if appExists {
            let infoPlistPath = (appBundlePath as NSString).appendingPathComponent("Contents/Info.plist")
            if let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
                version = plist["CFBundleShortVersionString"] as? String
            }
        }
        
        let statusMessage: String
        if !isInstalled {
            statusMessage = "Windsurf not detected on system"
        } else if !hookInstalled {
            statusMessage = "Windsurf detected, but Cascade hooks not configured in ~/.codeium/windsurf/hooks.json"
        } else {
            statusMessage = "Native Cascade hook integration active and healthy"
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
            isSupported: true,
            supportLevel: .nativeLifecycle
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(WindsurfHookPayload.self, from: data) else {
            logger.warning("Could not decode Windsurf Cascade hook payload")
            return nil
        }
        
        let trajectoryId = payload.trajectory_id ?? UUID().uuidString
        let actionName = payload.agent_action_name ?? "unknown"
        let execId = payload.execution_id
        let workspaceRoot = payload.workspace_root ?? payload.tool_info?.workspace
        
        var metadata: [String: String] = [
            "trajectoryId": trajectoryId,
            "actionName": actionName,
            "modelName": payload.model_name ?? "cascade"
        ]
        
        if let eid = execId {
            metadata["executionId"] = eid
        }
        if let step = payload.step_index {
            metadata["stepIndex"] = "\(step)"
        }
        if let err = payload.error ?? payload.tool_info?.error, !err.isEmpty {
            metadata["error"] = err
        }
        if let cmd = payload.tool_info?.command {
            metadata["command"] = String(cmd.prefix(120))
        }
        
        // Custom deduplication key for Cascade hooks: trajectory:action:execId
        metadata["deduplicationKey"] = "windsurf:\(trajectoryId):\(actionName):\(execId ?? "")"
        
        let eventType: AgentEventType
        let actionLower = actionName.lowercased()
        
        if let err = metadata["error"], !err.isEmpty {
            eventType = .agentFailed
        } else if actionLower == "pre_user_prompt" {
            eventType = (payload.step_index == nil || payload.step_index == 1) ? .agentStarted : .agentRunning
        } else if actionLower == "post_cascade_response" || actionLower == "post_cascade_response_with_transcript" {
            eventType = .agentCompleted
        } else if payload.tool_info?.requires_confirmation == true {
            eventType = .agentPermissionRequired
        } else if actionLower.hasPrefix("post_") {
            eventType = .agentProgress
        } else {
            eventType = .agentRunning
        }
        
        // Resolve Origin Context for Windsurf (bundle: com.codeium.windsurf)
        var origin: OriginContext?
        let targetBundle = "com.codeium.windsurf"
        if let ws = workspaceRoot {
            let folderName = (ws as NSString).lastPathComponent
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetBundle }) {
                var winID: UInt32?
                var winTitle = "\(folderName) — Windsurf"
                if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                    for win in windowList {
                        let pid = win[kCGWindowOwnerPID as String] as? Int32 ?? 0
                        let title = win[kCGWindowName as String] as? String ?? ""
                        if pid == app.processIdentifier && (title.localizedCaseInsensitiveContains(folderName) || title.localizedCaseInsensitiveContains("Windsurf")) {
                            winID = win[kCGWindowNumber as String] as? UInt32
                            winTitle = title
                            break
                        }
                    }
                }
                origin = OriginContext(
                    bundleIdentifier: app.bundleIdentifier ?? targetBundle,
                    processIdentifier: app.processIdentifier,
                    windowIdentifier: winID,
                    windowTitle: winTitle,
                    workspacePath: ws,
                    provenance: .nativeHook,
                    confidence: 1.0,
                    restorationCapability: .exactWindowAndWorkspace
                )
            }
        }
        
        return AgentEvent(
            timestamp: Date(),
            providerID: providerID,
            sessionID: AgentSessionID(trajectoryId),
            type: eventType,
            workspace: workspaceRoot,
            origin: origin,
            metadata: metadata
        )
    }
    
    public func installIntegration() async throws {
        let fm = FileManager.default
        let hooksPath = (globalConfigDir as NSString).appendingPathComponent("hooks.json")
        
        try fm.createDirectory(atPath: globalConfigDir, withIntermediateDirectories: true)
        
        var rootDict: [String: Any] = [:]
        if fm.fileExists(atPath: hooksPath) {
            let backupPath = "\(hooksPath).bak.\(Int(Date().timeIntervalSince1970))"
            try? fm.copyItem(atPath: hooksPath, toPath: backupPath)
            
            if let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rootDict = existing
            }
        }
        
        var hooksDict = rootDict["hooks"] as? [String: Any] ?? [:]
        
        let hookCommand = "export PATH=\"$HOME/.local/bin:/usr/local/bin:$PATH\"; flowback hook windsurf"
        let hookEntry: [String: Any] = [
            "command": hookCommand,
            "show_output": false
        ]
        
        let lifecycleEvents = [
            "pre_user_prompt",
            "post_cascade_response",
            "post_cascade_response_with_transcript",
            "pre_run_command",
            "post_run_command",
            "pre_write_code",
            "post_write_code",
            "pre_mcp_tool_use",
            "post_mcp_tool_use"
        ]
        
        for event in lifecycleEvents {
            var existingList = hooksDict[event] as? [[String: Any]] ?? []
            let alreadyInstalled = existingList.contains { ($0["command"] as? String)?.contains("flowback hook windsurf") == true }
            if !alreadyInstalled {
                existingList.append(hookEntry)
                hooksDict[event] = existingList
            }
        }
        
        rootDict["hooks"] = hooksDict
        let outputData = try JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: hooksPath))
        logger.info("Successfully installed Windsurf Cascade hooks into \(hooksPath)")
    }
    
    public func uninstallIntegration() async throws {
        let fm = FileManager.default
        let hooksPath = (globalConfigDir as NSString).appendingPathComponent("hooks.json")
        guard fm.fileExists(atPath: hooksPath) else { return }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
              var rootDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooksDict = rootDict["hooks"] as? [String: Any] else {
            return
        }
        
        for (event, value) in hooksDict {
            if var hookList = value as? [[String: Any]] {
                hookList.removeAll { ($0["command"] as? String)?.contains("flowback hook windsurf") == true }
                if hookList.isEmpty {
                    hooksDict.removeValue(forKey: event)
                } else {
                    hooksDict[event] = hookList
                }
            }
        }
        
        if hooksDict.isEmpty {
            rootDict.removeValue(forKey: "hooks")
        } else {
            rootDict["hooks"] = hooksDict
        }
        
        let outputData = try JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: hooksPath))
        logger.info("Removed Flowback Windsurf hooks from \(hooksPath)")
    }
    
    public func discoverActiveSessions() async -> [AgentSession] {
        let fm = FileManager.default
        let searchRoots = transcriptsDirs ?? [
            ((globalConfigDir as NSString).appendingPathComponent("transcripts")),
            ("~/.windsurf/transcripts" as NSString).expandingTildeInPath
        ]
        
        let now = Date()
        var discovered: [AgentSession] = []
        let windsurfApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.codeium.windsurf"
        }
        
        for root in searchRoots {
            guard fm.fileExists(atPath: root),
                  let files = try? fm.contentsOfDirectory(atPath: root) else {
                continue
            }
            
            for file in files where file.hasSuffix(".jsonl") {
                let filePath = (root as NSString).appendingPathComponent(file)
                let attrs = (try? fm.attributesOfItem(atPath: filePath)) ?? [:]
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                let createDate = attrs[.creationDate] as? Date ?? modDate
                
                // Only consider transcripts updated within the last 20 minutes
                guard now.timeIntervalSince(modDate) < 1200 else { continue }
                
                let trajId = (file as NSString).deletingPathExtension
                
                // Read last line without capturing full transcript text (Privacy rule adherence)
                guard let fileHandle = FileHandle(forReadingAtPath: filePath) else { continue }
                let fileSize = fileHandle.seekToEndOfFile()
                let offset = max(0, fileSize - 4096)
                fileHandle.seek(toFileOffset: offset)
                let tailData = fileHandle.readDataToEndOfFile()
                fileHandle.closeFile()
                
                let tailStr = String(data: tailData, encoding: .utf8) ?? ""
                let lines = tailStr.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard let lastLine = lines.last else { continue }
                
                // Determine state
                var state: AgentState = .running
                if lastLine.contains("\"post_cascade_response\"") || lastLine.contains("\"completed\"") {
                    state = .completed
                } else if lastLine.contains("\"error\"") {
                    state = .failed
                }
                
                // Extract workspace if present in JSON line
                var wsPath: String?
                if let wsRange = lastLine.range(of: "\"workspace_root\":\\s*\"([^\"]+)\"", options: .regularExpression) {
                    let matched = String(lastLine[wsRange])
                    let comps = matched.components(separatedBy: "\"")
                    if comps.count >= 4 {
                        wsPath = comps[3].replacingOccurrences(of: "\\/", with: "/")
                    }
                }
                
                // Resolve Origin
                var origin: OriginContext?
                if let ws = wsPath, let app = windsurfApps.first {
                    let folderName = (ws as NSString).lastPathComponent
                    origin = OriginContext(
                        bundleIdentifier: app.bundleIdentifier ?? "com.codeium.windsurf",
                        processIdentifier: app.processIdentifier,
                        windowIdentifier: nil,
                        windowTitle: "\(folderName) — Windsurf",
                        workspacePath: ws,
                        provenance: .providerTranscript,
                        confidence: 0.85,
                        restorationCapability: .workspaceWindow
                    )
                }
                
                let session = AgentSession(
                    id: AgentSessionID(trajId),
                    providerID: .windsurf,
                    providerSessionID: trajId,
                    state: state,
                    workspace: wsPath,
                    originContext: origin,
                    startedAt: createDate,
                    updatedAt: modDate
                )
                discovered.append(session)
            }
        }
        
        return discovered
    }
}
