import Foundation
import AppKit
import CoreGraphics
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "AntigravityCLIProvider")

public final class AntigravityCLIProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.antigravityCLI
    public let displayName = "Antigravity CLI"
    public let isSupported = true
    public let supportLevel = ProviderSupportLevel.nativeLifecycle
    
    private let globalConfigPath: String
    private let cliDir: String
    private let binaryPaths: [String]
    
    public init(
        globalConfigPath: String = ("~/.gemini/config" as NSString).expandingTildeInPath,
        cliDir: String = ("~/.gemini/antigravity-cli" as NSString).expandingTildeInPath,
        binaryPaths: [String]? = nil
    ) {
        self.globalConfigPath = globalConfigPath
        self.cliDir = cliDir
        self.binaryPaths = binaryPaths ?? [
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            ("~/.local/bin/agy" as NSString).expandingTildeInPath,
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/gemini"
        ]
    }
    
    public func checkHealth() async -> ProviderHealth {
        let fm = FileManager.default
        let dirExists = fm.fileExists(atPath: cliDir)
        
        var detectedBinary: String?
        for path in binaryPaths {
            if fm.fileExists(atPath: path) {
                detectedBinary = path
                break
            }
        }
        
        let isInstalled = dirExists || (detectedBinary != nil)
        let hooksPath = (globalConfigPath as NSString).appendingPathComponent("hooks.json")
        var hookInstalled = false
        
        if fm.fileExists(atPath: hooksPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            hookInstalled = json["flowback-agent-focus"] != nil
        }
        
        var version: String?
        if let bin = detectedBinary {
            version = probeBinaryVersion(atPath: bin)
        }
        
        let statusMessage: String
        if !isInstalled {
            statusMessage = "Antigravity CLI (agy) not detected on system"
        } else if !hookInstalled {
            statusMessage = "Antigravity CLI detected, but Flowback hook not configured in hooks.json"
        } else {
            statusMessage = "Integration active and healthy via hooks.json"
        }
        
        return ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: isInstalled,
            version: version,
            hookInstalled: hookInstalled,
            hookExecutable: true,
            configurationPath: hooksPath,
            statusMessage: statusMessage,
            isSupported: true,
            supportLevel: .nativeLifecycle
        )
    }
    
    private func probeBinaryVersion(atPath path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(1.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if !process.isRunning && process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    return str
                }
            } else if process.isRunning {
                process.terminate()
            }
        } catch {
            logger.debug("Failed to probe version for \(path): \(error.localizedDescription)")
        }
        return nil
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(AntigravityHookPayload.self, from: data) {
            let primaryWorkspace = payload.workspacePaths?.first
            var metadata: [String: String] = [
                "conversationId": payload.conversationId,
                "terminationReason": payload.terminationReason ?? "unknown",
                "modelName": payload.modelName ?? "auto"
            ]
            
            if let execNum = payload.executionNum {
                metadata["executionNum"] = "\(execNum)"
            }
            if let invNum = payload.invocationNum {
                metadata["invocationNum"] = "\(invNum)"
            }
            if let err = payload.error, !err.isEmpty {
                metadata["error"] = err
            }
            if let fullyIdle = payload.fullyIdle {
                metadata["fullyIdle"] = "\(fullyIdle)"
            }
            
            let eventType: AgentEventType
            let hookName = payload.hook_event_name?.lowercased()
            
            if let err = payload.error, !err.isEmpty {
                eventType = .agentFailed
            } else if hookName == "postinvocation" {
                eventType = .agentProgress
            } else if hookName == "preinvocation" || (hookName == nil && payload.invocationNum != nil && payload.terminationReason == nil) {
                eventType = (payload.invocationNum == 1) ? .agentStarted : .agentRunning
            } else if payload.fullyIdle == true {
                eventType = .agentCompleted
            } else if hookName == "stop" || payload.terminationReason != nil {
                eventType = (payload.fullyIdle == false) ? .agentRunning : .agentCompleted
            } else {
                eventType = .agentRunning
            }
            
            let origin = resolveTerminalOrigin(forWorkspace: primaryWorkspace)
            
            return AgentEvent(
                timestamp: Date(),
                providerID: providerID,
                sessionID: AgentSessionID(payload.conversationId),
                type: eventType,
                workspace: primaryWorkspace,
                origin: origin,
                metadata: metadata
            )
        }
        
        // Fallback: Generic JSON payload
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        let sessionID = (json["session_id"] as? String) ?? (json["id"] as? String) ?? UUID().uuidString
        let status = (json["status"] as? String) ?? (json["state"] as? String) ?? "completed"
        let workspace = (json["workspace"] as? String) ?? (json["cwd"] as? String)
        
        let eventType: AgentEventType
        switch status {
        case "permission_required":
            eventType = .agentPermissionRequired
        case "failed", "error":
            eventType = .agentFailed
        case "running":
            eventType = .agentRunning
        case "waiting":
            eventType = .agentWaiting
        default:
            eventType = .agentCompleted
        }
        
        let origin = resolveTerminalOrigin(forWorkspace: workspace)
        
        return AgentEvent(
            timestamp: Date(),
            providerID: providerID,
            sessionID: AgentSessionID(sessionID),
            type: eventType,
            workspace: workspace,
            origin: origin,
            metadata: ["status": status]
        )
    }
    
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public func discoverActiveSessions() async -> [AgentSession] {
        let fm = FileManager.default
        let now = Date()
        var discovered: [AgentSession] = []
        var seenIDs = Set<String>()
        
        // 1. Scan brain directory for active transcripts
        let brainDir = (cliDir as NSString).appendingPathComponent("brain")
        if fm.fileExists(atPath: brainDir),
           let entries = try? fm.contentsOfDirectory(atPath: brainDir) {
            for convID in entries where !convID.hasPrefix(".") {
                let convPath = (brainDir as NSString).appendingPathComponent(convID)
                let logsDir = (convPath as NSString).appendingPathComponent(".system_generated/logs")
                let transcriptPath = (logsDir as NSString).appendingPathComponent("transcript.jsonl")
                let tasksPath = (convPath as NSString).appendingPathComponent(".system_generated/tasks")
                
                guard fm.fileExists(atPath: transcriptPath) else { continue }
                let attrs = (try? fm.attributesOfItem(atPath: transcriptPath)) ?? [:]
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                let createDate = attrs[.creationDate] as? Date ?? modDate
                
                var recentlyActive = (now.timeIntervalSince(modDate) < 1200)
                if !recentlyActive, fm.fileExists(atPath: tasksPath),
                   let taskFiles = try? fm.contentsOfDirectory(atPath: tasksPath) {
                    for tf in taskFiles {
                        let tPath = (tasksPath as NSString).appendingPathComponent(tf)
                        let tAttrs = (try? fm.attributesOfItem(atPath: tPath)) ?? [:]
                        if let tMod = tAttrs[.modificationDate] as? Date, now.timeIntervalSince(tMod) < 1200 {
                            recentlyActive = true
                            break
                        }
                    }
                }
                
                guard recentlyActive else { continue }
                
                guard let fileHandle = FileHandle(forReadingAtPath: transcriptPath) else { continue }
                let fileSize = fileHandle.seekToEndOfFile()
                fileHandle.seek(toFileOffset: 0)
                let headData = fileHandle.readData(ofLength: Int(min(fileSize, 65536)))
                let headStr = String(data: headData, encoding: .utf8) ?? ""
                
                var tailStr = ""
                if fileSize > 65536 {
                    let tailOffset = max(65536, fileSize - 65536)
                    fileHandle.seek(toFileOffset: tailOffset)
                    let tailData = fileHandle.readDataToEndOfFile()
                    tailStr = String(data: tailData, encoding: .utf8) ?? ""
                }
                fileHandle.closeFile()
                
                let chunkStr = headStr + "\n" + tailStr
                let lines = (tailStr.isEmpty ? headStr : tailStr).components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard let lastLine = lines.last else { continue }
                let isModelDoneWithoutTools = lastLine.contains("\"source\":\"MODEL\"") &&
                    lastLine.contains("\"type\":\"PLANNER_RESPONSE\"") &&
                    lastLine.contains("\"status\":\"DONE\"") &&
                    !lastLine.contains("\"tool_calls\"")
                
                let isCompleted = (isModelDoneWithoutTools || lastLine.contains("\"fullyIdle\":true"))
                if isCompleted && now.timeIntervalSince(modDate) > 300 {
                    continue
                }
                
                let workspacePath = extractWorkspacePath(from: chunkStr)
                let origin = resolveTerminalOrigin(forWorkspace: workspacePath)
                let sessionState: AgentState = isCompleted ? .completed : .running
                
                seenIDs.insert(convID)
                discovered.append(AgentSession(
                    id: AgentSessionID(convID),
                    providerID: providerID,
                    providerSessionID: convID,
                    state: sessionState,
                    workspace: workspacePath,
                    originContext: origin,
                    startedAt: createDate,
                    updatedAt: modDate,
                    completedAt: isCompleted ? modDate : nil
                ))
            }
        }
        
        // 2. Scan presence locks for active CLI sessions
        let presenceDir = (cliDir as NSString).appendingPathComponent("presence")
        if fm.fileExists(atPath: presenceDir),
           let lockFiles = try? fm.contentsOfDirectory(atPath: presenceDir) {
            for lock in lockFiles where lock.hasSuffix(".lock") {
                let convID = String(lock.dropLast(5))
                guard !seenIDs.contains(convID) else { continue }
                
                let lockPath = (presenceDir as NSString).appendingPathComponent(lock)
                let attrs = (try? fm.attributesOfItem(atPath: lockPath)) ?? [:]
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                
                // If lock was updated within 30 minutes, consider it potentially active
                if now.timeIntervalSince(modDate) < 1800 {
                    let ws = findWorkspaceFromHistory(forConversationID: convID)
                    let origin = resolveTerminalOrigin(forWorkspace: ws)
                    seenIDs.insert(convID)
                    discovered.append(AgentSession(
                        id: AgentSessionID(convID),
                        providerID: providerID,
                        providerSessionID: convID,
                        state: .running,
                        workspace: ws,
                        originContext: origin,
                        startedAt: modDate,
                        updatedAt: modDate
                    ))
                }
            }
        }
        
        return discovered
    }
    
    private func findWorkspaceFromHistory(forConversationID convID: String) -> String? {
        let historyPath = (cliDir as NSString).appendingPathComponent("history.jsonl")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: historyPath)),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        let lines = content.components(separatedBy: "\n").reversed()
        for line in lines where line.contains(convID) {
            if let lineData = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let ws = json["workspace"] as? String {
                return ws
            }
        }
        return nil
    }
    
    private func extractWorkspacePath(from text: String) -> String? {
        let userHome = NSHomeDirectory()
        let fm = FileManager.default

        // Pattern 1: /workspace/projects/<name>
        if let projRange = text.range(of: "/workspace/projects/([A-Za-z0-9_-]+)", options: .regularExpression) {
            let matched = String(text[projRange])
            let comps = matched.components(separatedBy: "/workspace/projects/")
            if comps.count > 1, let proj = comps.last?.components(separatedBy: "/").first, !proj.isEmpty {
                return (userHome as NSString).appendingPathComponent("workspace/projects/\(proj)")
            }
        }

        // Pattern 2: "Cwd":"...path..."
        if let cwdRange = text.range(of: "\"Cwd\":\\s*\"([^\"]+)\"", options: .regularExpression) {
            let matched = String(text[cwdRange])
            let comps = matched.components(separatedBy: "\"")
            if comps.count >= 4 {
                return comps[3].replacingOccurrences(of: "\\/", with: "/")
            }
        }

        // Pattern 3: /Users/... -> CorpusName mapping
        if let uriRange = text.range(of: "(/[^\\s\n\"']+)\\s*->", options: .regularExpression) {
            let uriLine = String(text[uriRange])
            let pathPart = uriLine.components(separatedBy: "->").first?.trimmingCharacters(in: .whitespaces)
            if let p = pathPart, fm.fileExists(atPath: p) {
                return p
            }
        }

        // Pattern 4: "workspacePaths": ["/Users/..."]
        if let wsRange = text.range(of: "\"workspacePaths\":\\s*\\[\\s*\"([^\"]+)\"", options: .regularExpression) {
            let matched = String(text[wsRange])
            let comps = matched.components(separatedBy: "\"")
            if comps.count >= 4 {
                let candidate = comps[3].replacingOccurrences(of: "\\/", with: "/")
                if fm.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }
    
    private func resolveTerminalOrigin(forWorkspace workspace: String?) -> OriginContext? {
        guard let ws = workspace else { return nil }
        let folderName = (ws as NSString).lastPathComponent
        
        let terminalBundles = [
            "com.mitchellh.ghostty",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "co.zeit.hyper",
            "org.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm"
        ]
        
        let runningApps = NSWorkspace.shared.runningApplications
        var matchedApp: NSRunningApplication?
        for bundle in terminalBundles {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundle }) {
                matchedApp = app
                break
            }
        }
        
        guard let app = matchedApp else { return nil }
        
        var winID: UInt32?
        var winTitle = "\(folderName) — \(app.localizedName ?? "Terminal")"
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for win in windowList {
                let pid = win[kCGWindowOwnerPID as String] as? Int32 ?? 0
                let title = win[kCGWindowName as String] as? String ?? ""
                if pid == app.processIdentifier && title.localizedCaseInsensitiveContains(folderName) {
                    winID = win[kCGWindowNumber as String] as? UInt32
                    winTitle = title
                    break
                }
            }
        }
        
        return OriginContext(
            bundleIdentifier: app.bundleIdentifier ?? "com.apple.Terminal",
            processIdentifier: app.processIdentifier,
            windowIdentifier: winID,
            windowTitle: winTitle,
            workspacePath: ws
        )
    }
    
    public func installIntegration() async throws {
        let fm = FileManager.default
        let hooksPath = (globalConfigPath as NSString).appendingPathComponent("hooks.json")
        try fm.createDirectory(atPath: globalConfigPath, withIntermediateDirectories: true)
        
        var hooksDict: [String: Any] = [:]
        if fm.fileExists(atPath: hooksPath) {
            let backupPath = "\(hooksPath).bak.\(Int(Date().timeIntervalSince1970))"
            try? fm.copyItem(atPath: hooksPath, toPath: backupPath)
            
            if let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                hooksDict = existing
            }
        }
        
        let cmd = "export PATH=\"/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:$PATH\"; flowback hook antigravity-cli"
        let flowbackHook: [String: Any] = [
            "enabled": true,
            "PreInvocation": [["type": "command", "command": cmd, "timeout": 5]],
            "PostInvocation": [["type": "command", "command": cmd, "timeout": 5]],
            "Stop": [["type": "command", "command": cmd, "timeout": 5]]
        ]
        
        hooksDict["flowback-agent-focus"] = flowbackHook
        let outputData = try JSONSerialization.data(withJSONObject: hooksDict, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: hooksPath))
        logger.info("Successfully installed Flowback hooks for Antigravity CLI to \(hooksPath)")
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
