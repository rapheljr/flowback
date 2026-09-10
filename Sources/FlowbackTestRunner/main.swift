import Foundation
import AppKit
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackTestHarness

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
}

@MainActor
func testGroup(_ name: String, _ block: @MainActor () async throws -> Void) async {
    print("\n[TEST SUITE] \(name)")
    do {
        try await block()
    } catch {
        print("  ✗ CRITICAL SUITE ERROR in \(name): \(error.localizedDescription)")
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
}

// 6. Acceptance Scenarios A through J
await testGroup("Final Acceptance Scenarios A through J") {
    let mockApp = MockApplicationController()
    let mockWin = MockWindowController()
    let mockIdle = MockIdleTracker(idleSeconds: 30.0)
    let mockSpace = MockSpaceController()
    let intentEngine = UserIntentEngine(idleTracker: mockIdle, windowController: mockWin, spaceController: mockSpace)
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
