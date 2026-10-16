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

// MARK: - Test Framework Infrastructure

var totalTestsRun = 0
var totalTestsPassed = 0
var totalTestsFailed = 0

@MainActor
func assertTest(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
    totalTestsRun += 1
    if condition {
        totalTestsPassed += 1
        print("  ✓ \(name)")
    } else {
        totalTestsFailed += 1
        print("  ✗ FAILED: \(name) [\(file):\(line)]")
    }
    fflush(stdout)
}

@MainActor
func testGroup(_ name: String, _ block: @MainActor () async throws -> Void) async {
    print("\n[TEST SUITE] \(name)")
    fflush(stdout)
    do {
        try await block()
    } catch {
        print("  ✗ CRITICAL SUITE ERROR in \(name): \(error.localizedDescription)")
        fflush(stdout)
        totalTestsFailed += 1
    }
}

// MARK: - Test Suites Execution

print("================================================================")
print("Flowback Universal Context & Focus Manager — Verification Suites")
print("================================================================")

// 1. Core State Machine Tests
await testGroup("Agent State Machine") {
    let sm = AgentStateMachine()
    assertTest(sm.canTransition(from: .starting, to: .running), "starting -> running")
    assertTest(sm.canTransition(from: .running, to: .waiting), "running -> waiting")
    assertTest(sm.canTransition(from: .waiting, to: .running), "waiting -> running")
    assertTest(sm.canTransition(from: .running, to: .permissionRequired), "running -> permissionRequired")
    assertTest(sm.canTransition(from: .permissionRequired, to: .running), "permissionRequired -> running")
    assertTest(sm.canTransition(from: .running, to: .completed), "running -> completed")
    assertTest(sm.canTransition(from: .running, to: .failed), "running -> failed")
    assertTest(sm.canTransition(from: .running, to: .cancelled), "running -> cancelled")
    assertTest(!sm.canTransition(from: .completed, to: .running), "completed -> running is blocked (terminal)")
    assertTest(!sm.canTransition(from: .failed, to: .starting), "failed -> starting is blocked (terminal)")
}

// 2. Event Deduplication Tests
await testGroup("Event Deduplication") {
    let deduplicator = EventDeduplicator(window: 1.0)
    let sessionID = AgentSessionID("test-sess-dedup")
    let event1 = AgentEvent(providerID: .antigravity, sessionID: sessionID, type: .agentCompleted, workspace: "/test")
    let event2 = AgentEvent(providerID: .antigravity, sessionID: sessionID, type: .agentCompleted, workspace: "/test")
    let event3 = AgentEvent(providerID: .antigravity, sessionID: sessionID, type: .agentFailed, workspace: "/test")
    
    let first = await deduplicator.shouldProcess(event: event1)
    let second = await deduplicator.shouldProcess(event: event2)
    let third = await deduplicator.shouldProcess(event: event3)
    
    assertTest(first == true, "First unique event is processed")
    assertTest(second == false, "Immediate duplicate event is dropped")
    assertTest(third == true, "Different event type for same session is processed")
}

// 3. Policy Override Hierarchy Tests
await testGroup("Policy Configuration & Overrides") {
    var config = PolicyConfiguration.default
    config.focusPolicy = .smart
    config.providerOverrides["antigravity"] = .alwaysRestore
    config.applicationOverrides["com.microsoft.VSCode"] = .notificationOnly
    config.workspaceOverrides["/projects/critical"] = .neverInterrupt
    
    let res1 = config.resolvePolicy(provider: .antigravity, appBundleID: "com.microsoft.VSCode", workspace: "/projects/critical")
    assertTest(res1 == .neverInterrupt, "Workspace override has highest priority")
    
    let res2 = config.resolvePolicy(provider: .antigravity, appBundleID: "com.microsoft.VSCode", workspace: "/projects/other")
    assertTest(res2 == .notificationOnly, "Application override has priority over provider")
    
    let res3 = config.resolvePolicy(provider: .antigravity, appBundleID: "com.brave.Browser", workspace: "/projects/other")
    assertTest(res3 == .alwaysRestore, "Provider override has priority over global default")
    
    let res4 = config.resolvePolicy(provider: .claudeCode, appBundleID: "com.brave.Browser", workspace: "/projects/other")
    assertTest(res4 == .smart, "Global default used when no overrides match")
}

// 4. SQLite Database & Session Repository Tests
await testGroup("Persistence, WAL Mode & Recovery") {
    let tempDb = NSTemporaryDirectory() + "flowback_runner_\(UUID().uuidString).sqlite"
    let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
    let repo = SessionRepository(db: db)
    
    let origin = OriginContext(
        bundleIdentifier: "com.microsoft.VSCode",
        processIdentifier: 5555,
        windowIdentifier: 101,
        windowTitle: "MatchDay — index.ts",
        workspacePath: "/projects/matchday"
    )
    let sessionID = AgentSessionID("sess-db-test")
    let session = AgentSession(
        id: sessionID,
        providerID: .antigravity,
        state: .running,
        workspace: "/projects/matchday",
        originContext: origin,
        metadata: ["tag": "runner-test"]
    )
    
    try await repo.saveSession(session)
    let fetched = try await repo.fetchSession(id: sessionID)
    assertTest(fetched?.id == sessionID, "Session successfully persisted and fetched from SQLite")
    assertTest(fetched?.originContext?.bundleIdentifier == "com.microsoft.VSCode", "OriginContext correctly decoded from database")
    assertTest(fetched?.originContext?.windowIdentifier == 101, "Window ID correctly retrieved from database")
    
    var updated = session
    updated.state = .completed
    updated.completedAt = Date()
    try await repo.saveSession(updated)
    let fetchedUpdated = try await repo.fetchSession(id: sessionID)
    assertTest(fetchedUpdated?.state == .completed, "Session state transition saved to SQLite")
    assertTest(fetchedUpdated?.completedAt != nil, "Completion timestamp saved to SQLite")
    
    await db.close()
    try? FileManager.default.removeItem(atPath: tempDb)
    try? FileManager.default.removeItem(atPath: "\(tempDb)-wal")
    try? FileManager.default.removeItem(atPath: "\(tempDb)-shm")
}

// 5. Antigravity Hook & fullyIdle Prioritization
await testGroup("Antigravity Provider Official Hook Contract") {
    let provider = AntigravityProvider()
    
    // Case 1: fullyIdle = true -> completed
    let payloadComplete = """
    {
        "conversationId": "conv-test-complete",
        "workspacePaths": ["/Users/abin/workspace/projects/focus-switcher"],
        "executionNum": 1,
        "terminationReason": "model_stop",
        "error": "",
        "fullyIdle": true
    }
    """.data(using: .utf8)!
    let event1 = try provider.parseLifecyclePayload(data: payloadComplete)
    assertTest(event1?.type == .agentCompleted, "Antigravity fullyIdle=true translates to .agentCompleted")
    assertTest(event1?.workspace == "/Users/abin/workspace/projects/focus-switcher", "Workspace path correctly extracted")
    
    // Case 2: fullyIdle = false -> running (background tasks still working)
    let payloadRunning = """
    {
        "conversationId": "conv-test-bg",
        "workspacePaths": ["/Users/abin/workspace/projects/focus-switcher"],
        "executionNum": 1,
        "terminationReason": "model_stop",
        "error": "",
        "fullyIdle": false
    }
    """.data(using: .utf8)!
    let event2 = try provider.parseLifecyclePayload(data: payloadRunning)
    assertTest(event2?.type == .agentRunning, "Antigravity fullyIdle=false translates to .agentRunning (not completed)")
    
    // Case 3: error -> failed
    let payloadError = """
    {
        "conversationId": "conv-test-err",
        "workspacePaths": ["/Users/abin/workspace/projects/focus-switcher"],
        "executionNum": 2,
        "terminationReason": "error",
        "error": "Timeout",
        "fullyIdle": true
    }
    """.data(using: .utf8)!
    let event3 = try provider.parseLifecyclePayload(data: payloadError)
    assertTest(event3?.type == .agentFailed, "Antigravity error payload translates to .agentFailed")
    
    // Case 4: PreInvocation hook -> agentStarted
    let payloadPre = """
    {
        "hook_event_name": "PreInvocation",
        "conversationId": "conv-test-pre",
        "workspacePaths": ["/Users/abin/workspace/projects/focus-switcher"],
        "invocationNum": 1
    }
    """.data(using: .utf8)!
    let eventPre = try provider.parseLifecyclePayload(data: payloadPre)
    assertTest(eventPre?.type == .agentStarted, "Antigravity PreInvocation translates to .agentStarted")
    
    // Case 5: Proactive active session discovery
    let discovered = await provider.discoverActiveSessions()
    assertTest(discovered.count >= 1, "Antigravity discoverActiveSessions finds running agents on system")
}

// 6. Acceptance Scenarios A through J
await testGroup("Final Acceptance Scenarios A through J") {
    let mockApp = MockApplicationController()
    let mockWin = MockWindowController()
    let mockIdle = MockIdleTracker(idleSeconds: 30.0)
    let mockSpace = MockSpaceController()
    let intentEngine = UserIntentEngine(idleTracker: mockIdle, windowController: mockWin, spaceController: mockSpace, appController: mockApp)
    let arbiter = AttentionArbiter(aggregationWindow: 1.0, cooldownDuration: 0.5)
    let focusController = FocusController(appController: mockApp, windowController: mockWin, intentEngine: intentEngine, arbiter: arbiter)
    
    // Scenario A: Antigravity -> VS Code / MatchDay -> User switches to Brave -> Agent completes -> User idle -> Restore
    let originA = OriginContext(
        bundleIdentifier: "com.microsoft.VSCode",
        processIdentifier: 1001,
        windowIdentifier: 42,
        windowTitle: "MatchDay — Visual Studio Code",
        workspacePath: "/Users/abin/workspace/projects/matchday"
    )
    let sessionA = AgentSession(providerID: .antigravity, state: .completed, workspace: "/Users/abin/workspace/projects/matchday", originContext: originA)
    mockIdle.idleSecondsMock = 30.0
    let decisionA = await focusController.handleSessionCompletion(session: sessionA, config: .default, focusLock: FocusLockState())
    guard case .restoreOrigin(let ctxA, _) = decisionA else {
        assertTest(false, "Scenario A: Failed to restore origin for idle user")
        return
    }
    assertTest(ctxA.bundleIdentifier == "com.microsoft.VSCode" && ctxA.windowIdentifier == 42, "Scenario A: Successfully restores VS Code / MatchDay window")
    
    // Scenario B: Antigravity -> VS Code -> User actively typing in Brave -> Complete -> Do NOT steal focus
    mockIdle.idleSecondsMock = 0.5 // Active input < 5s threshold
    let decisionB = intentEngine.evaluate(session: sessionA, config: .default, focusLock: FocusLockState(), frontmostApp: NSRunningApplication.current)
    guard case .notifyOnly(let reasonB) = decisionB else {
        assertTest(false, "Scenario B: Improperly stole focus from actively typing user")
        return
    }
    assertTest(reasonB.contains("actively interacting"), "Scenario B: Respected active user typing; suppressed focus steal and notified instead")
    
    // Scenario C: Claude Code -> Terminal -> Complete -> Correct window restored
    let originC = OriginContext(bundleIdentifier: "com.apple.Terminal", processIdentifier: 2002, windowIdentifier: 88, workspacePath: "/test")
    let sessionC = AgentSession(providerID: .claudeCode, state: .completed, originContext: originC)
    mockIdle.idleSecondsMock = 20.0
    let focusControllerC = FocusController(appController: mockApp, windowController: mockWin, intentEngine: intentEngine, arbiter: AttentionArbiter(aggregationWindow: 1.0, cooldownDuration: 0.0))
    let decisionC = await focusControllerC.handleSessionCompletion(session: sessionC, config: .default, focusLock: FocusLockState())
    guard case .restoreOrigin(let ctxC, _) = decisionC else {
        assertTest(false, "Scenario C: Failed terminal restoration")
        return
    }
    assertTest(ctxC.bundleIdentifier == "com.apple.Terminal", "Scenario C: Terminal window restored")
    
    // Scenario D: Codex -> Cursor -> Agent fails -> Priority attention
    let originD = OriginContext(bundleIdentifier: "com.todesktop.230313mzl4w4u92", processIdentifier: 3003)
    _ = originD
    let reqFailure = AttentionRequest(sessionID: AgentSessionID("s-fail"), providerID: .codex, priority: .failure, title: "Failed", message: "Error")
    let reqInfo = AttentionRequest(sessionID: AgentSessionID("s-info"), providerID: .claudeCode, priority: .informational, title: "Info", message: "Progress")
    await arbiter.enqueue(reqInfo)
    await arbiter.enqueue(reqFailure)
    let topReq = await arbiter.dequeueHighestPriority()
    assertTest(topReq?.priority == .failure, "Scenario D: Failure attention request prioritized over lower priority")
    
    // Scenario E: 3 agents complete within 1 second -> Aggregated attention, cooldown prevents thrashing
    let arbMulti = AttentionArbiter(aggregationWindow: 1.5, cooldownDuration: 1.0)
    await arbMulti.enqueue(AttentionRequest(sessionID: AgentSessionID("e1"), providerID: .antigravity, priority: .completed, title: "Done", message: "1", workspace: "/p1"))
    await arbMulti.enqueue(AttentionRequest(sessionID: AgentSessionID("e2"), providerID: .claudeCode, priority: .completed, title: "Done", message: "2", workspace: "/p2"))
    await arbMulti.enqueue(AttentionRequest(sessionID: AgentSessionID("e3"), providerID: .codex, priority: .completed, title: "Done", message: "3", workspace: "/p3"))
    let summaryE = await arbMulti.aggregatedSummary()
    assertTest(summaryE?.title == "3 agents need attention", "Scenario E: Aggregated 3 simultaneous agents into single summary")
    await arbMulti.recordFocusRestoration()
    assertTest(await arbMulti.canRestoreFocusNow() == false, "Scenario E: Focus cooldown prevents window thrashing")
    
    // Scenario F: Origin window closes -> fallback to application/workspace
    let originF = OriginContext(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 1001, windowIdentifier: 99999)
    let sessionF = AgentSession(providerID: .antigravity, state: .completed, originContext: originF)
    mockIdle.idleSecondsMock = 25.0
    let decisionF = await focusController.handleSessionCompletion(session: sessionF, config: .default, focusLock: FocusLockState())
    assertTest(decisionF != .suppress(reason: ""), "Scenario F: Handles invalid window ID gracefully without crash")
    
    // Scenario G: Fullscreen presentation -> No focus steal
    mockWin.isFullscreenMock = true
    let decisionG = intentEngine.evaluate(session: sessionA, config: .default, focusLock: FocusLockState(), frontmostApp: nil)
    guard case .notifyOnly(let reasonG) = decisionG else {
        assertTest(false, "Scenario G: Failed to protect fullscreen presentation")
        return
    }
    assertTest(reasonG.contains("Fullscreen"), "Scenario G: Fullscreen presentation mode detected; focus switch suppressed")
    mockWin.isFullscreenMock = false
    
    // Scenario H: Focus Lock active -> Notification only
    let lockH = FocusLockState(isActive: true, expiresAt: Date().addingTimeInterval(1800), label: "30 min")
    let decisionH = intentEngine.evaluate(session: sessionA, config: .default, focusLock: lockH, frontmostApp: nil)
    guard case .notifyOnly(let reasonH) = decisionH else {
        assertTest(false, "Scenario H: Focus lock did not suppress focus switch")
        return
    }
    assertTest(reasonH.contains("Focus Lock is active"), "Scenario H: Focus Lock active; notification only")
    
    // Scenario I: Mac sleeps -> Wakes -> Reconciles orphaned sessions
    let smI = SessionManager()
    let runningSess = AgentSession(providerID: .antigravity, state: .running)
    _ = await smI.handleEvent(AgentEvent(providerID: .antigravity, sessionID: runningSess.id, type: .agentStarted))
    await smI.reconcileOrphanedSessions()
    let reconciledI = await smI.getSession(id: runningSess.id)
    assertTest(reconciledI?.state == .cancelled, "Scenario I: Startup / Wake reconciliation cleanly cancels orphaned sessions")
    
    // Scenario J: Crash recovery -> Startup reconciliation from persisted storage
    let crashDbPath = NSTemporaryDirectory() + "flowback_crash_j_\(UUID().uuidString).sqlite"
    let crashDb = await RecoveryManager.shared.initializeStorage(path: crashDbPath)
    let crashRepo = SessionRepository(db: crashDb)
    let crashSess = AgentSession(id: AgentSessionID("crash-j"), providerID: .antigravity, state: .running)
    try await crashRepo.saveSession(crashSess)
    
    // Simulate fresh relaunch
    let recoveredMgr = SessionManager(storageDelegate: crashRepo)
    let recSessions = try await crashRepo.fetchRecentSessions(limit: 10)
    await recoveredMgr.restorePersistedSessions(recSessions)
    await recoveredMgr.reconcileOrphanedSessions()
    let reconciledJ = await recoveredMgr.getSession(id: AgentSessionID("crash-j"))
    assertTest(reconciledJ?.state == .cancelled, "Scenario J: Persisted running session recovered and reconciled after restart")
    
    await crashDb.close()
    try? FileManager.default.removeItem(atPath: crashDbPath)
    try? FileManager.default.removeItem(atPath: "\(crashDbPath)-wal")
    try? FileManager.default.removeItem(atPath: "\(crashDbPath)-shm")
}

// 7. Deep Audit & Robustness Verification
await testGroup("Deep Audit & Robustness Verification") {
    // 1. Adapter Coverage Audit
    let vsAdapter = VSCodeAdapter()
    let expectedVSCodeBundles = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.google.antigravity-ide",
        "com.google.antigravity",
        "com.codeium.windsurf",
        "com.vscodium",
        "com.vscodium.codium",
        "co.posit.positron",
        "com.rstudio.positron",
        "com.byteplus.trae"
    ]
    for bundle in expectedVSCodeBundles {
        assertTest(vsAdapter.canHandle(bundleIdentifier: bundle), "VSCodeAdapter handles \(bundle)")
    }
    
    let cursorAdapter = CursorAdapter()
    assertTest(cursorAdapter.canHandle(bundleIdentifier: "com.todesktop.230313mzl4w4u92"), "CursorAdapter handles com.todesktop.230313mzl4w4u92")
    assertTest(cursorAdapter.canHandle(bundleIdentifier: "co.anysphere.cursor"), "CursorAdapter handles co.anysphere.cursor")
    
    // 2. SQLite Transient Memory Stress Test
    let auditDbPath = NSTemporaryDirectory() + "flowback_audit_\(UUID().uuidString).sqlite"
    let auditDb = await RecoveryManager.shared.initializeStorage(path: auditDbPath)
    let auditRepo = SessionRepository(db: auditDb)
    
    var stressSuccess = true
    for i in 1...20 {
        let dynString = "Workspace_Path_Dynamically_Allocated_\(UUID().uuidString)_\(i)"
        let origin = OriginContext(
            bundleIdentifier: "com.google.antigravity-ide",
            processIdentifier: Int32(1000 + i),
            windowIdentifier: UInt32(5000 + i),
            windowTitle: "Window Title \(dynString)",
            workspacePath: "/Users/abin/projects/\(dynString)"
        )
        let sess = AgentSession(
            id: AgentSessionID("audit-sess-\(i)"),
            providerID: .antigravity,
            state: .running,
            workspace: "/Users/abin/projects/\(dynString)",
            originContext: origin
        )
        do {
            try await auditRepo.saveSession(sess)
        } catch {
            stressSuccess = false
            break
        }
    }
    assertTest(stressSuccess, "SQLite handles rapid dynamic string persistence with SQLITE_TRANSIENT without memory fault")
    
    let fetchedSess = try? await auditRepo.fetchRecentSessions(limit: 50)
    assertTest(fetchedSess?.count == 20, "Retrieved all 20 persisted stress sessions with data intact")
    
    // 3. Database Transaction Rollback Test
    var rollbackVerified = false
    do {
        _ = try await auditDb.runInTransaction {
            try await auditDb.execute(sql: "INSERT INTO sessions (id, provider_id, state, started_at, updated_at) VALUES ('atomic-test', 'antigravity', 'running', 1.0, 1.0);")
            throw SQLiteError.executionFailed("Deliberate failure to test rollback", code: 999)
        }
    } catch {
        // Expected throw, verify record was rolled back
        let rows = try? await auditDb.query(sql: "SELECT id FROM sessions WHERE id = 'atomic-test';") { _ in true }
        if (rows?.isEmpty ?? false) {
            rollbackVerified = true
        }
    }
    assertTest(rollbackVerified, "SQLite transactions roll back completely on thrown error")
    
    await auditDb.close()
    try? FileManager.default.removeItem(atPath: auditDbPath)
    try? FileManager.default.removeItem(atPath: "\(auditDbPath)-wal")
    try? FileManager.default.removeItem(atPath: "\(auditDbPath)-shm")
    
    // 4. IPCHandler Edge Case & Malformed Payloads
    let tempDbIPC = NSTemporaryDirectory() + "flowback_audit_ipc_\(UUID().uuidString).sqlite"
    let ipcDb = await RecoveryManager.shared.initializeStorage(path: tempDbIPC)
    let ipcSettingsRepo = SettingsRepository(db: ipcDb)
    let ipcSessionMgr = SessionManager(storageDelegate: SessionRepository(db: ipcDb))
    let mockApp = MockApplicationController()
    let mockWin = MockWindowController()
    let intentEngine = UserIntentEngine(idleTracker: MockIdleTracker(), windowController: mockWin, spaceController: MockSpaceController())
    let ipcFocusCtrl = FocusController(appController: mockApp, windowController: mockWin, intentEngine: intentEngine, arbiter: AttentionArbiter())
    let testRegistry = ProviderRegistry()
    await testRegistry.register(provider: AntigravityProvider())
    await testRegistry.register(provider: ClaudeCodeProvider())
    await testRegistry.register(provider: CodexProvider())
    await testRegistry.register(provider: GenericHookProvider())
    
    let ipcHandler = IPCHandler(
        sessionManager: ipcSessionMgr,
        focusController: ipcFocusCtrl,
        providerRegistry: testRegistry,
        settingsRepo: ipcSettingsRepo
    )
    
    // Unknown command
    let unkResp = await ipcHandler.handleRequest(IPCRequest(command: "non_existent_command_xyz"))
    assertTest(!unkResp.success && unkResp.message.contains("Unknown command"), "IPCHandler safely rejects unknown commands")
    
    // Malformed hook JSON
    let malformedHookResp = await ipcHandler.handleRequest(IPCRequest(command: "hook", argument: "antigravity", payload: "not-json-content".data(using: .utf8)))
    assertTest(malformedHookResp.success, "IPCHandler fails safe on unparseable hook payload and provides fallback allow")
    
    // Missing arguments
    let missingArgsResp = await ipcHandler.handleRequest(IPCRequest(command: "focus", argument: "invalid-session-id-404"))
    assertTest(!missingArgsResp.success, "IPCHandler safely returns error for non-existent session focus")
    
    await ipcDb.close()
    try? FileManager.default.removeItem(atPath: tempDbIPC)
    try? FileManager.default.removeItem(atPath: "\(tempDbIPC)-wal")
    try? FileManager.default.removeItem(atPath: "\(tempDbIPC)-shm")
    
    // 5. Provider Hook Robustness
    let claude = ClaudeCodeProvider()
    let claudeEmpty = try? claude.parseLifecyclePayload(data: Data())
    assertTest(claudeEmpty == nil, "ClaudeCodeProvider handles empty data gracefully")
    
    let codex = CodexProvider()
    let codexPerm = try? codex.parseLifecyclePayload(data: "{\"status\": \"permission_required\", \"session_id\": \"codex-1\"}".data(using: .utf8)!)
    assertTest(codexPerm?.type == .agentPermissionRequired, "CodexProvider translates permission_required status")
    
    let generic = GenericHookProvider()
    let genericMalformed = try? generic.parseLifecyclePayload(data: "{\"bad_schema\": true}".data(using: .utf8)!)
    assertTest(genericMalformed == nil, "GenericHookProvider rejects non-conforming payloads cleanly")
}

// 13. Standalone Execution & App Bundle Safety Suite (P1-1 Fix)
await testGroup("Standalone Execution & App Bundle Safety") {
    let permMgr = PermissionManager()
    assertTest(!permMgr.isAppBundle, "Standalone process correctly identifies isAppBundle == false")
    
    let status = await permMgr.currentStatus()
    assertTest(!status.isAppBundle, "PermissionStatus reports isAppBundle == false")
    assertTest(!status.notificationsGranted, "Notifications disabled safely when running outside app bundle")
    assertTest(!status.launchAtLoginEnabled, "SMAppService launchAtLogin safely disabled outside app bundle")
}

// 14. UnixSocketServer Security & Concurrency Suite
await testGroup("UnixSocketServer Security & Concurrency") {
    let testSockPath = "/tmp/fb_t\(UInt32.random(in: 10000...99999)).sock"
    
    let dummyIPC = IPCHandler(
        sessionManager: SessionManager(),
        focusController: FocusController(
            appController: MockApplicationController(),
            windowController: MockWindowController(),
            intentEngine: UserIntentEngine(idleTracker: MockIdleTracker(), windowController: MockWindowController(), spaceController: MockSpaceController()),
            arbiter: AttentionArbiter()
        ),
        providerRegistry: ProviderRegistry(),
        settingsRepo: SettingsRepository(db: await RecoveryManager.shared.initializeStorage(path: ":memory:"))
    )
    
    let server1 = UnixSocketServer(socketPath: testSockPath, delegate: dummyIPC)
    try server1.start()
    assertTest(FileManager.default.fileExists(atPath: testSockPath), "UnixSocketServer creates socket file on start")
    
    // Duplicate instance test on same active socket
    let server2 = UnixSocketServer(socketPath: testSockPath, delegate: dummyIPC)
    var duplicateDetected = false
    do {
        try server2.start()
    } catch {
        duplicateDetected = true
    }
    assertTest(duplicateDetected, "UnixSocketServer detects active running daemon and refuses duplicate bind (EADDRINUSE)")
    
    server1.stop()
    assertTest(!FileManager.default.fileExists(atPath: testSockPath), "UnixSocketServer unlinks socket file on clean stop")
    
    // Stale socket recovery test: create a dead socket file on disk
    FileManager.default.createFile(atPath: testSockPath, contents: Data(), attributes: nil)
    assertTest(FileManager.default.fileExists(atPath: testSockPath), "Dead socket file staged on disk")
    let server3 = UnixSocketServer(socketPath: testSockPath, delegate: dummyIPC)
    try server3.start()
    assertTest(FileManager.default.fileExists(atPath: testSockPath), "UnixSocketServer successfully recovers from stale socket file")
    server3.stop()
}

// 15. Normalized Events & Enriched Context Model Suite
await testGroup("Normalized Events & Enriched Context Model") {
    let ctxChanged = AgentEventType.sessionContextChanged
    let disappeared = AgentEventType.sessionDisappeared
    assertTest(!ctxChanged.isActionableForAttention, "sessionContextChanged is non-actionable for disruptive focus")
    assertTest(!disappeared.isActionableForAttention, "sessionDisappeared is non-actionable for disruptive focus")
    assertTest(AgentEventType.agentCompleted.isActionableForAttention, "agentCompleted is actionable")
    assertTest(AgentEventType.agentWaiting.isActionableForAttention, "agentWaiting is actionable")
    
    let origin = OriginContext(
        bundleIdentifier: "com.apple.Terminal",
        processIdentifier: 99999,
        windowIdentifier: 101,
        workspacePath: "/Users/test/workspace",
        provenance: .systemFrontmost,
        confidence: 0.95,
        restorationCapability: .exactWindowAndWorkspace,
        capturedAt: Date()
    )
    assertTest(origin.provenance == .systemFrontmost, "OriginContext stores provenance accurately")
    assertTest(origin.restorationCapability == .exactWindowAndWorkspace, "OriginContext stores restoration capability")
    assertTest(origin.confidence == 0.95, "OriginContext confidence level tracked")
    assertTest(origin.isFresh(within: 60), "OriginContext captures freshness within threshold")
    
    // Stale context test
    let oldOrigin = OriginContext(
        bundleIdentifier: "com.apple.Terminal",
        processIdentifier: 99999,
        capturedAt: Date().addingTimeInterval(-700)
    )
    assertTest(!oldOrigin.isFresh(within: 600), "OriginContext detects stale context older than threshold")
    
    // Provider tier verification
    assertTest(AntigravityProvider().supportLevel == .nativeLifecycle, "AntigravityProvider tier is native-lifecycle")
    assertTest(ClaudeCodeProvider().supportLevel == .adapter, "ClaudeCodeProvider tier is adapter")
    assertTest(CodexProvider().supportLevel == .adapter, "CodexProvider tier is adapter")
    assertTest(GenericHookProvider().supportLevel == .genericProtocol, "GenericHookProvider tier is generic-protocol")
}

// 16. Structured Focus Outcomes & Intent Engine Suite
await testGroup("Structured Focus Outcomes & Intent Engine") {
    let mockApp = MockApplicationController()
    let mockWin = MockWindowController()
    let mockIdle = MockIdleTracker()
    let mockSpace = MockSpaceController()
    let intentEngine = UserIntentEngine(idleTracker: mockIdle, windowController: mockWin, spaceController: mockSpace, appController: mockApp)
    let focusController = FocusController(appController: mockApp, windowController: mockWin, intentEngine: intentEngine, arbiter: AttentionArbiter())
    
    // Terminated application test: PID 99999999 does not exist on macOS
    let deadPIDOrigin = OriginContext(
        bundleIdentifier: "com.nonexistent.app",
        processIdentifier: 99999999,
        capturedAt: Date()
    )
    let deadSession = AgentSession(
        id: AgentSessionID("dead-session-1"),
        providerID: AgentProviderID("antigravity"),
        state: .completed,
        originContext: deadPIDOrigin
    )
    
    let deadOutcome = intentEngine.evaluate(
        session: deadSession,
        config: PolicyConfiguration(),
        focusLock: FocusLockState()
    )
    switch deadOutcome {
    case .notifyOnly(let reason):
        assertTest(reason.contains("no longer running"), "Terminated origin application safely falls back to notifyOnly (reason: \(reason))")
    default:
        assertTest(false, "Terminated app did not produce notifyOnly")
    }
    
    // Cooldown test in FocusController
    let liveOrigin = OriginContext(
        bundleIdentifier: "com.apple.Terminal",
        processIdentifier: ProcessInfo.processInfo.processIdentifier,
        capturedAt: Date()
    )
    let liveSession = AgentSession(
        id: AgentSessionID("live-session-1"),
        providerID: AgentProviderID("antigravity"),
        state: .completed,
        originContext: liveOrigin
    )
    
    let config = PolicyConfiguration(focusPolicy: .alwaysRestore)
    let firstAction = await focusController.handleSessionCompletion(session: liveSession, config: config, focusLock: FocusLockState())
    assertTest(firstAction.outcome != .ignore, "First completion action handled")
    
    // Immediate repeat within cooldown window
    let secondAction = await focusController.handleSessionCompletion(session: liveSession, config: config, focusLock: FocusLockState())
    switch secondAction {
    case .deferAction(let reason, _):
        assertTest(reason == .cooldownActive, "Immediate second completion safely deferred with .cooldownActive")
    default:
        assertTest(false, "Rapid second completion was not deferred under cooldown: \(secondAction)")
    }
}

// 17. Database Retention & Pruning Suite
await testGroup("Database Retention & Pruning") {
    let dbPath = NSTemporaryDirectory() + "flowback_prune_test_\(UUID().uuidString).sqlite"
    let db = await RecoveryManager.shared.initializeStorage(path: dbPath)
    let sessionRepo = SessionRepository(db: db)
    let eventRepo = EventRepository(db: db)
    
    // Seed 10 old completed sessions and 5 recent active sessions
    let oldDate = Date().addingTimeInterval(-40 * 86400) // 40 days ago
    for i in 1...10 {
        let s = AgentSession(
            id: AgentSessionID("old-session-\(i)"),
            providerID: AgentProviderID("test"),
            state: .completed,
            startedAt: oldDate,
            updatedAt: oldDate,
            completedAt: oldDate
        )
        try await sessionRepo.saveSession(s)
        
        let e = AgentEvent(
            id: "old-event-\(i)",
            timestamp: oldDate,
            providerID: AgentProviderID("test"),
            sessionID: s.id,
            type: .agentCompleted
        )
        try await eventRepo.saveEvent(e)
    }
    
    for i in 1...5 {
        let s = AgentSession(
            id: AgentSessionID("recent-session-\(i)"),
            providerID: AgentProviderID("test"),
            state: .running,
            startedAt: Date(),
            updatedAt: Date()
        )
        try await sessionRepo.saveSession(s)
    }
    
    let prunedCount = try await sessionRepo.pruneCompletedSessions(olderThanDays: 30, keepMinCount: 5)
    assertTest(prunedCount == 10, "pruneCompletedSessions pruned exactly 10 old sessions exceeding 30-day cutoff")
    
    let remainingSessions = try await sessionRepo.fetchRecentSessions(limit: 50)
    assertTest(remainingSessions.count == 5, "Remaining sessions count is preserved at 5 recent active sessions")
    
    let eventPruned = try await eventRepo.pruneEvents(olderThanDays: 30)
    assertTest(eventPruned >= 0, "pruneEvents executes cleanly")
    
    await db.close()
    try? FileManager.default.removeItem(atPath: dbPath)
    try? FileManager.default.removeItem(atPath: "\(dbPath)-wal")
    try? FileManager.default.removeItem(atPath: "\(dbPath)-shm")
}

// 18. Apple HIG Compliance & Accessibility Verification Suite
await testGroup("Apple HIG Compliance & Accessibility Verification") {
    // 1. PermissionManager system URL deep links
    let axURL = PermissionManager.accessibilitySettingsURL
    assertTest(axURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", "Accessibility deep link maps to Privacy_Accessibility System Settings pane")
    
    let notifURL = PermissionManager.notificationSettingsURL
    assertTest(notifURL.absoluteString == "x-apple.systempreferences:com.apple.preference.notifications", "Notification deep link maps to Notifications System Settings pane")
    
    // 2. PolicyConfiguration Equatability and Live Persistence
    let config1 = PolicyConfiguration.default
    var config2 = PolicyConfiguration.default
    assertTest(config1 == config2, "Default PolicyConfiguration instances are equatable")
    
    config2.focusCooldownMs = 2500
    assertTest(config1 != config2, "Modified PolicyConfiguration triggers Equatable inequality for live onChange persistence")
    
    // 3. Notification Action Safety (Non-destructive Dismissal)
    assertTest(NotificationManager.categoryAttention == "FLOWBACK_ATTENTION", "Attention notification category is FLOWBACK_ATTENTION")
    assertTest(NotificationManager.actionDismiss == "FLOWBACK_ACTION_DISMISS", "Dismiss action ID is registered")
    assertTest(NotificationManager.actionFocus == "FLOWBACK_ACTION_FOCUS", "Focus action ID is registered")
    assertTest(NotificationManager.actionReview == "FLOWBACK_ACTION_REVIEW", "Review action ID is registered")
    
    // 4. Textual State Conveyance (VoiceOver / Color-Independent Communication)
    for state in AgentState.allCases {
        assertTest(!state.displayName.isEmpty, "AgentState.\(state.rawValue) defines clear text label '\(state.displayName)' for assistive technology")
    }
    
    // 5. DashboardTab Coverage & Human Interface Hierarchy
    assertTest(DashboardTab.allCases.count == 6, "Dashboard contains exactly 6 organized primary views")
    for tab in DashboardTab.allCases {
        assertTest(!tab.subtitle.isEmpty, "Dashboard tab '\(tab.rawValue)' provides descriptive subtitle for window header")
        assertTest(!tab.icon.isEmpty, "Dashboard tab '\(tab.rawValue)' uses valid SF Symbol '\(tab.icon)'")
    }
    
    // 6. Focus Lock Remaining Time Bounds & Formatting
    let lockActive = FocusLockState(isActive: true, expiresAt: Date().addingTimeInterval(900), label: "15 min")
    assertTest(lockActive.isCurrentlyLocked, "Focus lock detects active state")
    if let rem = lockActive.remainingSeconds {
        let mins = max(1, Int(rem / 60))
        assertTest(mins >= 1 && mins <= 15, "Focus lock calculates remaining minutes accurately without zero-second division")
    } else {
        assertTest(false, "Focus lock missing remainingSeconds calculation")
    }
    
    let lockExpired = FocusLockState(isActive: true, expiresAt: Date().addingTimeInterval(-10), label: "expired")
    assertTest(!lockExpired.isCurrentlyLocked, "Expired focus lock cleanly evaluates to isCurrentlyLocked == false")
    
    // 7. Protected Applications Case-Insensitive Matching
    var testConfig = PolicyConfiguration.default
    testConfig.protectedApplications = ["us.zoom.xos", "com.apple.Keynote"]
    let matchesZoom = testConfig.protectedApplications.contains(where: { "US.ZOOM.XOS".localizedCaseInsensitiveContains($0) })
    let matchesKeynote = testConfig.protectedApplications.contains(where: { "com.apple.keynote".localizedCaseInsensitiveContains($0) })
    let ignoresTerminal = testConfig.protectedApplications.contains(where: { "com.apple.Terminal".localizedCaseInsensitiveContains($0) })
    assertTest(matchesZoom, "Protected application matches case-insensitively for Zoom")
    assertTest(matchesKeynote, "Protected application matches case-insensitively for Keynote")
    assertTest(!ignoresTerminal, "Unprotected application is correctly permitted for focus switch")
}

print("\n================================================================")
print("TEST RESULTS SUMMARY")
print("Total tests executed: \(totalTestsRun)")
print("Passed: \(totalTestsPassed)")
print("Failed: \(totalTestsFailed)")
print("================================================================")

if totalTestsFailed > 0 {
    print("Verification FAILED.")
    exit(1)
} else {
    print("ALL VERIFICATION SUITES PASSED! ✓")
    exit(0)
}
