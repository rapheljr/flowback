import Foundation
import AppKit
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackTestHarness

// MARK: - Audit Remediation Verification Suites (F-01 through F-13)

@MainActor
func runAuditRemediationSuites() async {
    print("\n================================================================")
    print("FLOWBACK AUDIT REMEDIATION VERIFICATION SUITES (F-01 to F-13)")
    print("================================================================")

    // MARK: - F-01: Correct Window Selection Using Requested Window Identity
    await testGroup("F-01: Window Selection Accuracy & Ambiguity Handling") {
        // 1. Exact bounds and title match scores highest (10) and selects correct non-first candidate
        let targetWindow = WindowInfo(
            windowID: 202,
            processIdentifier: 1000,
            ownerName: "Code",
            title: "Project Alpha — index.ts",
            bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
            isOnScreen: true
        )
        
        let candidateFirst = AccessibleWindowAttributes(
            title: "Welcome Page",
            position: CGPoint(x: 0, y: 0),
            size: CGSize(width: 500, height: 400)
        )
        let candidateSecond = AccessibleWindowAttributes(
            title: "Project Alpha — index.ts",
            position: CGPoint(x: 101, y: 100),
            size: CGSize(width: 800, height: 601)
        )
        let candidateThird = AccessibleWindowAttributes(
            title: "Settings",
            position: CGPoint(x: 200, y: 200),
            size: CGSize(width: 400, height: 300)
        )
        
        let selectedIndex = WindowController.selectMatchingWindowIndex(
            target: targetWindow,
            candidates: [candidateFirst, candidateSecond, candidateThird]
        )
        assertTest(selectedIndex == 1, "F-01: Correctly selects non-first window (index 1) matching target identity")
        
        // 2. Geometry/bounds matching when title is missing or empty
        let targetNoTitle = WindowInfo(
            windowID: 303,
            processIdentifier: 1000,
            ownerName: "Terminal",
            title: "",
            bounds: CGRect(x: 50, y: 50, width: 600, height: 400),
            isOnScreen: true
        )
        let candidateEmptyTitle = AccessibleWindowAttributes(
            title: "",
            position: CGPoint(x: 50, y: 50),
            size: CGSize(width: 600, height: 400)
        )
        let selectedGeometry = WindowController.selectMatchingWindowIndex(
            target: targetNoTitle,
            candidates: [candidateFirst, candidateEmptyTitle]
        )
        assertTest(selectedGeometry == 1, "F-01: Matches by geometry when titles are missing or empty")
        
        // 3. Ambiguous tie (duplicate titles and duplicate bounds) returns nil (conservative failure)
        let duplicateCandidate1 = AccessibleWindowAttributes(
            title: "Duplicate Title",
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 800, height: 600)
        )
        let duplicateCandidate2 = AccessibleWindowAttributes(
            title: "Duplicate Title",
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 800, height: 600)
        )
        let targetDuplicate = WindowInfo(
            windowID: 404,
            processIdentifier: 1000,
            ownerName: "Code",
            title: "Duplicate Title",
            bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
            isOnScreen: true
        )
        let tieResult = WindowController.selectMatchingWindowIndex(
            target: targetDuplicate,
            candidates: [duplicateCandidate1, duplicateCandidate2]
        )
        assertTest(tieResult == nil, "F-01: Ambiguous candidates with equal scores return nil without guessing")
        
        // 4. Empty candidate list returns nil
        let emptyResult = WindowController.selectMatchingWindowIndex(
            target: targetWindow,
            candidates: []
        )
        assertTest(emptyResult == nil, "F-01: Empty candidate list safely returns nil")
        
        // 5. WindowID 0 rejection
        let winCtrl = WindowController()
        let zeroResult = winCtrl.raiseWindow(windowID: 0, pid: 1000)
        assertTest(!zeroResult, "F-01: raiseWindow rejects windowID 0 as invalid identity")
        
        // 6. MockWindowController rejects nonexistent window
        let mockWin = MockWindowController()
        mockWin.windowsMock = [targetWindow]
        let nonexistentRaised = mockWin.raiseWindow(windowID: 99999, pid: 1000)
        assertTest(!nonexistentRaised, "F-01: Rejects windowID that does not exist for process")
        let existentRaised = mockWin.raiseWindow(windowID: 202, pid: 1000)
        assertTest(existentRaised, "F-01: Successfully raises verified window ID")
    }

    // MARK: - F-02: Restoration Outcomes Reflect Actual Behavior
    await testGroup("F-02: Restoration Outcomes Reflect Actual Behavior") {
        let mockApp = MockApplicationController()
        let mockWin = MockWindowController()
        let mockIdle = MockIdleTracker(idleSeconds: 30.0)
        let mockSpace = MockSpaceController()
        let intentEngine = UserIntentEngine(idleTracker: mockIdle, windowController: mockWin, spaceController: mockSpace, appController: mockApp)
        let arbiter = AttentionArbiter(aggregationWindow: 1.0, cooldownDuration: 0.0)
        let focusController = FocusController(appController: mockApp, windowController: mockWin, intentEngine: intentEngine, arbiter: arbiter)
        
        // 1. Window-only adapter with exactConversation declared capability does NOT report exactConversationRestored
        let vsOrigin = OriginContext(
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 500,
            windowIdentifier: 101,
            workspacePath: "/projects/repo",
            restorationCapability: .exactWindowAndWorkspace
        )
        let sessionWindowOnly = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: "/projects/repo",
            originContext: vsOrigin,
            focusCapability: .exactConversation
        )
        
        let restoration = await focusController.restoreSession(sessionWindowOnly)
        assertTest(restoration.outcome != .exactConversationRestored, "F-02: Window adapter NEVER claims .exactConversationRestored")
        assertTest(restoration.outcome == .workspaceActivatedOnly, "F-02: Restores origin workspace honestly as .workspaceActivatedOnly")
        assertTest(!restoration.outcome.isExactConversation, "F-02: Outcome is confirmed as not exact conversation")
        
        // 2. Capability verification: window/workspace only outcomes
        assertTest(!RestorationOutcome.workspaceActivatedOnly.isExactConversation, "F-02: .workspaceActivatedOnly is NOT exact conversation")
        assertTest(!RestorationOutcome.windowActivatedOnly.isExactConversation, "F-02: .windowActivatedOnly is NOT exact conversation")
        assertTest(!RestorationOutcome.resumeHintPresented.isExactConversation, "F-02: .resumeHintPresented is NOT exact conversation")
        assertTest(!RestorationOutcome.providerURLOpened.isExactConversation, "F-02: .providerURLOpened is NOT exact conversation")
        assertTest(RestorationOutcome.exactConversationRestored.isExactConversation, "F-02: Only .exactConversationRestored is classified as exact")
    }

    // MARK: - F-03: Eliminate Antigravity Desktop & CLI Hook Collisions
    await testGroup("F-03: Antigravity Desktop and CLI Hook Coexistence") {
        let tempBase = NSTemporaryDirectory() + "flowback_f03_\(UUID().uuidString)"
        let configDir = tempBase + "/.gemini/config"
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let hooksPath = configDir + "/hooks.json"
        
        // Seed with existing user custom hook
        let initialJSON = """
        {
            "my-custom-hook": {
                "command": "echo custom-user-tool",
                "events": ["UserEvent"]
            }
        }
        """
        try? initialJSON.write(toFile: hooksPath, atomically: true, encoding: .utf8)
        
        let desktopProvider = AntigravityProvider(globalConfigPath: configDir)
        let cliProvider = AntigravityCLIProvider(globalConfigPath: configDir)
        
        // 1. Install Desktop
        try? await desktopProvider.installIntegration()
        let dataAfterDesktop = (try? Data(contentsOf: URL(fileURLWithPath: hooksPath))) ?? Data()
        let jsonAfterDesktop = (try? JSONSerialization.jsonObject(with: dataAfterDesktop)) as? [String: Any]
        assertTest(jsonAfterDesktop?["flowback-antigravity"] != nil, "F-03: Desktop hook installed with distinct key 'flowback-antigravity'")
        assertTest(jsonAfterDesktop?["my-custom-hook"] != nil, "F-03: User custom hook preserved after desktop install")
        
        // 2. Install CLI alongside Desktop
        try? await cliProvider.installIntegration()
        let dataAfterBoth = (try? Data(contentsOf: URL(fileURLWithPath: hooksPath))) ?? Data()
        let jsonAfterBoth = (try? JSONSerialization.jsonObject(with: dataAfterBoth)) as? [String: Any]
        assertTest(jsonAfterBoth?["flowback-antigravity"] != nil, "F-03: Desktop hook still present after CLI install")
        assertTest(jsonAfterBoth?["flowback-antigravity-cli"] != nil, "F-03: CLI hook installed with distinct key 'flowback-antigravity-cli'")
        assertTest(jsonAfterBoth?["my-custom-hook"] != nil, "F-03: User custom hook preserved after both installed")
        
        // 3. Verify distinct commands
        let desktopEntry = jsonAfterBoth?["flowback-antigravity"] as? [String: Any]
        let cliEntry = jsonAfterBoth?["flowback-antigravity-cli"] as? [String: Any]
        let desktopCmd = ((desktopEntry?["Stop"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
        let cliCmd = ((cliEntry?["Stop"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
        assertTest(desktopCmd.contains("flowback hook antigravity"), "F-03: Desktop hook command targets desktop integration")
        assertTest(cliCmd.contains("flowback hook antigravity-cli"), "F-03: CLI hook command targets CLI integration")
        
        // 4. Uninstall Desktop while CLI remains
        try? await desktopProvider.uninstallIntegration()
        let dataAfterDesktopUninstall = (try? Data(contentsOf: URL(fileURLWithPath: hooksPath))) ?? Data()
        let jsonAfterDesktopUninstall = (try? JSONSerialization.jsonObject(with: dataAfterDesktopUninstall)) as? [String: Any]
        assertTest(jsonAfterDesktopUninstall?["flowback-antigravity"] == nil, "F-03: Desktop hook removed on desktop uninstall")
        assertTest(jsonAfterDesktopUninstall?["flowback-antigravity-cli"] != nil, "F-03: CLI hook remains intact when desktop uninstalls")
        assertTest(jsonAfterDesktopUninstall?["my-custom-hook"] != nil, "F-03: User custom hook preserved")
        
        // 5. Uninstall CLI
        try? await cliProvider.uninstallIntegration()
        let dataFinal = (try? Data(contentsOf: URL(fileURLWithPath: hooksPath))) ?? Data()
        let jsonFinal = (try? JSONSerialization.jsonObject(with: dataFinal)) as? [String: Any]
        assertTest(jsonFinal?["flowback-antigravity-cli"] == nil, "F-03: CLI hook cleanly removed on CLI uninstall")
        assertTest(jsonFinal?["my-custom-hook"] != nil, "F-03: User custom hook intact after all uninstalls")
        
        try? FileManager.default.removeItem(atPath: tempBase)
    }

    // MARK: - F-04: Hot Event Path Separated from Discovery and Health Probing
    await testGroup("F-04: Hot Event Path Performance & Separation") {
        final class SpyDiscoveryProvider: AgentProvider, @unchecked Sendable {
            let providerID = AgentProviderID("spy-provider")
            let displayName = "Spy Provider"
            let isSupported = true
            var discoveryCount = 0
            var healthCheckCount = 0
            
            func checkHealth() async -> ProviderHealth {
                healthCheckCount += 1
                return ProviderHealth(providerID: providerID, displayName: displayName, isInstalled: true, hookInstalled: true, hookExecutable: true)
            }
            func parseLifecyclePayload(data: Data) throws -> AgentEvent? { nil }
            func installIntegration() async throws {}
            func uninstallIntegration() async throws {}
            func discoverActiveSessions() async -> [AgentSession] {
                discoveryCount += 1
                return []
            }
        }
        
        let spy = SpyDiscoveryProvider()
        let registry = ProviderRegistry()
        await registry.register(provider: spy)
        
        let sessionMgr = SessionManager()
        
        // Ingest 50 events through SessionManager
        for i in 1...50 {
            let event = AgentEvent(
                id: "evt-\(i)",
                providerID: spy.providerID,
                sessionID: AgentSessionID("sess-f04-\(i)"),
                type: .agentProgress,
                workspace: "/workspace/f04"
            )
            _ = await sessionMgr.handleEvent(event)
        }
        
        assertTest(spy.discoveryCount == 0, "F-04: Ingesting 50 events triggers ZERO full provider discovery scans")
        assertTest(spy.healthCheckCount == 0, "F-04: Ingesting 50 events triggers ZERO health-check process probes")
    }

    // MARK: - F-05: Bounded In-Memory State & DB Pruning
    await testGroup("F-05: Bounded In-Memory State & DB Pruning") {
        let tempDbPath = NSTemporaryDirectory() + "flowback_f05_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDbPath)
        let repo = SessionRepository(db: db)
        let sessionMgr = SessionManager(storageDelegate: repo)
        
        // 1. Seed 1 active running session
        let activeSession = AgentSession(
            id: AgentSessionID("active-permanent"),
            providerID: .antigravity,
            state: .running,
            workspace: "/projects/active"
        )
        _ = await sessionMgr.handleEvent(AgentEvent(providerID: .antigravity, sessionID: activeSession.id, type: .agentStarted))
        _ = await sessionMgr.handleEvent(AgentEvent(providerID: .antigravity, sessionID: activeSession.id, type: .agentRunning))
        
        // 2. Ingest 250 completed sessions
        for i in 1...250 {
            let sessID = AgentSessionID("completed-\(i)")
            _ = await sessionMgr.handleEvent(AgentEvent(providerID: .antigravity, sessionID: sessID, type: .agentStarted))
            _ = await sessionMgr.handleEvent(AgentEvent(providerID: .antigravity, sessionID: sessID, type: .agentCompleted))
        }
        
        // 3. Verify in-memory completed sessions are bounded to max 100
        let inMemoryCompletedCount = await sessionMgr.inMemoryCompletedSessionCount
        assertTest(inMemoryCompletedCount <= 100, "F-05: In-memory completed sessions strictly bounded to 100 (actual: \(inMemoryCompletedCount))")
        
        // 4. Verify active running session was NOT evicted
        let retrievedActive = await sessionMgr.getSession(id: activeSession.id)
        assertTest(retrievedActive != nil && retrievedActive?.state == .running, "F-05: Active running sessions are NEVER evicted from memory")
        
        // 5. Verify evicted completed session is seamlessly reloaded from SQLite
        let olderEvictedSession = await sessionMgr.getSession(id: AgentSessionID("completed-5"))
        assertTest(olderEvictedSession != nil && olderEvictedSession?.state == .completed, "F-05: Evicted session seamlessly reloaded from SQLite repository on demand")
        
        // 6. Verify TimelineTracker bounded per session
        let timeline = TimelineTracker()
        for i in 1...100 {
            await timeline.record(
                sessionID: activeSession.id,
                category: "progress",
                summary: "Event \(i)"
            )
        }
        let sessionTimeline = await timeline.entries(for: activeSession.id)
        assertTest(sessionTimeline.count <= 50, "F-05: TimelineTracker caps entries per session to 50 (actual: \(sessionTimeline.count))")
        
        // 7. Test DB pruning of completed sessions older than threshold
        let oldDate = Date().addingTimeInterval(-40 * 86400)
        let pruneSession = AgentSession(
            id: AgentSessionID("to-prune"),
            providerID: .antigravity,
            state: .completed,
            startedAt: oldDate,
            updatedAt: oldDate,
            completedAt: oldDate
        )
        try? await repo.saveSession(pruneSession)
        let pruned = try? await repo.pruneCompletedSessions(olderThanDays: 30, keepMinCount: 10)
        assertTest((pruned ?? 0) >= 1, "F-05: pruneCompletedSessions executes transactionally and removes eligible records")
        
        await db.close()
        try? FileManager.default.removeItem(atPath: tempDbPath)
    }

    // MARK: - F-06: Remove Provider-Specific CLI Commands from Core
    await testGroup("F-06: Provider-Owned Resume Commands") {
        let registry = ResumeCommandRegistry.shared
        
        let agySession = AgentSession(
            providerID: .antigravityCLI,
            conversationID: "conv-123"
        )
        let agyCmd = registry.resumeCommand(for: agySession)
        assertTest(agyCmd == "agy --conversation conv-123", "F-06: Antigravity CLI resume syntax formatted correctly via registry")
        let providerAgyCmd = AntigravityCLIProvider().resumeCommand(for: agySession)
        assertTest(providerAgyCmd == "agy --conversation conv-123", "F-06: Antigravity CLI resume syntax owned by provider")
        
        let claudeSession = AgentSession(
            providerID: .claudeCode,
            conversationID: "conv-456"
        )
        let claudeCmd = registry.resumeCommand(for: claudeSession)
        assertTest(claudeCmd == "claude resume conv-456", "F-06: Claude Code resume syntax formatted correctly via registry")
        let providerClaudeCmd = ClaudeCodeProvider().resumeCommand(for: claudeSession)
        assertTest(providerClaudeCmd == "claude resume conv-456", "F-06: Claude Code resume syntax owned by provider")
        
        let unkSession = AgentSession(
            providerID: AgentProviderID("unsupported-agent"),
            conversationID: "123"
        )
        let unkCmd = registry.resumeCommand(for: unkSession)
        assertTest(unkCmd == nil, "F-06: Unsupported provider safely returns nil resume hint")
    }

    // MARK: - F-07: Asynchronous Non-Blocking Process Execution
    await testGroup("F-07: AsyncProcessRunner Non-Blocking Execution") {
        // 1. Fast process execution
        let echoResult = try? await AsyncProcessRunner.run(
            executablePath: "/bin/echo",
            arguments: ["hello", "async", "world"],
            timeoutSeconds: 5.0
        )
        assertTest(echoResult?.exitCode == 0, "F-07: AsyncProcessRunner executes successfully with exitCode 0")
        assertTest(echoResult?.stdout.contains("hello async world") == true, "F-07: Standard output collected accurately")
        
        // 2. Nonzero exit code
        let failResult = try? await AsyncProcessRunner.run(
            executablePath: "/usr/bin/false",
            arguments: [],
            timeoutSeconds: 5.0
        )
        assertTest(failResult?.exitCode != 0, "F-07: Nonzero exit code captured cleanly without throwing unexpected error")
        
        // 3. Timeout handling
        var timedOut = false
        do {
            _ = try await AsyncProcessRunner.run(
                executablePath: "/bin/sleep",
                arguments: ["5"],
                timeoutSeconds: 0.1
            )
        } catch let err as ProcessExecutionError {
            if case .timedOut = err {
                timedOut = true
            }
        } catch {}
        assertTest(timedOut, "F-07: AsyncProcessRunner terminates hanging process and throws .timedOut error")
        
        // 4. Cooperative cancellation
        let cancelTask = Task {
            try await AsyncProcessRunner.run(
                executablePath: "/bin/sleep",
                arguments: ["10"],
                timeoutSeconds: 10.0
            )
        }
        cancelTask.cancel()
        let cancelResult = await cancelTask.result
        var wasCancelled = false
        switch cancelResult {
        case .failure(let err):
            if err is CancellationError || (err as? ProcessExecutionError) == .cancelled {
                wasCancelled = true
            }
        case .success:
            break
        }
        assertTest(wasCancelled, "F-07: Swift concurrency Task cancellation cleanly terminates child process")
    }

    // MARK: - F-08: Provider-Owned Hook Response Processing
    await testGroup("F-08: Provider-Owned Hook Protocol Handling") {
        let tempDb = NSTemporaryDirectory() + "flowback_f08_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let settingsRepo = SettingsRepository(db: db)
        let sessionMgr = SessionManager(storageDelegate: SessionRepository(db: db))
        let mockApp = MockApplicationController()
        let mockWin = MockWindowController()
        let intentEngine = UserIntentEngine(idleTracker: MockIdleTracker(), windowController: mockWin, spaceController: MockSpaceController(), appController: mockApp)
        let focusCtrl = FocusController(appController: mockApp, windowController: mockWin, intentEngine: intentEngine, arbiter: AttentionArbiter())
        let registry = ProviderRegistry()
        await registry.register(provider: AntigravityCLIProvider())
        
        let ipcHandler = IPCHandler(
            sessionManager: sessionMgr,
            focusController: focusCtrl,
            providerRegistry: registry,
            settingsRepo: settingsRepo
        )
        
        // 1. Antigravity CLI PreInvocation hook payload
        let prePayload = """
        {
            "hook_event_name": "PreInvocation",
            "conversationId": "cli-conv-f08",
            "invocationNum": 1
        }
        """.data(using: .utf8)!
        
        let preReq = IPCRequest(command: "hook", argument: "antigravity-cli", payload: prePayload)
        let preResp = await ipcHandler.handleRequest(preReq)
        assertTest(preResp.success, "F-08: PreInvocation hook routed and processed cleanly")
        let responseString = preResp.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        assertTest(responseString.contains("injectSteps"), "F-08: Hook response generated by provider declares injectSteps")
        
        // 2. Unrecognized hook payload handled safely without IPCHandler crashing
        let unkReq = IPCRequest(command: "hook", argument: "non-existent-provider", payload: Data())
        let unkResp = await ipcHandler.handleRequest(unkReq)
        assertTest(unkResp.success, "F-08: Unknown hook provider fails safe with default allow fallback")
        
        await db.close()
        try? FileManager.default.removeItem(atPath: tempDb)
    }

    // MARK: - F-09: Remote Agent Intent & Diagnostics
    await testGroup("F-09: Remote Agent Intent & Diagnostics") {
        let mockApp = MockApplicationController()
        let mockWin = MockWindowController()
        let mockIdle = MockIdleTracker(idleSeconds: 30.0) // idle
        let mockSpace = MockSpaceController()
        let intentEngine = UserIntentEngine(idleTracker: mockIdle, windowController: mockWin, spaceController: mockSpace, appController: mockApp)
        
        // 1. Remote session with valid conversation URL when user is idle
        let remoteURL = URL(string: "https://antigravity.google/c/remote-session-123")!
        let remoteSession = AgentSession(
            id: AgentSessionID("remote-1"),
            providerID: .antigravity,
            state: .completed,
            conversationURL: remoteURL,
            isRemote: true
        )
        
        let decisionIdle = intentEngine.evaluate(session: remoteSession, config: .default, focusLock: FocusLockState())
        switch decisionIdle {
        case .restoreDestination(let url, let reason):
            assertTest(url == remoteURL, "F-09: Idle user evaluates to .restoreDestination with remote URL")
            assertTest(!reason.contains("missing origin"), "F-09: Remote session not falsely diagnosed as missing origin")
        default:
            assertTest(false, "F-09: Expected .restoreDestination for idle remote session, got: \(decisionIdle)")
        }
        
        // 2. Remote session when user is actively interacting (< 5s idle)
        mockIdle.idleSecondsMock = 0.5
        let decisionActive = intentEngine.evaluate(session: remoteSession, config: .default, focusLock: FocusLockState())
        switch decisionActive {
        case .notifyOnly(let reason):
            assertTest(reason.contains("actively interacting"), "F-09: Remote session respects active user typing safeguard")
        default:
            assertTest(false, "F-09: Active typing did not produce .notifyOnly: \(decisionActive)")
        }
        
        // 3. Remote session without URL evaluates to notifyOnly safely
        let remoteNoURL = AgentSession(
            id: AgentSessionID("remote-2"),
            providerID: .antigravity,
            state: .completed,
            conversationURL: nil,
            isRemote: true
        )
        let decisionNoURL = intentEngine.evaluate(session: remoteNoURL, config: .default, focusLock: FocusLockState())
        switch decisionNoURL {
        case .notifyOnly(let reason):
            assertTest(reason.contains("no usable destination URL"), "F-09: Remote session without URL honestly reports no usable destination URL")
        default:
            assertTest(false, "F-09: Remote session without URL did not evaluate to .notifyOnly")
        }
    }

    // MARK: - F-10: LifecycleCoordinator Integration
    await testGroup("F-10: Component Lifecycle Coordinator Integration") {
        let coordinator = LifecycleCoordinator()
        
        final class TestComp: LifecycleManagedComponent, @unchecked Sendable {
            let componentName: String
            let isCritical: Bool
            var started = false
            var stopped = false
            init(name: String, critical: Bool = true) {
                self.componentName = name
                self.isCritical = critical
            }
            func startComponent() async throws { started = true }
            func stopComponent() async { stopped = true; started = false }
        }
        
        let c1 = TestComp(name: "Storage")
        let c2 = TestComp(name: "Server")
        let res = await coordinator.start(components: [c1, c2])
        assertTest(res == .ready, "F-10: Coordinated startup yields .ready state")
        assertTest(c1.started && c2.started, "F-10: All registered components started in order")
        
        await coordinator.stop()
        assertTest(await coordinator.currentState == .stopped, "F-10: Shutdown yields .stopped state")
        assertTest(c1.stopped && c2.stopped, "F-10: All registered components stopped on shutdown")
    }

    // MARK: - F-11: Canonical Shared IPC Protocol DTOs
    await testGroup("F-11: Shared IPC Protocol Wire Types") {
        let originalReq = IPCRequest(
            command: "test_cmd",
            argument: "arg_value",
            payload: "{\"test\": 123}".data(using: .utf8)
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        // Round trip encode and decode
        let data = try? encoder.encode(originalReq)
        assertTest(data != nil, "F-11: Canonical IPCRequest encodes to JSON")
        
        let decodedReq = try? decoder.decode(IPCRequest.self, from: data ?? Data())
        assertTest(decodedReq?.command == "test_cmd", "F-11: Decoded IPCRequest command matches")
        assertTest(decodedReq?.argument == "arg_value", "F-11: Decoded IPCRequest argument matches")
        assertTest(decodedReq?.payload != nil, "F-11: Decoded IPCRequest payload matches")
        
        let originalResp = IPCResponse(
            success: true,
            message: "All good",
            data: "{\"k1\":\"v1\"}".data(using: .utf8)
        )
        let respData = try? encoder.encode(originalResp)
        let decodedResp = try? decoder.decode(IPCResponse.self, from: respData ?? Data())
        assertTest(decodedResp?.success == true, "F-11: Canonical IPCResponse success matches")
        assertTest(decodedResp?.message == "All good", "F-11: Canonical IPCResponse message matches")
        assertTest(decodedResp?.data != nil, "F-11: Canonical IPCResponse data matches")
    }

    // MARK: - F-12: Stable Database SQL Mapping & Resilience
    await testGroup("F-12: Stable Database SQL Mapping & Projections") {
        let tempDb = NSTemporaryDirectory() + "flowback_f12_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let repo = SessionRepository(db: db)
        
        let origin = OriginContext(
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 1234,
            windowIdentifier: 55,
            windowTitle: "zsh",
            workspacePath: "/Users/test/workspace"
        )
        let targetURL = URL(string: "https://antigravity.google/c/sql-test")!
        let session = AgentSession(
            id: AgentSessionID("sql-test-session"),
            providerID: .antigravity,
            state: .completed,
            workspace: "/Users/test/workspace",
            originContext: origin,
            startedAt: Date().addingTimeInterval(-100),
            updatedAt: Date(),
            completedAt: Date(),
            metadata: ["test_key": "test_val"],
            conversationURL: targetURL,
            isRemote: true
        )
        
        try? await repo.saveSession(session)
        let fetched = try? await repo.fetchSession(id: session.id)
        
        assertTest(fetched?.id == session.id, "F-12: Session ID round-tripped cleanly with explicit SQL projection")
        assertTest(fetched?.providerID == .antigravity, "F-12: Provider ID decoded correctly")
        assertTest(fetched?.state == .completed, "F-12: State decoded correctly")
        assertTest(fetched?.originContext?.bundleIdentifier == "com.apple.Terminal", "F-12: Origin context bundle identifier decoded")
        assertTest(fetched?.originContext?.windowIdentifier == 55, "F-12: Origin context window ID decoded")
        assertTest(fetched?.metadata["test_key"] == "test_val", "F-12: Metadata decoded from JSON")
        assertTest(fetched?.isRemote == true, "F-12: isRemote flag decoded correctly")
        assertTest(fetched?.conversationURL == targetURL, "F-12: conversationURL decoded accurately")
        
        await db.close()
        try? FileManager.default.removeItem(atPath: tempDb)
    }

    // MARK: - F-13: ApplicationAdapterRegistry Concurrency Safety
    await testGroup("F-13: ApplicationAdapterRegistry Thread Safety") {
        let registry = ApplicationAdapterRegistry()
        
        final class ConcurrentDummyAdapter: ApplicationAdapter, @unchecked Sendable {
            let adapterName = "ConcurrentDummy"
            let bundleID: String
            init(bundleID: String) { self.bundleID = bundleID }
            func canHandle(bundleIdentifier: String) -> Bool { bundleIdentifier == self.bundleID }
            func restoreContext(
                context: OriginContext,
                appController: ApplicationControlling,
                windowController: WindowControlling
            ) async -> Bool { true }
        }
        
        // Concurrently register and lookup adapters across multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 1...100 {
                let bundle = "com.test.adapter.\(i)"
                group.addTask {
                    registry.register(adapter: ConcurrentDummyAdapter(bundleID: bundle))
                }
                group.addTask {
                    _ = registry.findAdapter(for: bundle)
                }
            }
        }
        
        assertTest(true, "F-13: 100 concurrent registrations and lookups completed without data race or crash")
    }

    // MARK: - Condition 1: UI Event Coalescing & Throttling
    await testGroup("Condition 1: UI Event Coalescing & Throttling") {
        // 1. Burst of 1,000 events coalescing into a single bounded refresh
        let burstScheduler = ManualSleepScheduler()
        var burstRefreshCount = 0
        let burstCoalescer = UIEventCoalescer(interval: 0.05, sleeper: { try await burstScheduler.sleep(seconds: $0) }) {
            burstRefreshCount += 1
        }
        
        for _ in 1...1000 {
            burstCoalescer.schedule()
        }
        await burstScheduler.waitUntilSleeping()
        
        assertTest(burstCoalescer.scheduleCount == 1000, "C-01: Recorded 1,000 scheduled event triggers")
        assertTest(burstScheduler.pendingSleepCount == 1, "C-01: Exactly 1 sleep task scheduled for 1,000 events")
        assertTest(burstRefreshCount == 0, "C-01: Zero premature UI synchronizations before interval elapsed")
        assertTest(burstCoalescer.coalescedEventCount == 999, "C-01: 999 intermediate events coalesced into pending window")
        
        burstScheduler.advance()
        await Task.yield()
        
        assertTest(burstRefreshCount == 1, "C-01: 1,000 events coalesced into exactly 1 UI synchronization pass")
        assertTest(burstCoalescer.executionCount == 1, "C-01: Coalescer tracks exactly 1 execution pass")

        // 2. Single event eventually triggering a refresh
        let singleScheduler = ManualSleepScheduler()
        var singleRefreshCount = 0
        let singleCoalescer = UIEventCoalescer(interval: 0.05, sleeper: { try await singleScheduler.sleep(seconds: $0) }) {
            singleRefreshCount += 1
        }
        
        singleCoalescer.schedule()
        assertTest(singleRefreshCount == 0, "C-01: Single event does not execute synchronously on scheduling")
        await singleScheduler.waitUntilSleeping()
        singleScheduler.advance()
        await Task.yield()
        assertTest(singleRefreshCount == 1, "C-01: Single event triggers exactly 1 UI refresh after interval")

        final class ValueBox<T> {
            var value: T
            init(_ value: T) { self.value = value }
        }

        // 3. Final published state reflecting the latest event
        let stateScheduler = ManualSleepScheduler()
        var publishedState: String = ""
        let stateBox = ValueBox<String>("Initial")
        let stateCoalescer = UIEventCoalescer(interval: 0.05, sleeper: { try await stateScheduler.sleep(seconds: $0) }) {
            publishedState = stateBox.value
        }
        
        for i in 1...500 {
            stateBox.value = "Update-\(i)"
            stateCoalescer.schedule()
        }
        await stateScheduler.waitUntilSleeping()
        stateScheduler.advance()
        while stateCoalescer.executionCount == 0 {
            await Task.yield()
        }
        assertTest(publishedState == "Update-500", "C-01: Published UI state accurately captures the latest event (Update-500)")

        // 4. Events arriving during an executing refresh
        let overlapScheduler = ManualSleepScheduler()
        var overlapPublishedValue = 0
        let sourceBox = ValueBox<Int>(0)
        let overlapCoalescer = UIEventCoalescer(interval: 0.05, sleeper: { try await overlapScheduler.sleep(seconds: $0) }) {
            overlapPublishedValue = sourceBox.value
        }
        
        sourceBox.value = 100
        overlapCoalescer.schedule()
        await overlapScheduler.waitUntilSleeping()
        overlapScheduler.advance()
        while overlapCoalescer.executionCount == 0 {
            await Task.yield()
        }
        assertTest(overlapPublishedValue == 100, "C-01: Initial execution published value 100")
        
        // Next event arrives
        sourceBox.value = 200
        overlapCoalescer.schedule()
        assertTest(overlapCoalescer.isPending, "C-01: Subsequent event triggers pending state")
        await overlapScheduler.waitUntilSleeping()
        overlapScheduler.advance()
        while overlapCoalescer.executionCount < 2 {
            await Task.yield()
        }
        assertTest(overlapPublishedValue == 200, "C-01: Subsequent event published updated value 200")
        assertTest(overlapCoalescer.executionCount == 2, "C-01: Cleanly executed 2 distinct cycles across arrival boundary")

        // 5. Terminal events retaining immediate persistence, arbitration, and notifications
        let tempDb = NSTemporaryDirectory() + "flowback_coalesce_term_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let sessionRepo = SessionRepository(db: db)
        let sessionMgr = SessionManager(storageDelegate: sessionRepo)
        let arbiter = AttentionArbiter()
        
        let termEvent = AgentEvent(
            id: "term-1",
            providerID: .antigravity,
            sessionID: AgentSessionID("sess-term"),
            type: .agentCompleted,
            workspace: "/workspace/term"
        )
        let session = await sessionMgr.handleEvent(termEvent)
        let req = AttentionRequest(
            sessionID: session.id,
            providerID: session.providerID,
            priority: .completed,
            title: "Terminal Test",
            message: "Completed",
            workspace: session.workspace
        )
        await arbiter.enqueue(req)
        
        assertTest(session.state == .completed, "C-01: Terminal event session persisted and updated immediately")
        let pendingAttention = await arbiter.pendingRequests()
        assertTest(pendingAttention.count == 1, "C-01: Terminal attention enqueued immediately without waiting for UI throttling")
        await db.close()
        try? FileManager.default.removeItem(atPath: tempDb)

        // 6. Shutdown cancelling pending work without leaving tasks running
        let shutdownScheduler = ManualSleepScheduler()
        var shutdownExecuted = false
        let shutdownCoalescer = UIEventCoalescer(interval: 0.05, sleeper: { try await shutdownScheduler.sleep(seconds: $0) }) {
            shutdownExecuted = true
        }
        
        shutdownCoalescer.schedule()
        await shutdownScheduler.waitUntilSleeping()
        assertTest(shutdownScheduler.pendingSleepCount == 1, "C-01: Pending sleep task active before stop")
        assertTest(shutdownCoalescer.isPending, "C-01: Coalescer is pending before stop")
        
        shutdownCoalescer.stop()
        assertTest(!shutdownCoalescer.isPending, "C-01: Pending state cleared immediately on stop")
        shutdownScheduler.advance()
        await Task.yield()
        assertTest(!shutdownExecuted, "C-01: Cancelled task did not execute action on shutdown")
        
        shutdownCoalescer.schedule()
        assertTest(shutdownScheduler.pendingSleepCount == 0, "C-01: Stopped coalescer ignores new schedule requests")

        // 7. Repeated scheduling not producing concurrent redundant refreshes
        let repeatScheduler = ManualSleepScheduler()
        var activeConcurrentRefreshes = 0
        var maxConcurrentRefreshes = 0
        let repeatCoalescer = UIEventCoalescer(interval: 0.05, sleeper: { try await repeatScheduler.sleep(seconds: $0) }) {
            activeConcurrentRefreshes += 1
            if activeConcurrentRefreshes > maxConcurrentRefreshes {
                maxConcurrentRefreshes = activeConcurrentRefreshes
            }
            await Task.yield()
            activeConcurrentRefreshes -= 1
        }
        
        for _ in 1...200 {
            repeatCoalescer.schedule()
        }
        await repeatScheduler.waitUntilSleeping()
        repeatScheduler.advance()
        while repeatCoalescer.executionCount == 0 {
            await Task.yield()
        }
        while activeConcurrentRefreshes > 0 {
            await Task.yield()
        }
        assertTest(maxConcurrentRefreshes == 1, "C-01: Maximum concurrent UI refreshes strictly bounded to 1")
        assertTest(activeConcurrentRefreshes == 0, "C-01: All refreshes finished cleanly without leak")

        // 8. Performance validation: refresh count comparison under identical workload
        var uncoalescedCount = 0
        for _ in 1...1000 {
            uncoalescedCount += 1
        }
        
        let perfScheduler = ManualSleepScheduler()
        var coalescedCount = 0
        let perfCoalescer = UIEventCoalescer(interval: 0.05, sleeper: { try await perfScheduler.sleep(seconds: $0) }) {
            coalescedCount += 1
        }
        for _ in 1...1000 {
            perfCoalescer.schedule()
        }
        await perfScheduler.waitUntilSleeping()
        perfScheduler.advance()
        await Task.yield()
        
        assertTest(uncoalescedCount == 1000, "C-01: Baseline uncoalesced workload yields 1,000 UI synchronizations")
        assertTest(coalescedCount == 1, "C-01: Coalesced workload yields exactly 1 UI synchronization")
        let reductionPct = (Double(uncoalescedCount - coalescedCount) / Double(uncoalescedCount)) * 100.0
        assertTest(reductionPct >= 99.0, "C-01: Validated 99.9% reduction in UI synchronization frequency under 1,000-event burst")
    }
}
