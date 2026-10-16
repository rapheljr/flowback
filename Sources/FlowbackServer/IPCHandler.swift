import Foundation
import AppKit
import FlowbackCore
import FlowbackFocus
import FlowbackProviders
import FlowbackStorage
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "IPCHandler")

public final class IPCHandler: IPCHandlerDelegate, @unchecked Sendable {
    private let eventBus: EventBus
    private let sessionManager: SessionManager
    private let focusController: FocusController
    private let providerRegistry: ProviderRegistry
    private let settingsRepo: SettingsRepository
    private var focusLock: FocusLockState
    
    public init(
        eventBus: EventBus = .shared,
        sessionManager: SessionManager,
        focusController: FocusController,
        providerRegistry: ProviderRegistry = .shared,
        settingsRepo: SettingsRepository,
        focusLock: FocusLockState = FocusLockState()
    ) {
        self.eventBus = eventBus
        self.sessionManager = sessionManager
        self.focusController = focusController
        self.providerRegistry = providerRegistry
        self.settingsRepo = settingsRepo
        self.focusLock = focusLock
    }
    
    public func setFocusLock(_ state: FocusLockState) {
        self.focusLock = state
    }
    
    public func currentFocusLock() -> FocusLockState {
        self.focusLock
    }
    
    public func handleRequest(_ request: IPCRequest) async -> IPCResponse {
        logger.info("Handling IPC command: \(request.command)")
        
        switch request.command {
        case "status":
            return await handleStatus()
            
        case "agents":
            return await handleAgents()
            
        case "sessions":
            return await handleSessions()
            
        case "doctor":
            return await handleDoctor()
            
        case "focus":
            return await handleFocus(sessionIDString: request.argument)
            
        case "focus-lock":
            return handleFocusLock(argument: request.argument)
            
        case "hook":
            return await handleHook(providerString: request.argument, payload: request.payload)
            
        case "emit":
            return await handleEmit(payload: request.payload)
            
        case "refresh":
            return await handleRefresh()
            
        case "test-focus":
            return await handleTestFocus()
            
        default:
            return IPCResponse(success: false, message: "Unknown command '\(request.command)'")
        }
    }
    
    // MARK: - Handlers
    
    private func handleStatus() async -> IPCResponse {
        let active = await sessionManager.getActiveSessions()
        let healths = await providerRegistry.checkAllHealth()
        let isLocked = focusLock.isCurrentlyLocked
        
        var summary = [
            "activeSessionsCount": "\(active.count)",
            "focusLockActive": "\(isLocked)",
            "providersConfigured": "\(healths.count)",
            "status": "online"
        ]
        if let rem = focusLock.remainingSeconds {
            summary["focusLockRemainingSeconds"] = "\(Int(rem))"
        }
        
        let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted])
        return IPCResponse(success: true, message: "Flowback is running", data: data)
    }
    
    private func handleAgents() async -> IPCResponse {
        let active = await sessionManager.getActiveSessions()
        let data = try? JSONEncoder().encode(active)
        return IPCResponse(success: true, message: "Found \(active.count) active sessions", data: data)
    }
    
    private func handleSessions() async -> IPCResponse {
        let recent = await sessionManager.getRecentSessions(limit: 20)
        let data = try? JSONEncoder().encode(recent)
        return IPCResponse(success: true, message: "Found \(recent.count) recent sessions", data: data)
    }
    
    private func handleDoctor() async -> IPCResponse {
        let healths = await providerRegistry.checkAllHealth()
        let permStatus = await PermissionManager.shared.currentStatus()
        
        var report: [String: Any] = [
            "permissions": [
                "accessibility": permStatus.accessibilityGranted,
                "notifications": permStatus.notificationsGranted,
                "launchAtLogin": permStatus.launchAtLoginEnabled
            ]
        ]
        
        var providerList: [[String: Any]] = []
        for h in healths {
            providerList.append([
                "provider": h.providerID.rawValue,
                "name": h.displayName,
                "installed": h.isInstalled,
                "hookInstalled": h.hookInstalled,
                "supportLevel": h.supportLevel.rawValue,
                "status": h.statusMessage
            ])
        }
        report["providers"] = providerList
        
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted])
        return IPCResponse(success: true, message: "Doctor diagnostics completed", data: data)
    }
    
    private func handleFocus(sessionIDString: String?) async -> IPCResponse {
        guard let idStr = sessionIDString, !idStr.isEmpty else {
            // Focus most recent session
            if let recent = await sessionManager.getRecentSessions(limit: 1).first {
                let success = await focusController.manualFocusSession(recent)
                return IPCResponse(success: success, message: success ? "Restored focus to \(recent.projectName)" : "Failed to restore focus")
            }
            return IPCResponse(success: false, message: "No recent session found")
        }
        
        if let session = await sessionManager.getSession(id: AgentSessionID(idStr)) {
            let success = await focusController.manualFocusSession(session)
            return IPCResponse(success: success, message: success ? "Restored focus to \(session.projectName)" : "Failed to restore focus")
        }
        return IPCResponse(success: false, message: "Session '\(idStr)' not found")
    }
    
    private func handleFocusLock(argument: String?) -> IPCResponse {
        guard let arg = argument?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !arg.isEmpty else {
            // Toggle off if active
            if focusLock.isActive {
                focusLock = FocusLockState(isActive: false)
                return IPCResponse(success: true, message: "Focus Lock disabled")
            } else {
                // Default 30 minutes
                let exp = Date().addingTimeInterval(30 * 60)
                focusLock = FocusLockState(isActive: true, expiresAt: exp, label: "30 min")
                return IPCResponse(success: true, message: "Focus Lock enabled for 30 minutes")
            }
        }
        
        if arg == "off" || arg == "disable" || arg == "0" {
            focusLock = FocusLockState(isActive: false)
            return IPCResponse(success: true, message: "Focus Lock disabled")
        }
        
        var durationMinutes = 30
        if arg.hasSuffix("m") {
            let digits = arg.dropLast()
            durationMinutes = Int(digits) ?? 30
        } else if arg.hasSuffix("h") {
            let digits = arg.dropLast()
            durationMinutes = (Int(digits) ?? 1) * 60
        } else if let val = Int(arg) {
            durationMinutes = val
        }
        
        let exp = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
        focusLock = FocusLockState(isActive: true, expiresAt: exp, label: "\(durationMinutes) min")
        return IPCResponse(success: true, message: "Focus Lock enabled for \(durationMinutes) minutes")
    }
    
    private func handleRefresh() async -> IPCResponse {
        let discovered = await providerRegistry.discoverAllActiveSessions()
        if !discovered.isEmpty {
            await sessionManager.mergeDiscoveredSessions(discovered)
        }
        let active = await sessionManager.getActiveSessions()
        
        let report: [String: Any] = [
            "status": "refreshed",
            "activeSessionsCount": active.count,
            "activeSessions": active.map { session in
                [
                    "id": session.id.rawValue,
                    "projectName": session.projectName,
                    "provider": session.providerID.rawValue,
                    "state": session.state.rawValue,
                    "workspace": session.workspace ?? "unknown"
                ]
            }
        ]
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted])
        return IPCResponse(success: true, message: "Refreshed. \(active.count) active agent(s) found.", data: data)
    }
    
    private func handleHook(providerString: String?, payload: Data?) async -> IPCResponse {
        let allowData = "{\"decision\":\"allow\"}".data(using: .utf8)
        guard let provName = providerString else {
            return IPCResponse(success: true, message: "Missing provider name (safe pass-through)", data: allowData)
        }
        guard let data = payload else {
            return IPCResponse(success: true, message: "Missing hook payload (safe pass-through)", data: allowData)
        }
        
        let provID = AgentProviderID(provName)
        guard let provider = await providerRegistry.getProvider(provID) else {
            return IPCResponse(success: true, message: "Provider '\(provName)' not registered (safe pass-through)", data: allowData)
        }
        
        var isPreInvocation = false
        var isPostInvocation = false
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let hookName = json["hook_event_name"] as? String {
                if hookName.caseInsensitiveCompare("PreInvocation") == .orderedSame {
                    isPreInvocation = true
                } else if hookName.caseInsensitiveCompare("PostInvocation") == .orderedSame {
                    isPostInvocation = true
                }
            } else if json["invocationNum"] != nil && json["terminationReason"] == nil {
                isPreInvocation = true
            }
        }
        
        do {
            if let event = try provider.parseLifecyclePayload(data: data) {
                await eventBus.publish(agentEvent: event)
                logger.info("Published event from hook: \(event.type.rawValue)")
            }
        } catch {
            logger.error("Failed to parse hook payload for \(provName): \(error.localizedDescription)")
        }
        
        let responseStr: String
        if isPreInvocation {
            responseStr = "{\"injectSteps\":[]}"
        } else if isPostInvocation {
            responseStr = "{}"
        } else {
            responseStr = "{\"decision\":\"allow\"}"
        }
        let responseData = responseStr.data(using: .utf8)
        return IPCResponse(success: true, message: "Hook ingested", data: responseData)
    }
    
    private func handleEmit(payload: Data?) async -> IPCResponse {
        guard let data = payload else {
            return IPCResponse(success: false, message: "Missing emit payload")
        }
        guard let genericProvider = await providerRegistry.getProvider(.genericHook) else {
            return IPCResponse(success: false, message: "Generic hook provider unavailable")
        }
        
        do {
            if let event = try genericProvider.parseLifecyclePayload(data: data) {
                await eventBus.publish(agentEvent: event)
                return IPCResponse(success: true, message: "Event \(event.type.rawValue) emitted successfully")
            }
        } catch {
            return IPCResponse(success: false, message: "Failed to parse emit event: \(error.localizedDescription)")
        }
        
        return IPCResponse(success: false, message: "Could not emit event")
    }
    
    private func handleTestFocus() async -> IPCResponse {
        // Find frontmost application to simulate
        guard let front = NSWorkspace.shared.frontmostApplication else {
            return IPCResponse(success: false, message: "No frontmost application detected")
        }
        let testWs = (NSHomeDirectory() as NSString).appendingPathComponent("workspace/projects/focus-switcher")
        let testOrigin = OriginContext(
            bundleIdentifier: front.bundleIdentifier ?? "com.apple.finder",
            applicationPath: front.bundleURL?.path,
            processIdentifier: front.processIdentifier,
            workspacePath: testWs
        )
        let config = await settingsRepo.loadConfiguration()
        let testSession = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: testWs,
            originContext: testOrigin
        )
        
        let decision = await focusController.handleSessionCompletion(
            session: testSession,
            config: config,
            focusLock: focusLock
        )
        
        return IPCResponse(success: true, message: "Test focus evaluated: \(decision.explanation)")
    }
}
