import Foundation
import AppKit
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackTestHarness
import FlowbackNotifications
import FlowbackUI

// MARK: - Antigravity Multi-Turn Session Reactivation & Transcript Suite

func runAntigravityReactivationAndTranscriptSuites() async {
    await testGroup("Antigravity Multi-Turn Session Reactivation & Transcript Detection") {
        let tempDb = NSTemporaryDirectory() + "flowback_runner_antigravity_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let repo = SessionRepository(db: db)
        let eventBus = EventBus()
        let sessionManager = SessionManager(storageDelegate: repo, eventBus: eventBus)

        let sessionID = AgentSessionID("antigravity-multiturn-conv-1")

        // 1. First turn: agentStarted -> running
        let startEvent = AgentEvent(
            timestamp: Date(),
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentStarted,
            workspace: "/Users/abin/workspace/projects/flowback"
        )
        let s1 = await sessionManager.handleEvent(startEvent)
        assertTest(s1.state == .starting, "Turn 1: Initial event starts session in .starting state")

        let runEvent = AgentEvent(
            timestamp: Date().addingTimeInterval(1),
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentRunning,
            workspace: "/Users/abin/workspace/projects/flowback"
        )
        let s1b = await sessionManager.handleEvent(runEvent)
        assertTest(s1b.state == .running, "Turn 1: Running event transitions session to .running state")

        // 2. Turn 1 finishes: agentCompleted -> completed
        let stopEvent = AgentEvent(
            timestamp: Date().addingTimeInterval(2),
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentCompleted,
            workspace: "/Users/abin/workspace/projects/flowback"
        )
        let s2 = await sessionManager.handleEvent(stopEvent)
        assertTest(s2.state == .completed, "Turn 1: Stop event transitions session to .completed")
        assertTest(s2.completedAt != nil, "Turn 1: Completed timestamp recorded")

        // 3. User sends next prompt: multi-turn reactivation via PreInvocation (agentStarted/agentRunning)
        let nextTurnStart = AgentEvent(
            timestamp: Date().addingTimeInterval(5),
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentStarted,
            workspace: "/Users/abin/workspace/projects/flowback"
        )
        let s3 = await sessionManager.handleEvent(nextTurnStart)
        assertTest(s3.state == .starting, "Turn 2: Session successfully reactivated from .completed to .starting")
        assertTest(s3.completedAt == nil, "Turn 2: Completed timestamp cleared on reactivation")

        let nextTurnRun = AgentEvent(
            timestamp: Date().addingTimeInterval(6),
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentRunning,
            workspace: "/Users/abin/workspace/projects/flowback"
        )
        let s3b = await sessionManager.handleEvent(nextTurnRun)
        assertTest(s3b.state == .running, "Turn 2: Running event transitions reactivated session to .running")

        let storedActive = await sessionManager.getSession(id: sessionID)
        assertTest(storedActive?.state == .running, "Stored session state reflects reactivated .running state")

        // 4. Proactive Discovery Reactivation via mergeDiscoveredSessions
        // First, complete turn 2
        let stopTurn2 = AgentEvent(
            timestamp: Date().addingTimeInterval(10),
            providerID: .antigravity,
            sessionID: sessionID,
            type: .agentCompleted,
            workspace: "/Users/abin/workspace/projects/flowback"
        )
        _ = await sessionManager.handleEvent(stopTurn2)
        let s4 = await sessionManager.getSession(id: sessionID)
        assertTest(s4?.state == .completed, "Turn 2: Completed")

        // Now simulate discovery finding this session active again (e.g., Turn 3 started)
        let discoveredActive = AgentSession(
            id: sessionID,
            providerID: .antigravity,
            providerSessionID: "antigravity-multiturn-conv-1",
            state: .running,
            workspace: "/Users/abin/workspace/projects/flowback",
            updatedAt: Date().addingTimeInterval(15)
        )
        let reactivationEvents = await sessionManager.mergeDiscoveredSessions([discoveredActive])
        assertTest(reactivationEvents.count == 1, "Discovered active multi-turn session emits 1 event")
        assertTest(reactivationEvents.first?.type == .agentRunning, "Emitted event type is .agentRunning")
        let s5 = await sessionManager.getSession(id: sessionID)
        assertTest(s5?.state == .running, "mergeDiscoveredSessions successfully reactivated completed session to .running")

        await db.close()
        try? FileManager.default.removeItem(atPath: tempDb)
        try? FileManager.default.removeItem(atPath: "\(tempDb)-wal")
        try? FileManager.default.removeItem(atPath: "\(tempDb)-shm")

        // 5. AntigravityProvider Transcript System Prompt & Workspace Parsing
        let tempBrainDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("flowback-test-brain-\(UUID().uuidString)")
        let testConvDir = (tempBrainDir as NSString).appendingPathComponent("conv-test-system-prompt")
        let testLogsDir = (testConvDir as NSString).appendingPathComponent(".system_generated/logs")
        try? FileManager.default.createDirectory(atPath: testLogsDir, withIntermediateDirectories: true)

        let transcriptWithSystemPrompt = """
        {"step_index":0,"source":"SYSTEM","type":"SYSTEM_PROMPT","content":"The user has 1 active workspaces:\\n/Users/abin/workspace/projects/flowback -> rapheljr/flowback\\n"}
        {"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"Fix the bug"}
        {"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","content":"Running checks...","tool_calls":[{"name":"view_file"}]}
        """
        let transcriptPath = (testLogsDir as NSString).appendingPathComponent("transcript.jsonl")
        try? transcriptWithSystemPrompt.write(toFile: transcriptPath, atomically: true, encoding: .utf8)

        let fixtureProvider = AntigravityProvider(brainPaths: [tempBrainDir])
        let discoveredFromTranscript = await fixtureProvider.discoverActiveSessions()
        assertTest(!discoveredFromTranscript.isEmpty, "Discovered session from transcript with system prompt")
        let expectedWorkspace = "/Users/abin/workspace/projects/flowback"
        assertTest(discoveredFromTranscript.first?.workspace == expectedWorkspace,
                   "Workspace correctly extracted from inverted [URI] -> [CorpusName] format")
        assertTest(discoveredFromTranscript.first?.state == .running, "Session in progress with tool_calls is detected as .running")

        // Test completion detection when model responds DONE with no tool calls
        let transcriptDone = """
        {"step_index":0,"source":"SYSTEM","type":"SYSTEM_PROMPT","content":"/Users/abin/workspace/projects/flowback -> rapheljr/flowback"}
        {"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"Done?"}
        {"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","content":"All fixed!"}
        """
        try? transcriptDone.write(toFile: transcriptPath, atomically: true, encoding: .utf8)
        let discoveredDone = await fixtureProvider.discoverActiveSessions()
        assertTest(!discoveredDone.isEmpty, "Discovered finished session")
        assertTest(discoveredDone.first?.state == .completed, "Session with MODEL DONE and no tool calls is detected as .completed")

        try? FileManager.default.removeItem(atPath: tempBrainDir)
    }
}

// MARK: - Antigravity CLI (formerly Gemini CLI) Native Integration Verification Suite

@MainActor
func runAntigravityCLIIntegrationSuites() async {
    await testGroup("Antigravity CLI (agy) Native Hook & Lifecycle Integration") {
        let tempConfigDir = NSTemporaryDirectory() + "flowback_runner_agy_config_\(UUID().uuidString)"
        let tempCliDir = NSTemporaryDirectory() + "flowback_runner_agy_cli_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempConfigDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: tempCliDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempConfigDir)
            try? FileManager.default.removeItem(atPath: tempCliDir)
        }

        // 1. Identity & Backward Compatibility Verification
        let provider = AntigravityCLIProvider(
            globalConfigPath: tempConfigDir,
            cliDir: tempCliDir,
            binaryPaths: ["/nonexistent/bin/agy"]
        )
        assertTest(provider.providerID == .antigravityCLI, "Provider ID is .antigravityCLI")
        assertTest(provider.displayName == "Antigravity CLI", "Display name is 'Antigravity CLI'")
        assertTest(provider.supportLevel == .nativeLifecycle, "Support level is .nativeLifecycle")
        assertTest(AgentProviderID.geminiCLI == .antigravityCLI, "AgentProviderID.geminiCLI aliases to .antigravityCLI")
        assertTest(AgentProviderID("gemini-cli") == .antigravityCLI, "'gemini-cli' string maps to .antigravityCLI")
        assertTest(AgentProviderID("gemini") == .antigravityCLI, "'gemini' string maps to .antigravityCLI")
        assertTest(AgentProviderID("agy") == .antigravityCLI, "'agy' string maps to .antigravityCLI")

        // Backwards compatibility alias
        let legacyInstance = GeminiCLIProvider(
            globalConfigPath: tempConfigDir,
            cliDir: tempCliDir,
            binaryPaths: ["/nonexistent/bin/agy"]
        )
        assertTest(legacyInstance.providerID == .antigravityCLI, "GeminiCLIProvider creates AntigravityCLIProvider with .antigravityCLI")

        // 2. Health & Diagnostic Diagnostics
        let initialHealth = await provider.checkHealth()
        assertTest(initialHealth.isInstalled, "Detected as installed when cliDir exists")
        assertTest(!initialHealth.hookInstalled, "hookInstalled is false before install")
        assertTest(initialHealth.statusMessage.contains("Flowback hook not configured"), "Actionable diagnostic message before install")

        // 3. Safe Installation & Config Preservation
        let hooksPath = (tempConfigDir as NSString).appendingPathComponent("hooks.json")
        let userConfig = """
        {
            "user_custom_hook": {
                "enabled": true
            }
        }
        """
        try? userConfig.write(toFile: hooksPath, atomically: true, encoding: .utf8)

        try? await provider.installIntegration()

        let dirContents = (try? FileManager.default.contentsOfDirectory(atPath: tempConfigDir)) ?? []
        let backupExists = dirContents.contains { $0.contains("hooks.json.bak.") }
        assertTest(backupExists, "Timestamped backup created before modifying hooks.json")

        let installedHealth = await provider.checkHealth()
        assertTest(installedHealth.hookInstalled, "hookInstalled is true after install")
        assertTest(installedHealth.statusMessage.contains("active and healthy"), "Status message reflects healthy integration")

        // Verify user custom hook preserved
        let installedData = (try? Data(contentsOf: URL(fileURLWithPath: hooksPath))) ?? Data()
        let installedJson = (try? JSONSerialization.jsonObject(with: installedData)) as? [String: Any]
        assertTest(installedJson?["user_custom_hook"] != nil, "User custom hook preserved alongside Flowback hook")
        let fbHook = (installedJson?["flowback-antigravity-cli"] ?? installedJson?["flowback-agent-focus"]) as? [String: Any]
        let stopCmds = fbHook?["Stop"] as? [[String: Any]]
        let stopCmdStr = stopCmds?.first?["command"] as? String ?? ""
        assertTest(stopCmdStr.contains("flowback hook antigravity-cli"), "Stop hook command targets flowback hook antigravity-cli")

        // 4. Lifecycle Event Parsing (Native AntigravityHookPayload)
        let convID = "agy-test-conv-123"
        let prePayload1 = AntigravityHookPayload(
            hook_event_name: "PreInvocation",
            conversationId: convID,
            workspacePaths: ["/Users/abin/workspace/projects/flowback"],
            invocationNum: 1
        )
        let preData1 = (try? JSONEncoder().encode(prePayload1)) ?? Data()
        let ev1 = try? provider.parseLifecyclePayload(data: preData1)
        assertTest(ev1?.type == .agentStarted, "PreInvocation with invocationNum 1 normalizes to .agentStarted")
        assertTest(ev1?.sessionID.rawValue == convID, "Preserves conversationId as sessionID")
        assertTest(ev1?.providerID == .antigravityCLI, "Event providerID is .antigravityCLI")

        let prePayload2 = AntigravityHookPayload(
            hook_event_name: "PreInvocation",
            conversationId: convID,
            workspacePaths: ["/Users/abin/workspace/projects/flowback"],
            invocationNum: 2
        )
        let preData2 = (try? JSONEncoder().encode(prePayload2)) ?? Data()
        let ev2 = try? provider.parseLifecyclePayload(data: preData2)
        assertTest(ev2?.type == .agentRunning, "PreInvocation with invocationNum > 1 normalizes to .agentRunning")

        let postPayload = AntigravityHookPayload(
            hook_event_name: "PostInvocation",
            conversationId: convID,
            workspacePaths: ["/Users/abin/workspace/projects/flowback"],
            invocationNum: 2
        )
        let postData = (try? JSONEncoder().encode(postPayload)) ?? Data()
        let evPost = try? provider.parseLifecyclePayload(data: postData)
        assertTest(evPost?.type == .agentProgress, "PostInvocation normalizes to .agentProgress")

        let stopPayloadIdle = AntigravityHookPayload(
            hook_event_name: "Stop",
            conversationId: convID,
            workspacePaths: ["/Users/abin/workspace/projects/flowback"],
            fullyIdle: true
        )
        let stopDataIdle = (try? JSONEncoder().encode(stopPayloadIdle)) ?? Data()
        let evStop = try? provider.parseLifecyclePayload(data: stopDataIdle)
        assertTest(evStop?.type == .agentCompleted, "Stop with fullyIdle=true normalizes to .agentCompleted")

        let stopPayloadBusy = AntigravityHookPayload(
            hook_event_name: "Stop",
            conversationId: convID,
            workspacePaths: ["/Users/abin/workspace/projects/flowback"],
            fullyIdle: false
        )
        let stopDataBusy = (try? JSONEncoder().encode(stopPayloadBusy)) ?? Data()
        let evBusy = try? provider.parseLifecyclePayload(data: stopDataBusy)
        assertTest(evBusy?.type == .agentRunning, "Stop with fullyIdle=false normalizes to .agentRunning")

        let errPayload = AntigravityHookPayload(
            hook_event_name: "Stop",
            conversationId: convID,
            workspacePaths: ["/Users/abin/workspace/projects/flowback"],
            error: "Process crashed with exit 1"
        )
        let errData = (try? JSONEncoder().encode(errPayload)) ?? Data()
        let evErr = try? provider.parseLifecyclePayload(data: errData)
        assertTest(evErr?.type == .agentFailed, "Payload with error normalizes to .agentFailed")

        // 5. Generic JSON Payload Parsing Fallback
        let genericJson = """
        {
            "session_id": "legacy-session-999",
            "status": "permission_required",
            "workspace": "/Users/abin/workspace/projects/flowback"
        }
        """.data(using: .utf8) ?? Data()
        let evGen = try? provider.parseLifecyclePayload(data: genericJson)
        assertTest(evGen?.type == .agentPermissionRequired, "Generic JSON status permission_required normalizes to .agentPermissionRequired")
        assertTest(evGen?.sessionID.rawValue == "legacy-session-999", "Generic JSON preserves session_id")

        // 6. Proactive Discovery via Brain Transcripts and Presence Locks
        let testBrainDir = (tempCliDir as NSString).appendingPathComponent("brain")
        let activeConvDir = (testBrainDir as NSString).appendingPathComponent("agy-active-conv-1")
        let activeLogsDir = (activeConvDir as NSString).appendingPathComponent(".system_generated/logs")
        try? FileManager.default.createDirectory(atPath: activeLogsDir, withIntermediateDirectories: true)

        let transcriptContent = """
        {"step_index":0,"source":"SYSTEM","type":"SYSTEM_PROMPT","content":"/Users/abin/workspace/projects/flowback -> rapheljr/flowback"}
        {"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"agy test turn"}
        {"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","content":"Running checks...","tool_calls":[{"name":"view_file"}]}
        """
        let activeTranscriptPath = (activeLogsDir as NSString).appendingPathComponent("transcript.jsonl")
        try? transcriptContent.write(toFile: activeTranscriptPath, atomically: true, encoding: .utf8)

        let discoveredSessions = await provider.discoverActiveSessions()
        assertTest(!discoveredSessions.isEmpty, "Discovered active CLI session from brain transcript")
        let firstDiscovered = discoveredSessions.first { $0.id.rawValue == "agy-active-conv-1" }
        assertTest(firstDiscovered?.providerID == .antigravityCLI, "Discovered session providerID is .antigravityCLI")
        assertTest(firstDiscovered?.workspace == "/Users/abin/workspace/projects/flowback", "Workspace path extracted accurately")
        assertTest(firstDiscovered?.state == .running, "In-progress turn detected as .running")

        // 7. Clean Uninstall
        try? await provider.uninstallIntegration()
        let uninstalledHealth = await provider.checkHealth()
        assertTest(!uninstalledHealth.hookInstalled, "hookInstalled is false after uninstall")

        let remainingData = (try? Data(contentsOf: URL(fileURLWithPath: hooksPath))) ?? Data()
        let remainingJson = (try? JSONSerialization.jsonObject(with: remainingData)) as? [String: Any]
        assertTest(remainingJson?["user_custom_hook"] != nil, "User custom hook preserved after Flowback uninstall")
        assertTest(remainingJson?["flowback-antigravity-cli"] == nil && remainingJson?["flowback-agent-focus"] == nil, "Flowback hook cleanly removed on uninstall")
    }
}
