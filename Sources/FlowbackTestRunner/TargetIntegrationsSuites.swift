import Foundation
import AppKit
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackTestHarness

// MARK: - Windsurf Integration Verification Suite

@MainActor
func runWindsurfIntegrationSuites() async {
    await testGroup("Windsurf Native Cascade Hook & Health Integration") {
        let tempDir = NSTemporaryDirectory() + "flowback_runner_windsurf_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        
        let provider = WindsurfProvider(globalConfigDir: tempDir)
        
        // 1. Health check before installation
        let initialHealth = await provider.checkHealth()
        assertTest(initialHealth.supportLevel == .nativeLifecycle, "WindsurfProvider supportLevel is nativeLifecycle")
        assertTest(!initialHealth.hookInstalled, "Windsurf hookInstalled is false before install")
        assertTest(initialHealth.statusMessage.contains("Cascade hooks not configured"), "Actionable diagnostic message before install")
        
        // 2. Safe install with user config preservation
        let hooksPath = (tempDir as NSString).appendingPathComponent("hooks.json")
        let userConfig = """
        {
            "hooks": {
                "pre_write_code": [
                    {
                        "command": "npx prettier --check",
                        "show_output": true
                    }
                ]
            }
        }
        """
        try userConfig.write(toFile: hooksPath, atomically: true, encoding: .utf8)
        
        try await provider.installIntegration()
        
        // Check backup creation
        let dirContents = (try? FileManager.default.contentsOfDirectory(atPath: tempDir)) ?? []
        let backupExists = dirContents.contains { $0.contains("hooks.json.bak.") }
        assertTest(backupExists, "Timestamped backup created before modifying Windsurf hooks.json")
        
        // Verify installation & preservation
        let installedHealth = await provider.checkHealth()
        assertTest(installedHealth.hookInstalled, "Windsurf hookInstalled is true after install")
        
        let installedData = try Data(contentsOf: URL(fileURLWithPath: hooksPath))
        let installedJson = (try? JSONSerialization.jsonObject(with: installedData)) as? [String: Any]
        let hooks = installedJson?["hooks"] as? [String: Any]
        let preWriteList = hooks?["pre_write_code"] as? [[String: Any]]
        
        assertTest(preWriteList?.contains { ($0["command"] as? String) == "npx prettier --check" } == true, "User's pre-existing prettier hook preserved")
        assertTest(preWriteList?.contains { ($0["command"] as? String)?.contains("flowback hook windsurf") == true } == true, "Flowback hook added to pre_write_code")
        assertTest(hooks?["pre_user_prompt"] != nil, "Flowback installed pre_user_prompt hook")
        assertTest(hooks?["post_cascade_response"] != nil, "Flowback installed post_cascade_response hook")
        assertTest(hooks?["post_cascade_response_with_transcript"] != nil, "Flowback installed post_cascade_response_with_transcript hook")
        
        // 3. Lifecycle Payload Normalization
        let startPayload = """
        {
            "agent_action_name": "pre_user_prompt",
            "trajectory_id": "traj-runner-100",
            "execution_id": "exec-01",
            "step_index": 1,
            "workspace_root": "/Users/abin/workspace/projects/flowback",
            "model_name": "cascade",
            "tool_info": { "prompt": "Implement target integrations" }
        }
        """.data(using: .utf8)!
        
        let startEvent = try provider.parseLifecyclePayload(data: startPayload)
        assertTest(startEvent?.type == .agentStarted, "pre_user_prompt (step 1) normalizes to .agentStarted")
        assertTest(startEvent?.sessionID.rawValue == "traj-runner-100", "Preserves trajectory_id as sessionID")
        assertTest(startEvent?.metadata["executionId"] == "exec-01", "Preserves execution_id")
        assertTest(startEvent?.metadata["deduplicationKey"] == "windsurf:traj-runner-100:pre_user_prompt:exec-01", "Generates granular deduplication key")
        
        // 4. Progress and Tool Normalization
        let progressPayload = """
        {
            "agent_action_name": "post_write_code",
            "trajectory_id": "traj-runner-100",
            "execution_id": "exec-02",
            "workspace_root": "/Users/abin/workspace/projects/flowback",
            "tool_info": { "path": "Sources/Windsurf.swift" }
        }
        """.data(using: .utf8)!
        let progEvent = try provider.parseLifecyclePayload(data: progressPayload)
        assertTest(progEvent?.type == .agentProgress, "post_write_code normalizes to .agentProgress")
        
        // 5. Permission Required Normalization
        let confirmPayload = """
        {
            "agent_action_name": "pre_run_command",
            "trajectory_id": "traj-runner-100",
            "execution_id": "exec-03",
            "tool_info": { "command": "rm -rf temp", "requires_confirmation": true }
        }
        """.data(using: .utf8)!
        let confirmEvent = try provider.parseLifecyclePayload(data: confirmPayload)
        assertTest(confirmEvent?.type == .agentPermissionRequired, "requires_confirmation: true normalizes to .agentPermissionRequired")
        
        // 6. Completion Normalization
        let completePayload = """
        {
            "agent_action_name": "post_cascade_response",
            "trajectory_id": "traj-runner-100",
            "execution_id": "exec-04",
            "tool_info": { "response": "Completed task." }
        }
        """.data(using: .utf8)!
        let compEvent = try provider.parseLifecyclePayload(data: completePayload)
        assertTest(compEvent?.type == .agentCompleted, "post_cascade_response normalizes to .agentCompleted")
        
        // 7. Error Normalization
        let errorPayload = """
        {
            "agent_action_name": "post_run_command",
            "trajectory_id": "traj-runner-100",
            "error": "Command failed"
        }
        """.data(using: .utf8)!
        let errEvent = try provider.parseLifecyclePayload(data: errorPayload)
        assertTest(errEvent?.type == .agentFailed, "Cascade error field normalizes to .agentFailed")
        
        // 8. Clean Uninstallation
        try await provider.uninstallIntegration()
        let cleanHealth = await provider.checkHealth()
        assertTest(!cleanHealth.hookInstalled, "hookInstalled is false after clean uninstall")
        
        let cleanedData = try Data(contentsOf: URL(fileURLWithPath: hooksPath))
        let cleanedJson = (try? JSONSerialization.jsonObject(with: cleanedData)) as? [String: Any]
        let cleanedHooks = cleanedJson?["hooks"] as? [String: Any]
        let remainingPreWrite = cleanedHooks?["pre_write_code"] as? [[String: Any]]
        assertTest(remainingPreWrite?.contains { ($0["command"] as? String) == "npx prettier --check" } == true, "User's prettier hook preserved after uninstall")
        assertTest(remainingPreWrite?.contains { ($0["command"] as? String)?.contains("flowback hook windsurf") == true } == false, "Flowback hook removed cleanly from pre_write_code")
        
        // 9. WindsurfAdapter Verification
        let adapter = WindsurfAdapter()
        assertTest(adapter.canHandle(bundleIdentifier: "com.codeium.windsurf"), "WindsurfAdapter canHandle com.codeium.windsurf")
        assertTest(!adapter.canHandle(bundleIdentifier: "com.microsoft.VSCode"), "WindsurfAdapter rejects non-Windsurf bundles")
        
        let registryAdapter = ApplicationAdapterRegistry.shared.findAdapter(for: "com.codeium.windsurf")
        assertTest(registryAdapter?.adapterName == "Windsurf Editor Adapter", "Registry selects WindsurfAdapter for com.codeium.windsurf")
    }
}

// MARK: - OpenCode Integration Verification Suite

@MainActor
func runOpenCodeIntegrationSuites() async {
    await testGroup("OpenCode Official Plugin API & Event Ingestion") {
        let tempConfig = NSTemporaryDirectory() + "flowback_runner_opencode_\(UUID().uuidString)"
        let tempPlugins = (tempConfig as NSString).appendingPathComponent("plugins")
        try FileManager.default.createDirectory(atPath: tempPlugins, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempConfig) }
        
        let provider = OpenCodeProvider(
            configDir: tempConfig,
            pluginInstallDir: tempPlugins,
            appBundlePath: "/Applications/OpenCode.app"
        )
        
        // 1. Initial health
        let initialHealth = await provider.checkHealth()
        assertTest(initialHealth.supportLevel == .nativeLifecycle, "OpenCodeProvider supportLevel is nativeLifecycle")
        assertTest(!initialHealth.hookInstalled, "OpenCode plugin hookInstalled is false before install")
        
        // 2. Install plugin
        try await provider.installIntegration()
        let pluginFile = (tempPlugins as NSString).appendingPathComponent("flowback.js")
        assertTest(FileManager.default.fileExists(atPath: pluginFile), "flowback.js plugin written to ~/.config/opencode/plugins")
        
        let installedHealth = await provider.checkHealth()
        assertTest(installedHealth.hookInstalled, "OpenCode hookInstalled is true after plugin installation")
        
        let configPath = (tempConfig as NSString).appendingPathComponent("opencode.json")
        let configData = (try? Data(contentsOf: URL(fileURLWithPath: configPath))) ?? Data()
        let configJson = (try? JSONSerialization.jsonObject(with: configData)) as? [String: Any]
        let pluginsList = configJson?["plugins"] as? [String]
        assertTest(pluginsList?.contains("flowback") == true, "opencode.json updated with flowback plugin reference")
        
        // 3. Event normalization: session.created
        let startPayload = """
        {
            "event": "session.created",
            "sessionId": "opencode-sess-99",
            "directory": "/Users/abin/workspace/projects/flowback",
            "projectId": "flowback"
        }
        """.data(using: .utf8)!
        let startEvent = try provider.parseLifecyclePayload(data: startPayload)
        assertTest(startEvent?.type == .agentStarted, "session.created normalizes to .agentStarted")
        assertTest(startEvent?.sessionID.rawValue == "opencode-sess-99", "Preserves sessionId")
        assertTest(startEvent?.workspace == "/Users/abin/workspace/projects/flowback", "Preserves workspace directory")
        assertTest(startEvent?.metadata["projectId"] == "flowback", "Preserves projectId")
        
        // 4. Tool execution with permission
        let permPayload = """
        {
            "event": "tool.execute.before",
            "sessionId": "opencode-sess-99",
            "tool": {
                "name": "bash",
                "callId": "call-1",
                "requiresPermission": true
            }
        }
        """.data(using: .utf8)!
        let permEvent = try provider.parseLifecyclePayload(data: permPayload)
        assertTest(permEvent?.type == .agentPermissionRequired, "tool.execute.before with permission normalizes to .agentPermissionRequired")
        
        // 5. Tool execution completed (progress)
        let progPayload = """
        {
            "event": "tool.execute.after",
            "sessionId": "opencode-sess-99",
            "tool": { "name": "bash", "callId": "call-1", "status": "finished" }
        }
        """.data(using: .utf8)!
        let progEvent = try provider.parseLifecyclePayload(data: progPayload)
        assertTest(progEvent?.type == .agentProgress, "tool.execute.after normalizes to .agentProgress")
        
        // 6. Completion
        let idlePayload = """
        {
            "event": "session.idle",
            "sessionId": "opencode-sess-99"
        }
        """.data(using: .utf8)!
        let idleEvent = try provider.parseLifecyclePayload(data: idlePayload)
        assertTest(idleEvent?.type == .agentCompleted, "session.idle normalizes to .agentCompleted")
        
        // 7. Cancellation
        let cancelPayload = """
        {
            "event": "session.deleted",
            "sessionId": "opencode-sess-99"
        }
        """.data(using: .utf8)!
        let cancelEvent = try provider.parseLifecyclePayload(data: cancelPayload)
        assertTest(cancelEvent?.type == .agentCancelled, "session.deleted normalizes to .agentCancelled")
        
        // 8. Clean uninstall
        try await provider.uninstallIntegration()
        assertTest(!FileManager.default.fileExists(atPath: pluginFile), "flowback.js removed on uninstall")
        let uninstalledHealth = await provider.checkHealth()
        assertTest(!uninstalledHealth.hookInstalled, "hookInstalled is false after uninstall")
    }
}

// MARK: - Cursor Background Agent Verification Suite

@MainActor
func runCursorBackgroundIntegrationSuites() async {
    await testGroup("Cursor Local Adapter & Remote Cloud Agent API") {
        // 1. Local CursorAdapter Multi-Bundle & Heuristic Handling
        let localAdapter = CursorAdapter()
        assertTest(localAdapter.canHandle(bundleIdentifier: "com.todesktop.230313mzl4w4u92"), "Handles com.todesktop.230313mzl4w4u92")
        assertTest(localAdapter.canHandle(bundleIdentifier: "co.anysphere.cursor"), "Handles co.anysphere.cursor")
        assertTest(localAdapter.canHandle(bundleIdentifier: "com.cursor.Cursor"), "Handles com.cursor.Cursor")
        assertTest(!localAdapter.canHandle(bundleIdentifier: "com.microsoft.VSCode"), "Rejects VSCode")
        
        // Mock controller restoration with exact window and fallback
        let mockApp = MockApplicationController()
        let mockWin = MockWindowController()
        let curPid = NSRunningApplication.current.processIdentifier
        
        let originWithExact = OriginContext(
            bundleIdentifier: "co.anysphere.cursor",
            processIdentifier: curPid,
            windowIdentifier: 101,
            workspacePath: "/Users/abin/workspace/projects/flowback"
        )
        mockWin.windowsMock.append(WindowInfo(
            windowID: 101,
            processIdentifier: curPid,
            ownerName: "Cursor",
            title: "flowback — Cursor",
            bounds: .zero,
            isOnScreen: true
        ))
        
        let exactRestored = await localAdapter.restoreContext(context: originWithExact, appController: mockApp, windowController: mockWin)
        assertTest(exactRestored, "Local CursorAdapter restores exact window successfully")
        
        // Stale/missing window falling back to workspace matching
        let originMissingWin = OriginContext(
            bundleIdentifier: "co.anysphere.cursor",
            processIdentifier: curPid,
            windowIdentifier: 9999, // stale window ID
            workspacePath: "/Users/abin/workspace/projects/flowback"
        )
        let fallbackRestored = await localAdapter.restoreContext(context: originMissingWin, appController: mockApp, windowController: mockWin)
        assertTest(fallbackRestored, "Local CursorAdapter gracefully recovers from stale window ID via workspace match")
        
        // 2. Remote CursorBackgroundProvider Authentication & Diagnostics
        let unconfiguredProvider = CursorBackgroundProvider(apiKeyProvider: { nil })
        let unconfiguredHealth = await unconfiguredProvider.checkHealth()
        assertTest(!unconfiguredHealth.isInstalled, "Unconfigured provider reports isInstalled = false")
        assertTest(unconfiguredHealth.supportLevel == .partial, "Unconfigured provider reports supportLevel = partial")
        assertTest(unconfiguredHealth.statusMessage.contains("CURSOR_API_KEY"), "Unconfigured status guides user on API key setup")
        
        let configuredProvider = CursorBackgroundProvider(apiKeyProvider: { "crs_secret_live_token" })
        let configuredHealth = await configuredProvider.checkHealth()
        assertTest(configuredHealth.isInstalled, "Configured provider reports isInstalled = true")
        assertTest(configuredHealth.supportLevel == .nativeLifecycle, "Configured provider reports supportLevel = nativeLifecycle")
        assertTest(!configuredHealth.statusMessage.contains("crs_secret_live_token"), "Credentials never leaked in health message")
        
        // 3. Remote Cloud Agent Lifecycle Normalization
        let runningPayload = """
        {
            "id": "agent-cloud-run-1",
            "status": "RUNNING",
            "repository": "https://github.com/rapheljr/flowback.git",
            "branchName": "cursor/feat-agent",
            "latestRunId": "run-01"
        }
        """.data(using: .utf8)!
        let runningEvent = try configuredProvider.parseLifecyclePayload(data: runningPayload)
        assertTest(runningEvent?.type == .agentRunning, "RUNNING normalizes to .agentRunning")
        assertTest(runningEvent?.metadata["repositoryUrl"] == "https://github.com/rapheljr/flowback.git", "Preserves repository URL")
        assertTest(runningEvent?.metadata["branch"] == "cursor/feat-agent", "Preserves branch name")
        assertTest(runningEvent?.metadata["latestRunId"] == "run-01", "Preserves latest run ID")
        assertTest(runningEvent?.metadata["isSubagent"] == nil, "Top-level cloud agent is not marked as subagent")
        
        let completedPayload = """
        {
            "id": "agent-cloud-run-1",
            "status": "COMPLETED",
            "repository": "https://github.com/rapheljr/flowback.git",
            "prUrl": "https://github.com/rapheljr/flowback/pull/15",
            "latestRunId": "run-02"
        }
        """.data(using: .utf8)!
        let compEvent = try configuredProvider.parseLifecyclePayload(data: completedPayload)
        assertTest(compEvent?.type == .agentCompleted, "COMPLETED normalizes to .agentCompleted")
        assertTest(compEvent?.metadata["prUrl"] == "https://github.com/rapheljr/flowback/pull/15", "Preserves pull request URL")
        
        let failedPayload = """
        {
            "id": "agent-cloud-run-2",
            "status": "FAILED",
            "error": "Cloud sandbox build failed"
        }
        """.data(using: .utf8)!
        let failEvent = try configuredProvider.parseLifecyclePayload(data: failedPayload)
        assertTest(failEvent?.type == .agentFailed, "FAILED normalizes to .agentFailed")
        assertTest(failEvent?.metadata["error"] == "Cloud sandbox build failed", "Preserves cloud failure description")
        
        // 4. Subagent Relationship Tracking
        let subagentPayload = """
        {
            "id": "agent-cloud-sub-88",
            "parentAgentId": "agent-cloud-run-1",
            "status": "RUNNING",
            "repository": "https://github.com/rapheljr/flowback.git",
            "latestRunId": "subrun-01"
        }
        """.data(using: .utf8)!
        let subEvent = try configuredProvider.parseLifecyclePayload(data: subagentPayload)
        assertTest(subEvent?.metadata["isSubagent"] == "true", "Child agent identified as subagent")
        assertTest(subEvent?.metadata["parentSessionId"] == "agent-cloud-run-1", "Linked to parent agent session")
        
        // 5. Remote Context Restoration: Local match vs Notification fallback
        // When repo is flowback, findLocalWorkspace matches /Users/abin/workspace/projects/flowback
        assertTest(runningEvent?.origin?.restorationCapability == .workspaceWindow, "Local clone detected -> .workspaceWindow capability")
        
        let remoteOnlyPayload = """
        {
            "id": "agent-cloud-no-clone",
            "status": "COMPLETED",
            "repository": "https://github.com/other-org/remote-only-repo.git",
            "prUrl": "https://github.com/other-org/remote-only-repo/pull/1"
        }
        """.data(using: .utf8)!
        let remoteOnlyEvent = try configuredProvider.parseLifecyclePayload(data: remoteOnlyPayload)
        assertTest(remoteOnlyEvent?.origin?.restorationCapability == .notificationFallbackOnly, "No local clone -> .notificationFallbackOnly navigation capability")
    }
}

// MARK: - Multi-Agent Concurrency & Shared Reliability Suite

@MainActor
func runMultiAgentConcurrencyAndSharedReliabilitySuites() async {
    await testGroup("Multi-Agent Concurrency & Shared Reliability") {
        let tempDb = NSTemporaryDirectory() + "flowback_runner_concurrency_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let repo = SessionRepository(db: db)
        let sessionManager = SessionManager(storageDelegate: repo)
        let deduplicator = EventDeduplicator(window: 1.0)
        
        // 1. Concurrent Sessions across all 3 providers
        let windsurfSessionID = AgentSessionID("traj-windsurf-concurrent")
        let opencodeSessionID = AgentSessionID("opencode-concurrent-sess")
        let cursorSessionID = AgentSessionID("cursor-cloud-concurrent")
        
        let now = Date()
        let wStart = AgentEvent(
            timestamp: now,
            providerID: .windsurf,
            sessionID: windsurfSessionID,
            type: .agentStarted,
            workspace: "/Users/abin/workspace/projects/flowback",
            metadata: ["executionId": "e1"]
        )
        let oStart = AgentEvent(
            timestamp: now,
            providerID: .openCode,
            sessionID: opencodeSessionID,
            type: .agentStarted,
            workspace: "/Users/abin/workspace/projects/opencode-app"
        )
        let cStart = AgentEvent(
            timestamp: now,
            providerID: .cursorBackground,
            sessionID: cursorSessionID,
            type: .agentRunning,
            workspace: "/Users/abin/workspace/projects/cursor-task"
        )
        
        _ = await sessionManager.handleEvent(wStart)
        _ = await sessionManager.handleEvent(oStart)
        _ = await sessionManager.handleEvent(cStart)
        
        let active = await sessionManager.getActiveSessions()
        assertTest(active.count == 3, "3 concurrent agent sessions tracked simultaneously across Windsurf, OpenCode, and Cursor")
        
        let wSession = await sessionManager.getSession(id: windsurfSessionID)
        let oSession = await sessionManager.getSession(id: opencodeSessionID)
        let cSession = await sessionManager.getSession(id: cursorSessionID)
        
        assertTest(wSession?.providerID == .windsurf, "Windsurf session preserved in isolation")
        assertTest(oSession?.providerID == .openCode, "OpenCode session preserved in isolation")
        assertTest(cSession?.providerID == .cursorBackground, "Cursor session preserved in isolation")
        
        // 2. Sliding Window Deduplication
        let dup1 = await deduplicator.shouldProcess(event: wStart)
        assertTest(dup1 == true, "First unique Windsurf event accepted")
        let dup2 = await deduplicator.shouldProcess(event: wStart)
        assertTest(dup2 == false, "Immediate duplicate Windsurf event dropped by sliding window")
        
        // Event for different provider/session is accepted
        let dup3 = await deduplicator.shouldProcess(event: oStart)
        assertTest(dup3 == true, "Event for different session accepted without cross-provider blocking")
        
        // 3. Out-of-Order / Stale Event Rejection
        let oldTimestamp = now.addingTimeInterval(-60.0)
        let staleEvent = AgentEvent(
            timestamp: oldTimestamp,
            providerID: .windsurf,
            sessionID: windsurfSessionID,
            type: .agentProgress,
            workspace: "/Users/abin/workspace/projects/flowback"
        )
        let sessionAfterStale = await sessionManager.handleEvent(staleEvent)
        assertTest(sessionAfterStale.updatedAt >= now, "Stale event with old timestamp did not roll back session state")
        
        // 4. Sequential Lifecycle Progression
        let wComp = AgentEvent(
            timestamp: Date(),
            providerID: .windsurf,
            sessionID: windsurfSessionID,
            type: .agentCompleted,
            workspace: "/Users/abin/workspace/projects/flowback"
        )
        _ = await sessionManager.handleEvent(wComp)
        let wUpdated = await sessionManager.getSession(id: windsurfSessionID)
        assertTest(wUpdated?.state == .completed, "Windsurf session transitioned cleanly to .completed")
        assertTest(wUpdated?.completedAt != nil, "Completion timestamp recorded")
        
        let remainingActive = await sessionManager.getActiveSessions()
        assertTest(remainingActive.count == 2, "Active sessions decreased to 2 after Windsurf completes")
        
        // 5. Crash Recovery / Startup Reconciliation
        await sessionManager.reconcileOrphanedSessions()
        let oReconciled = await sessionManager.getSession(id: opencodeSessionID)
        let cReconciled = await sessionManager.getSession(id: cursorSessionID)
        assertTest(oReconciled?.state == .cancelled, "Active OpenCode session marked .cancelled during restart reconciliation")
        assertTest(cReconciled?.state == .cancelled, "Active Cursor session marked .cancelled during restart reconciliation")
        assertTest(oReconciled?.errorDescription?.contains("restart") == true, "Reconciled session explains cancellation reason")
        
        let activeAfterReconciliation = await sessionManager.getActiveSessions()
        assertTest(activeAfterReconciliation.isEmpty, "No orphaned active sessions remain after reconciliation")
        
        await db.close()
        try? FileManager.default.removeItem(atPath: tempDb)
        try? FileManager.default.removeItem(atPath: "\(tempDb)-wal")
        try? FileManager.default.removeItem(atPath: "\(tempDb)-shm")
    }
}
