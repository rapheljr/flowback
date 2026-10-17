import Foundation
import AppKit
import CoreGraphics
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "OpenCodeProvider")

public final class OpenCodeProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.openCode
    public let displayName = "OpenCode"
    public let isSupported = true
    public let supportLevel = ProviderSupportLevel.nativeLifecycle
    
    private let configDir: String
    private let pluginInstallDir: String
    private let appBundlePath: String
    private let cliPath: String
    
    public init(
        configDir: String = ("~/.config/opencode" as NSString).expandingTildeInPath,
        pluginInstallDir: String = ("~/.config/opencode/plugins" as NSString).expandingTildeInPath,
        appBundlePath: String = "/Applications/OpenCode.app",
        cliPath: String = "/usr/local/bin/opencode"
    ) {
        self.configDir = configDir
        self.pluginInstallDir = pluginInstallDir
        self.appBundlePath = appBundlePath
        self.cliPath = cliPath
    }
    
    public func checkHealth() async -> ProviderHealth {
        let fm = FileManager.default
        let appExists = fm.fileExists(atPath: appBundlePath)
        let cliExists = fm.fileExists(atPath: cliPath)
        let configExists = fm.fileExists(atPath: configDir)
        let isInstalled = appExists || cliExists || configExists
        
        let targetPluginPath = (pluginInstallDir as NSString).appendingPathComponent("flowback.js")
        let hookInstalled = fm.fileExists(atPath: targetPluginPath)
        let hookExecutable = hookInstalled
        
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
            statusMessage = "OpenCode not detected on system"
        } else if !hookInstalled {
            statusMessage = "OpenCode detected, but Flowback plugin not installed in ~/.config/opencode/plugins"
        } else {
            statusMessage = "OpenCode native plugin integration active and healthy"
        }
        
        return ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: isInstalled,
            version: version,
            hookInstalled: hookInstalled,
            hookExecutable: hookExecutable,
            configurationPath: targetPluginPath,
            statusMessage: statusMessage,
            isSupported: true,
            supportLevel: .nativeLifecycle
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(OpenCodeHookPayload.self, from: data) else {
            logger.warning("Could not decode OpenCode hook payload")
            return nil
        }
        
        let sId = payload.sessionId ?? payload.session_id ?? UUID().uuidString
        let rawEvent = payload.event?.lowercased() ?? "session.running"
        let workspace = payload.workspace ?? payload.directory
        
        var metadata: [String: String] = [
            "sessionId": sId,
            "rawEvent": rawEvent
        ]
        if let pId = payload.projectId {
            metadata["projectId"] = pId
        }
        if let err = payload.error, !err.isEmpty {
            metadata["error"] = err
        }
        if let tool = payload.tool {
            if let name = tool.name { metadata["toolName"] = name }
            if let callId = tool.callId { metadata["callId"] = callId }
        }
        if let customMeta = payload.metadata {
            for (k, v) in customMeta { metadata[k] = v }
        }
        
        // Custom deduplication key
        let toolId = payload.tool?.callId ?? ""
        metadata["deduplicationKey"] = "opencode:\(sId):\(rawEvent):\(toolId)"
        
        let eventType: AgentEventType
        if let err = metadata["error"], !err.isEmpty {
            eventType = .agentFailed
        } else {
            switch rawEvent {
            case "session.created", "agent.started":
                eventType = .agentStarted
            case "session.idle", "session.completed", "agent.completed":
                eventType = .agentCompleted
            case "session.deleted", "agent.cancelled":
                eventType = .agentCancelled
            case "session.error", "agent.failed":
                eventType = .agentFailed
            case "tool.execute.before":
                if payload.tool?.requiresPermission == true {
                    eventType = .agentPermissionRequired
                } else {
                    eventType = .agentRunning
                }
            case "tool.execute.after", "agent.progress":
                eventType = .agentProgress
            default:
                eventType = .agentRunning
            }
        }
        
        // Resolve Origin Context
        var origin: OriginContext?
        if let ws = workspace {
            let folderName = (ws as NSString).lastPathComponent
            let targetBundles: Set<String> = ["ai.opencode.app", "com.opencode", "com.github.opencode"]
            let apps = NSWorkspace.shared.runningApplications.filter {
                guard let b = $0.bundleIdentifier else { return false }
                return targetBundles.contains(b)
            }
            if let app = apps.first {
                var winID: UInt32?
                var winTitle = "\(folderName) — OpenCode"
                if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                    for win in windowList {
                        let pid = win[kCGWindowOwnerPID as String] as? Int32 ?? 0
                        let title = win[kCGWindowName as String] as? String ?? ""
                        if pid == app.processIdentifier && (title.localizedCaseInsensitiveContains(folderName) || title.localizedCaseInsensitiveContains("OpenCode")) {
                            winID = win[kCGWindowNumber as String] as? UInt32
                            winTitle = title
                            break
                        }
                    }
                }
                origin = OriginContext(
                    bundleIdentifier: app.bundleIdentifier ?? "ai.opencode.app",
                    processIdentifier: app.processIdentifier,
                    windowIdentifier: winID,
                    windowTitle: winTitle,
                    workspacePath: ws,
                    provenance: .nativeHook,
                    confidence: 0.95,
                    restorationCapability: .workspaceWindow
                )
            }
        }
        
        return AgentEvent(
            timestamp: Date(),
            providerID: providerID,
            sessionID: AgentSessionID(sId),
            type: eventType,
            workspace: workspace,
            origin: origin,
            metadata: metadata
        )
    }
    
    public func installIntegration() async throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: pluginInstallDir, withIntermediateDirectories: true)
        
        let targetPluginPath = (pluginInstallDir as NSString).appendingPathComponent("flowback.js")
        if fm.fileExists(atPath: targetPluginPath) {
            let backupPath = "\(targetPluginPath).bak.\(Int(Date().timeIntervalSince1970))"
            try? fm.copyItem(atPath: targetPluginPath, toPath: backupPath)
        }
        
        let pluginCode = OpenCodeProvider.embeddedPluginSource
        try pluginCode.write(to: URL(fileURLWithPath: targetPluginPath), atomically: true, encoding: .utf8)
        
        // Also register in opencode.json if configuration file exists or directory exists
        let configPath = (configDir as NSString).appendingPathComponent("opencode.json")
        var configDict: [String: Any] = [:]
        if fm.fileExists(atPath: configPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            configDict = existing
        }
        
        var pluginsList = configDict["plugins"] as? [String] ?? []
        if !pluginsList.contains("flowback") {
            pluginsList.append("flowback")
            configDict["plugins"] = pluginsList
            if let outputData = try? JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys]) {
                try? outputData.write(to: URL(fileURLWithPath: configPath))
            }
        }
        
        logger.info("Successfully installed OpenCode Flowback plugin at \(targetPluginPath)")
    }
    
    public func uninstallIntegration() async throws {
        let fm = FileManager.default
        let targetPluginPath = (pluginInstallDir as NSString).appendingPathComponent("flowback.js")
        if fm.fileExists(atPath: targetPluginPath) {
            try? fm.removeItem(atPath: targetPluginPath)
        }
        
        let configPath = (configDir as NSString).appendingPathComponent("opencode.json")
        if fm.fileExists(atPath: configPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           var configDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var pluginsList = configDict["plugins"] as? [String] {
            pluginsList.removeAll { $0 == "flowback" }
            if pluginsList.isEmpty {
                configDict.removeValue(forKey: "plugins")
            } else {
                configDict["plugins"] = pluginsList
            }
            if let outputData = try? JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys]) {
                try? outputData.write(to: URL(fileURLWithPath: configPath))
            }
        }
        
        logger.info("Removed Flowback OpenCode plugin from \(targetPluginPath)")
    }
    
    public func discoverActiveSessions() async -> [AgentSession] {
        // Fallback observation: check running OpenCode instances
        let running = NSWorkspace.shared.runningApplications.filter {
            guard let b = $0.bundleIdentifier else { return false }
            return b == "ai.opencode.app" || b == "com.opencode"
        }
        
        var sessions: [AgentSession] = []
        for app in running {
            let pid = app.processIdentifier
            let origin = OriginContext(
                bundleIdentifier: app.bundleIdentifier ?? "ai.opencode.app",
                processIdentifier: pid,
                provenance: .systemFrontmost,
                restorationCapability: .applicationActivationOnly
            )
            let s = AgentSession(
                id: AgentSessionID("opencode-proc-\(pid)"),
                providerID: .openCode,
                providerSessionID: "\(pid)",
                state: .running,
                originContext: origin,
                startedAt: Date(),
                updatedAt: Date()
            )
            sessions.append(s)
        }
        return sessions
    }
    
    public static let embeddedPluginSource: String = """
    // Flowback Universal Focus Orchestrator — OpenCode Plugin
    const net = require("net");
    const fs = require("fs");
    const path = require("path");
    const os = require("os");

    const SOCKET_PATH = process.env.FLOWBACK_SOCKET || path.join(os.homedir(), ".flowback", "flowback.sock");
    const TOKEN_PATH = path.join(os.homedir(), ".flowback", ".session_token");

    function getSessionToken() {
      try {
        if (fs.existsSync(TOKEN_PATH)) {
          return fs.readFileSync(TOKEN_PATH, "utf8").trim();
        }
      } catch (e) {}
      return null;
    }

    function sendIPCEvent(eventData) {
      const token = getSessionToken();
      const request = {
        command: "hook",
        argument: "opencode",
        payload: Buffer.from(JSON.stringify(eventData)).toString("base64"),
        authToken: token
      };
      try {
        const client = net.createConnection({ path: SOCKET_PATH }, () => {
          client.write(JSON.stringify(request) + "\\n");
        });
        client.on("data", () => client.end());
        client.on("error", () => {});
      } catch (e) {}
    }

    async function setup(ctx) {
      const abortController = new AbortController();
      const { signal } = abortController;
      const currentWorkspace = ctx?.workspace || process.cwd();

      const emitLifecycle = (eventType, session, extra = {}) => {
        const sId = session?.id || session?.sessionId || "opencode-session";
        const dir = session?.directory || session?.project || currentWorkspace;
        const payload = {
          event: eventType,
          sessionId: sId,
          directory: dir,
          workspace: dir,
          timestamp: new Date().toISOString(),
          ...extra
        };
        sendIPCEvent(payload);
      };

      try {
        if (ctx?.event?.subscribe) {
          (async () => {
            try {
              for await (const event of ctx.event.subscribe({ signal })) {
                if (!event || !event.type) continue;
                switch (event.type) {
                  case "session.created":
                    emitLifecycle("session.created", event.session || event);
                    break;
                  case "session.idle":
                  case "session.completed":
                    emitLifecycle("session.idle", event.session || event);
                    break;
                  case "session.deleted":
                    emitLifecycle("session.deleted", event.session || event);
                    break;
                  case "session.error":
                    emitLifecycle("session.error", event.session || event, { error: event.error || "Session error" });
                    break;
                  case "tool.execute.before":
                    emitLifecycle("tool.execute.before", event.session || {}, {
                      tool: {
                        name: event.toolName || event.name,
                        callId: event.callId,
                        requiresPermission: !!event.requiresConfirmation || !!event.requiresPermission
                      }
                    });
                    break;
                  case "tool.execute.after":
                    emitLifecycle("tool.execute.after", event.session || {}, {
                      tool: {
                        name: event.toolName || event.name,
                        callId: event.callId,
                        status: "finished"
                      }
                    });
                    break;
                  case "session.status":
                    if (event.status === "busy" || event.status === "running") {
                      emitLifecycle("session.running", event.session || event);
                    }
                    break;
                }
              }
            } catch (err) {}
          })();
        }
      } catch (e) {}

      return () => {
        abortController.abort();
      };
    }

    module.exports = {
      id: "flowback-opencode",
      name: "Flowback OpenCode Integration",
      setup
    };
    module.exports.default = module.exports;
    """
}
