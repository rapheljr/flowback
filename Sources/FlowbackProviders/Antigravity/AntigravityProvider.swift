import Foundation
import AppKit
import CoreGraphics
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "AntigravityProvider")

public final class AntigravityProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.antigravity
    public let displayName = "Google Antigravity"
    public let isSupported = true
    public let supportLevel = ProviderSupportLevel.nativeLifecycle

    private let globalConfigPath: String
    private let appBundlePath: String
    private let brainPaths: [String]?

    public init(
        globalConfigPath: String = ("~/.gemini/config" as NSString).expandingTildeInPath,
        appBundlePath: String = "/Applications/Antigravity IDE.app",
        brainPaths: [String]? = nil
    ) {
        self.globalConfigPath = globalConfigPath
        self.appBundlePath = appBundlePath
        self.brainPaths = brainPaths
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
            if let hook = (json["flowback-antigravity"] ?? json["flowback-agent-focus"]) as? [String: Any] {
                let stopCmds = hook["Stop"] as? [[String: Any]]
                let cmdStr = stopCmds?.first?["command"] as? String ?? ""
                if cmdStr.contains("flowback hook antigravity") && !cmdStr.contains("flowback hook antigravity-cli") {
                    hookInstalled = true
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
            isSupported: true,
            supportLevel: .nativeLifecycle
        )
    }

    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(AntigravityHookPayload.self, from: data) else {
            logger.warning("Could not decode Antigravity hook payload")
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

        let isCLI = payload.transcriptPath?.contains("antigravity-cli") == true ||
                    payload.artifactDirectoryPath?.contains("antigravity-cli") == true
        let resolvedProviderID = isCLI ? AgentProviderID.antigravityCLI : providerID

        // Resolve Origin Context
        var origin: OriginContext?
        let targetBundle = "com.google.antigravity-ide"
        if let ws = primaryWorkspace {
            let folderName = (ws as NSString).lastPathComponent
            let isAntigravity = { (b: String?) in b == targetBundle || b == "com.google.antigravity" }
            if let app = NSWorkspace.shared.runningApplications.first(where: { isAntigravity($0.bundleIdentifier) }) {
                var winID: UInt32?
                var winTitle = "\(folderName) — Antigravity"
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
                origin = OriginContext(
                    bundleIdentifier: app.bundleIdentifier ?? targetBundle,
                    processIdentifier: app.processIdentifier,
                    windowIdentifier: winID,
                    windowTitle: winTitle,
                    workspacePath: ws
                )
            } else if isCLI {
                // Resolve terminal origin for CLI invocations
                let terminalBundles = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "co.zeit.hyper"]
                if let termApp = NSWorkspace.shared.runningApplications.first(where: { terminalBundles.contains($0.bundleIdentifier ?? "") }) {
                    var winID: UInt32?
                    var winTitle = "\(folderName) — \(termApp.localizedName ?? "Terminal")"
                    if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                        for win in windowList {
                            let pid = win[kCGWindowOwnerPID as String] as? Int32 ?? 0
                            let title = win[kCGWindowName as String] as? String ?? ""
                            if pid == termApp.processIdentifier && title.localizedCaseInsensitiveContains(folderName) {
                                winID = win[kCGWindowNumber as String] as? UInt32
                                winTitle = title
                                break
                            }
                        }
                    }
                    origin = OriginContext(
                        bundleIdentifier: termApp.bundleIdentifier ?? "com.apple.Terminal",
                        processIdentifier: termApp.processIdentifier,
                        windowIdentifier: winID,
                        windowTitle: winTitle,
                        workspacePath: ws
                    )
                }
            }
        }

        let convTitle = payload.conversation_title
        if let t = convTitle, !t.isEmpty {
            metadata["title"] = t
            metadata["conversation_title"] = t
        }

        return AgentEvent(
            timestamp: Date(),
            providerID: resolvedProviderID,
            sessionID: AgentSessionID(payload.conversationId),
            type: eventType,
            workspace: primaryWorkspace,
            origin: origin,
            metadata: metadata,
            conversationID: payload.conversationId,
            conversationTitle: convTitle,
            executionID: payload.executionNum.map { "\($0)" },
            focusCapability: isCLI ? .workspaceAndConversation : .windowOnly,
            isRemote: false
        )
    }

    private func extractConversationTitle(from text: String) -> String? {
        BrainTranscriptParser.extractConversationTitle(from: text)
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public func discoverActiveSessions() async -> [AgentSession] {
        let fm = FileManager.default
        let searchRoots = brainPaths ?? [
            ("~/.gemini/antigravity-ide/brain" as NSString).expandingTildeInPath,
            ("~/.gemini/antigravity/brain" as NSString).expandingTildeInPath
        ]

        let now = Date()
        var discovered: [AgentSession] = []
        let antigravityApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.google.antigravity-ide" || $0.bundleIdentifier == "com.google.antigravity"
        }

        for root in searchRoots {
            guard fm.fileExists(atPath: root),
                  let entries = try? fm.contentsOfDirectory(atPath: root) else {
                continue
            }

            for convID in entries where !convID.hasPrefix(".") {
                let convPath = (root as NSString).appendingPathComponent(convID)
                let logsDir = (convPath as NSString).appendingPathComponent(".system_generated/logs")
                let transcriptPath = (logsDir as NSString).appendingPathComponent("transcript.jsonl")
                let tasksPath = (convPath as NSString).appendingPathComponent(".system_generated/tasks")

                guard fm.fileExists(atPath: transcriptPath) else { continue }
                let attrs = (try? fm.attributesOfItem(atPath: transcriptPath)) ?? [:]
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                let createDate = attrs[.creationDate] as? Date ?? modDate

                // Check if recently modified (within 20 minutes) or has tasks active
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

                // Read head and tail of transcript file
                guard let fileHandle = FileHandle(forReadingAtPath: transcriptPath) else { continue }
                let fileSize = fileHandle.seekToEndOfFile()

                // Read head
                fileHandle.seek(toFileOffset: 0)
                let headData = fileHandle.readData(ofLength: Int(min(fileSize, 65536)))
                let headStr = String(data: headData, encoding: .utf8) ?? ""

                // Read tail if large
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

                // Check if last line indicates fully completed and stopped idle without background tasks
                var hasActiveTasks = false
                if fm.fileExists(atPath: tasksPath), let taskFiles = try? fm.contentsOfDirectory(atPath: tasksPath) {
                    for tf in taskFiles where !tf.hasPrefix(".") {
                        let tPath = (tasksPath as NSString).appendingPathComponent(tf)
                        if let tAttrs = try? fm.attributesOfItem(atPath: tPath),
                           let tMod = tAttrs[.modificationDate] as? Date,
                           now.timeIntervalSince(tMod) < 300 {
                            hasActiveTasks = true
                            break
                        }
                    }
                }

                let isModelDoneWithoutTools = lastLine.contains("\"source\":\"MODEL\"") &&
                    lastLine.contains("\"type\":\"PLANNER_RESPONSE\"") &&
                    lastLine.contains("\"status\":\"DONE\"") &&
                    !lastLine.contains("\"tool_calls\"")

                let isCompleted = (isModelDoneWithoutTools || lastLine.contains("\"fullyIdle\":true")) && !hasActiveTasks

                if isCompleted && now.timeIntervalSince(modDate) > 300 {
                    continue
                }

                // Extract workspace path
                let workspacePath = BrainTranscriptParser.extractWorkspacePath(from: chunkStr)

                // Resolve Origin Context
                var origin: OriginContext?
                if let ws = workspacePath {
                    let folderName = (ws as NSString).lastPathComponent
                    if let app = antigravityApps.first {
                        var winID: UInt32?
                        var winTitle = "\(folderName) — Antigravity"
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
                        origin = OriginContext(
                            bundleIdentifier: app.bundleIdentifier ?? "com.google.antigravity-ide",
                            processIdentifier: app.processIdentifier,
                            windowIdentifier: winID,
                            windowTitle: winTitle,
                            workspacePath: ws
                        )
                    }
                }

                let convTitle = extractConversationTitle(from: chunkStr)
                let sessionState: AgentState = isCompleted ? .completed : .running
                let session = AgentSession(
                    id: AgentSessionID(convID),
                    providerID: .antigravity,
                    providerSessionID: convID,
                    state: sessionState,
                    workspace: workspacePath,
                    originContext: origin,
                    startedAt: createDate,
                    updatedAt: modDate,
                    completedAt: isCompleted ? modDate : nil,
                    conversationID: convID,
                    conversationTitle: convTitle,
                    focusCapability: .windowOnly,
                    isRemote: false
                )

                discovered.append(session)
            }
        }

        return discovered
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

        let cmd = "export PATH=\"$HOME/.local/bin:/usr/local/bin:$PATH\"; flowback hook antigravity"

        // Define Flowback hook block supporting PreInvocation, PostInvocation, and Stop
        let flowbackHook: [String: Any] = [
            "enabled": true,
            "PreInvocation": [
                [
                    "type": "command",
                    "command": cmd,
                    "timeout": 5
                ]
            ],
            "PostInvocation": [
                [
                    "type": "command",
                    "command": cmd,
                    "timeout": 5
                ]
            ],
            "Stop": [
                [
                    "type": "command",
                    "command": cmd,
                    "timeout": 5
                ]
            ]
        ]

        hooksDict["flowback-antigravity"] = flowbackHook
        if let legacy = hooksDict["flowback-agent-focus"] as? [String: Any] {
            let legacyCmd = ((legacy["Stop"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
            if legacyCmd.contains("flowback hook antigravity") && !legacyCmd.contains("flowback hook antigravity-cli") {
                hooksDict.removeValue(forKey: "flowback-agent-focus")
            }
        }

        let outputData = try JSONSerialization.data(withJSONObject: hooksDict, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: hooksPath), options: .atomic)
        logger.info("Successfully installed Flowback hooks (PreInvocation, PostInvocation, Stop) to \(hooksPath)")
    }

    public func uninstallIntegration() async throws {
        let fm = FileManager.default
        let hooksPath = (globalConfigPath as NSString).appendingPathComponent("hooks.json")
        guard fm.fileExists(atPath: hooksPath) else { return }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
              var hooksDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var didRemove = false
        if hooksDict.removeValue(forKey: "flowback-antigravity") != nil {
            didRemove = true
        }
        if let legacy = hooksDict["flowback-agent-focus"] as? [String: Any] {
            let legacyCmd = ((legacy["Stop"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
            if legacyCmd.contains("flowback hook antigravity") && !legacyCmd.contains("flowback hook antigravity-cli") {
                hooksDict.removeValue(forKey: "flowback-agent-focus")
                didRemove = true
            }
        }

        if didRemove {
            let outputData = try JSONSerialization.data(withJSONObject: hooksDict, options: [.prettyPrinted, .sortedKeys])
            try outputData.write(to: URL(fileURLWithPath: hooksPath), options: .atomic)
            logger.info("Removed Flowback desktop hook from \(hooksPath)")
        }
    }
}
