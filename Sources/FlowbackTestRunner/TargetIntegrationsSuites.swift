import Foundation
import AppKit
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackTestHarness

// MARK: - Mock HTTP Transport for Injectable Provider Testing

final class MockHTTPTransport: HTTPDataLoading, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let lock = NSLock()
    private var handler: Handler
    private var requestCountVal = 0

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCountVal
    }

    func setHandler(_ newHandler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = newHandler
    }

    private func getAndIncrementHandler() -> Handler {
        lock.lock()
        defer { lock.unlock() }
        requestCountVal += 1
        return self.handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let currentHandler = getAndIncrementHandler()
        return try await currentHandler(request)
    }
}

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

        // 2. Safe install with user config preservation & Apple Silicon / Intel PATH
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

        let flowbackHook = preWriteList?.first { ($0["command"] as? String)?.contains("flowback hook windsurf") == true }
        let cmdString = flowbackHook?["command"] as? String ?? ""
        assertTest(cmdString.contains("/opt/homebrew/bin"), "Hook command includes /opt/homebrew/bin for Apple Silicon")
        assertTest(cmdString.contains("/usr/local/bin"), "Hook command includes /usr/local/bin for Intel Macs")
        assertTest(cmdString.contains("$PATH"), "Hook command preserves user's existing PATH without overriding")

        assertTest(hooks?["pre_user_prompt"] != nil, "Flowback installed pre_user_prompt hook")
        assertTest(hooks?["post_cascade_response"] != nil, "Flowback installed post_cascade_response hook")
        assertTest(hooks?["post_cascade_response_with_transcript"] != nil, "Flowback installed post_cascade_response_with_transcript hook")

        // 3. Lifecycle Payload Normalization: step_index handling & multi-turn
        provider.resetKnownTrajectories()

        let step1Payload = """
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
        let step1Event = try provider.parseLifecyclePayload(data: step1Payload)
        assertTest(step1Event?.type == .agentStarted, "pre_user_prompt (step 1) normalizes to .agentStarted")
        assertTest(step1Event?.sessionID.rawValue == "traj-runner-100", "Preserves trajectory_id as sessionID")
        assertTest(step1Event?.metadata["executionId"] == "exec-01", "Preserves execution_id")
        assertTest(step1Event?.metadata["deduplicationKey"] == "windsurf:traj-runner-100:pre_user_prompt:exec-01", "Generates granular deduplication key with execution_id")

        // Step 2 with step_index
        let step2Payload = """
        {
            "agent_action_name": "pre_user_prompt",
            "trajectory_id": "traj-runner-100",
            "execution_id": "exec-02",
            "step_index": 2,
            "workspace_root": "/Users/abin/workspace/projects/flowback",
            "tool_info": { "prompt": "Continue implementation" }
        }
        """.data(using: .utf8)!
        let step2Event = try provider.parseLifecyclePayload(data: step2Payload)
        assertTest(step2Event?.type == .agentRunning, "pre_user_prompt (step > 1) normalizes to .agentRunning")

        // Fresh trajectory with MISSING step_index -> .agentStarted
        let freshNoStepPayload = """
        {
            "agent_action_name": "pre_user_prompt",
            "trajectory_id": "traj-runner-200",
            "workspace_root": "/Users/abin/workspace/projects/flowback",
            "tool_info": { "prompt": "Fresh trajectory prompt without step_index" }
        }
        """.data(using: .utf8)!
        let freshNoStepEvent = try provider.parseLifecyclePayload(data: freshNoStepPayload)
        assertTest(freshNoStepEvent?.type == .agentStarted, "Missing step_index on brand new trajectory normalizes to .agentStarted")

        // Follow-up prompt on SAME trajectory with MISSING step_index -> .agentRunning (not a brand new session!)
        let followUpNoStepPayload = """
        {
            "agent_action_name": "pre_user_prompt",
            "trajectory_id": "traj-runner-200",
            "workspace_root": "/Users/abin/workspace/projects/flowback",
            "tool_info": { "prompt": "Follow up prompt on same trajectory without step_index" }
        }
        """.data(using: .utf8)!
        let followUpNoStepEvent = try provider.parseLifecyclePayload(data: followUpNoStepPayload)
        assertTest(followUpNoStepEvent?.type == .agentRunning, "Missing step_index on existing trajectory normalizes to .agentRunning")

        // Verify deduplication key differs when prompt changes and execution_id is absent
        assertTest(freshNoStepEvent?.metadata["deduplicationKey"] != followUpNoStepEvent?.metadata["deduplicationKey"], "Distinct prompts generate distinct deduplication keys without execution_id")

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

        // 2. Install plugin preserving existing user config and avoiding opencode.json pollution
        let configPath = (tempConfig as NSString).appendingPathComponent("opencode.json")
        let userConfig: [String: Any] = [
            "theme": "nord",
            "plugins": ["custom-user-plugin"]
        ]
        let userConfigData = try JSONSerialization.data(withJSONObject: userConfig, options: [.prettyPrinted])
        try userConfigData.write(to: URL(fileURLWithPath: configPath))

        try await provider.installIntegration()
        let pluginFile = (tempPlugins as NSString).appendingPathComponent("flowback.js")
        assertTest(FileManager.default.fileExists(atPath: pluginFile), "flowback.js plugin written to ~/.config/opencode/plugins")

        let installedHealth = await provider.checkHealth()
        assertTest(installedHealth.hookInstalled, "OpenCode hookInstalled is true after plugin installation")

        // Verify opencode.json was NOT mutated to include 'flowback' (which would trigger invalid npm resolution)
        let configDataAfterInstall = (try? Data(contentsOf: URL(fileURLWithPath: configPath))) ?? Data()
        let configJsonAfterInstall = (try? JSONSerialization.jsonObject(with: configDataAfterInstall)) as? [String: Any]
        let pluginsList = configJsonAfterInstall?["plugins"] as? [String]
        assertTest(pluginsList?.contains("custom-user-plugin") == true, "User's existing plugin preserved in opencode.json")
        assertTest(pluginsList?.contains("flowback") == false, "opencode.json NOT contaminated with local plugin as npm package")
        assertTest(configJsonAfterInstall?["theme"] as? String == "nord", "User configuration fields preserved in opencode.json")

        // 3. Legacy entry cleanup test: If opencode.json previously contained a broken 'flowback' package reference
        let legacyConfig: [String: Any] = [
            "plugins": ["custom-user-plugin", "flowback"]
        ]
        let legacyConfigData = try JSONSerialization.data(withJSONObject: legacyConfig, options: [.prettyPrinted])
        try legacyConfigData.write(to: URL(fileURLWithPath: configPath))

        try await provider.installIntegration()
        let cleanedConfigData = (try? Data(contentsOf: URL(fileURLWithPath: configPath))) ?? Data()
        let cleanedConfigJson = (try? JSONSerialization.jsonObject(with: cleanedConfigData)) as? [String: Any]
        let cleanedPlugins = cleanedConfigJson?["plugins"] as? [String]
        assertTest(cleanedPlugins?.contains("flowback") == false, "Legacy flowback entry cleaned up from opencode.json")
        assertTest(cleanedPlugins?.contains("custom-user-plugin") == true, "User plugin preserved during legacy cleanup")

        // 4. Repeated installation is idempotent
        try await provider.installIntegration()
        assertTest(FileManager.default.fileExists(atPath: pluginFile), "Repeated install is idempotent")

        // 5. Multi-turn Lifecycle: session.created -> tool execution -> session.idle (waiting) -> resumption -> completed
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

        // Tool execution with permission
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

        // Tool execution finished (progress)
        let progPayload = """
        {
            "event": "tool.execute.after",
            "sessionId": "opencode-sess-99",
            "tool": { "name": "bash", "callId": "call-1", "status": "finished" }
        }
        """.data(using: .utf8)!
        let progEvent = try provider.parseLifecyclePayload(data: progPayload)
        assertTest(progEvent?.type == .agentProgress, "tool.execute.after normalizes to .agentProgress")

        // Turn ended: session.idle normalizes to .agentWaiting (resumable, not terminal completion!)
        let idlePayload = """
        {
            "event": "session.idle",
            "sessionId": "opencode-sess-99"
        }
        """.data(using: .utf8)!
        let idleEvent = try provider.parseLifecyclePayload(data: idlePayload)
        assertTest(idleEvent?.type == .agentWaiting, "session.idle normalizes to .agentWaiting (resumable waiting for prompt)")

        // Verify state machine allows resumption: waiting -> running
        let sm = AgentStateMachine()
        assertTest(sm.canTransition(from: .waiting, to: .running), "State machine allows multi-turn prompt resumption (.waiting -> .running)")

        // Genuine terminal session completion
        let completedPayload = """
        {
            "event": "session.completed",
            "sessionId": "opencode-sess-99"
        }
        """.data(using: .utf8)!
        let compEvent = try provider.parseLifecyclePayload(data: completedPayload)
        assertTest(compEvent?.type == .agentCompleted, "session.completed normalizes to .agentCompleted")

        // Cancellation
        let cancelPayload = """
        {
            "event": "session.deleted",
            "sessionId": "opencode-sess-99"
        }
        """.data(using: .utf8)!
        let cancelEvent = try provider.parseLifecyclePayload(data: cancelPayload)
        assertTest(cancelEvent?.type == .agentCancelled, "session.deleted normalizes to .agentCancelled")

        // Failure
        let errorPayload = """
        {
            "event": "session.error",
            "sessionId": "opencode-sess-99",
            "error": "Model context window exceeded"
        }
        """.data(using: .utf8)!
        let errEvent = try provider.parseLifecyclePayload(data: errorPayload)
        assertTest(errEvent?.type == .agentFailed, "session.error normalizes to .agentFailed")
        assertTest(errEvent?.metadata["error"] == "Model context window exceeded", "Preserves error message")

        // 6. Clean uninstall
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
        assertTest(remoteOnlyEvent?.origin?.workspacePath == "https://github.com/other-org/remote-only-repo/pull/1", "Remote origin records PR destination URL")

        // 6. Direct Remote Web URL Opening through FocusController
        final class URLRecordingBox: @unchecked Sendable {
            var openedURLs: [URL] = []
        }
        let urlRecorder = URLRecordingBox()
        let customFocusController = FocusController(
            appController: mockApp,
            windowController: mockWin,
            urlOpener: { url in
                urlRecorder.openedURLs.append(url)
                return true
            }
        )

        if let origin = remoteOnlyEvent?.origin {
            let restored = await customFocusController.restoreContext(origin)
            assertTest(restored == true, "FocusController opens remote destination URL via workspace opener")
            assertTest(urlRecorder.openedURLs.first?.absoluteString == "https://github.com/other-org/remote-only-repo/pull/1", "Opened destination URL matches pull request URL")
        }

        // Malformed or unsafe URL scheme rejection
        let unsafeOrigin = OriginContext(
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 0,
            workspacePath: "javascript:alert('malicious')"
        )
        let unsafeRestored = await customFocusController.restoreContext(unsafeOrigin)
        assertTest(unsafeRestored == false, "FocusController rejects non-http/https URL schemes for security")

        // 7. Injectable HTTP Client: Pagination, Rate-Limiting, Server Errors, and Key Protection
        let page1JSON = """
        {
            "agents": [
                { "id": "agent-page-1-a", "status": "RUNNING", "repository": "https://github.com/test/repo1" },
                { "id": "agent-page-1-b", "status": "WAITING", "repository": "https://github.com/test/repo2" }
            ],
            "nextCursor": "cursor-page-2"
        }
        """.data(using: .utf8)!

        let page2JSON = """
        {
            "agents": [
                { "id": "agent-page-2-a", "status": "COMPLETED", "prUrl": "https://github.com/test/repo1/pull/1" }
            ],
            "nextCursor": null
        }
        """.data(using: .utf8)!

        let mockTransport = MockHTTPTransport { req in
            let urlStr = req.url?.absoluteString ?? ""
            if urlStr.contains("cursor=cursor-page-2") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (page2JSON, resp)
            } else {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (page1JSON, resp)
            }
        }

        let testProvider = CursorBackgroundProvider(
            apiKeyProvider: { "crs_mock_key_123" },
            httpClient: mockTransport
        )

        let discoveredPages = await testProvider.discoverActiveSessions()
        assertTest(discoveredPages.count == 3, "Pagination fetches agents across multiple pages (3 total)")
        assertTest(mockTransport.requestCount == 2, "Pagination made exactly 2 HTTP requests for 2 pages")

        // HTTP 429 Rate Limiting with Retry-After
        mockTransport.setHandler { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "20"])!
            return (Data(), resp)
        }
        let rateLimited = await testProvider.discoverActiveSessions()
        assertTest(rateLimited.isEmpty, "HTTP 429 returns empty discovered sessions during rate limit")

        let countBeforeImmediate = mockTransport.requestCount
        let backoffSkipped = await testProvider.discoverActiveSessions()
        assertTest(backoffSkipped.isEmpty, "Immediate query during backoff window skipped without network request")
        assertTest(mockTransport.requestCount == countBeforeImmediate, "No network request made during active rate-limit backoff")

        // HTTP 401 Unauthorized handling
        mockTransport.setHandler { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), resp)
        }
        let authProvider = CursorBackgroundProvider(
            apiKeyProvider: { "invalid_key" },
            httpClient: mockTransport
        )
        _ = await authProvider.discoverActiveSessions()
        let authHealth = await authProvider.checkHealth()
        assertTest(authHealth.statusMessage.contains("authentication failed"), "Diagnostic health reports HTTP 401 auth failure")
        assertTest(!authHealth.statusMessage.contains("invalid_key"), "Health message never leaks configured credentials")
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

        // 5. Crash Recovery / Startup & Wake Reconciliation
        // Local process sessions (OpenCode) are cancelled on restart/wake.
        // Remote cloud sessions (Cursor) run independently of the local Mac host and MUST survive.
        await sessionManager.reconcileOrphanedSessions()
        let oReconciled = await sessionManager.getSession(id: opencodeSessionID)
        let cReconciled = await sessionManager.getSession(id: cursorSessionID)

        assertTest(oReconciled?.state == .cancelled, "Active local OpenCode session marked .cancelled during restart reconciliation")
        assertTest(oReconciled?.errorDescription?.contains("restart") == true, "Reconciled session explains local cancellation reason")
        assertTest(cReconciled?.state == .running, "Remote Cursor background session preserved as .running across restart/wake")

        let activeAfterReconciliation = await sessionManager.getActiveSessions()
        assertTest(activeAfterReconciliation.count == 1, "Only remote cloud agent remains active after local restart reconciliation")

        await db.close()
        try? FileManager.default.removeItem(atPath: tempDb)
        try? FileManager.default.removeItem(atPath: "\(tempDb)-wal")
        try? FileManager.default.removeItem(atPath: "\(tempDb)-shm")
    }
}

// MARK: - Cloud Discovery & Lifecycle Regression Suite (Phase 2.A & 2.C)

@MainActor
func runCloudDiscoveryAndLifecycleRegressionSuites() async {
    await testGroup("Cloud Discovery State Transitions & Event Bus Delivery") {
        let tempDb = NSTemporaryDirectory() + "flowback_runner_cloud_discovery_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let repo = SessionRepository(db: db)
        let eventBus = EventBus()
        let sessionManager = SessionManager(storageDelegate: repo, eventBus: eventBus)

        // 1. Set up an active running cloud agent session
        let cloudSessID = AgentSessionID("agent-cloud-sess-100")
        let startEvent = AgentEvent(
            timestamp: Date(),
            providerID: .cursorBackground,
            sessionID: cloudSessID,
            type: .agentRunning,
            workspace: "https://github.com/rapheljr/flowback"
        )
        _ = await sessionManager.handleEvent(startEvent)

        let initialSession = await sessionManager.getSession(id: cloudSessID)
        assertTest(initialSession?.state == .running, "Initial cloud session is in .running state")

        // 2. Discover terminal state: Running -> Completed via mergeDiscoveredSessions
        let discoveredCompleted = AgentSession(
            id: cloudSessID,
            providerID: .cursorBackground,
            providerSessionID: "agent-cloud-sess-100",
            state: .completed,
            workspace: "https://github.com/rapheljr/flowback",
            completedAt: Date(),
            metadata: ["prUrl": "https://github.com/rapheljr/flowback/pull/99"]
        )

        let emittedEvents = await sessionManager.mergeDiscoveredSessions([discoveredCompleted])
        assertTest(emittedEvents.count == 1, "Discovered completion emits exactly 1 event for downstream consumers")
        assertTest(emittedEvents.first?.type == .agentCompleted, "Emitted event type is .agentCompleted")
        assertTest(emittedEvents.first?.sessionID == cloudSessID, "Emitted event belongs to discovered session")

        let storedCompleted = await sessionManager.getSession(id: cloudSessID)
        assertTest(storedCompleted?.state == .completed, "Stored session state transitioned to .completed")
        assertTest(storedCompleted?.completedAt != nil, "Completion timestamp recorded")

        // 3. Polling Deduplication: Repeated polling of already completed session must NOT emit duplicate events
        let repeatedPollEvents = await sessionManager.mergeDiscoveredSessions([discoveredCompleted])
        assertTest(repeatedPollEvents.isEmpty, "Repeated discovery poll with unchanged terminal state emits zero duplicate events")

        // 4. Stale Discovery Rejection: Stale update attempting to roll terminal state back to .running is rejected
        let staleRunning = AgentSession(
            id: cloudSessID,
            providerID: .cursorBackground,
            providerSessionID: "agent-cloud-sess-100",
            state: .running,
            workspace: "https://github.com/rapheljr/flowback",
            updatedAt: Date().addingTimeInterval(-100)
        )
        let staleEvents = await sessionManager.mergeDiscoveredSessions([staleRunning])
        assertTest(staleEvents.isEmpty, "Stale discovery update rejected without emitting events")
        let sessionAfterStale = await sessionManager.getSession(id: cloudSessID)
        assertTest(sessionAfterStale?.state == .completed, "Terminal .completed state strictly protected from regression by stale polling")

        // 5. Running -> Failed Discovery Transition
        let failSessID = AgentSessionID("agent-cloud-sess-failed")
        let failStart = AgentEvent(
            timestamp: Date(),
            providerID: .cursorBackground,
            sessionID: failSessID,
            type: .agentRunning
        )
        _ = await sessionManager.handleEvent(failStart)

        let discoveredFailed = AgentSession(
            id: failSessID,
            providerID: .cursorBackground,
            state: .failed,
            errorDescription: "Remote cloud agent container crashed"
        )
        let failEvents = await sessionManager.mergeDiscoveredSessions([discoveredFailed])
        assertTest(failEvents.first?.type == .agentFailed, "Discovered failure transitions state to .failed and emits .agentFailed")
        let storedFailed = await sessionManager.getSession(id: failSessID)
        assertTest(storedFailed?.state == .failed, "Stored session state transitioned to .failed")

        // 6. Running -> Cancelled Discovery Transition
        let cancelSessID = AgentSessionID("agent-cloud-sess-cancelled")
        let cancelStart = AgentEvent(
            timestamp: Date(),
            providerID: .cursorBackground,
            sessionID: cancelSessID,
            type: .agentRunning
        )
        _ = await sessionManager.handleEvent(cancelStart)

        let discoveredCancelled = AgentSession(
            id: cancelSessID,
            providerID: .cursorBackground,
            state: .cancelled
        )
        let cancelEvents = await sessionManager.mergeDiscoveredSessions([discoveredCancelled])
        assertTest(cancelEvents.first?.type == .agentCancelled, "Discovered cancellation transitions state to .cancelled and emits .agentCancelled")
        let storedCancelled = await sessionManager.getSession(id: cancelSessID)
        assertTest(storedCancelled?.state == .cancelled, "Stored session state transitioned to .cancelled")

        await db.close()
        try? FileManager.default.removeItem(atPath: tempDb)
        try? FileManager.default.removeItem(atPath: "\(tempDb)-wal")
        try? FileManager.default.removeItem(atPath: "\(tempDb)-shm")
    }
}
