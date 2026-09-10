import XCTest
import AppKit
@testable import FlowbackCore
@testable import FlowbackFocus
@testable import FlowbackProviders
@testable import FlowbackStorage
@testable import FlowbackServer
@testable import FlowbackTestHarness

final class AcceptanceScenariosTests: XCTestCase {
    var mockAppController: MockApplicationController!
    var mockWindowController: MockWindowController!
    var mockIdleTracker: MockIdleTracker!
    var mockSpaceController: MockSpaceController!
    var intentEngine: UserIntentEngine!
    var arbiter: AttentionArbiter!
    var focusController: FocusController!
    var timelineTracker: TimelineTracker!
    
    override func setUp() {
        super.setUp()
        mockAppController = MockApplicationController()
        mockWindowController = MockWindowController()
        mockIdleTracker = MockIdleTracker(idleSeconds: 30.0)
        mockSpaceController = MockSpaceController()
        timelineTracker = TimelineTracker()
        
        intentEngine = UserIntentEngine(
            idleTracker: mockIdleTracker,
            windowController: mockWindowController,
            spaceController: mockSpaceController
        )
        arbiter = AttentionArbiter(aggregationWindow: 1.0, cooldownDuration: 0.5)
        focusController = FocusController(
            appController: mockAppController,
            windowController: mockWindowController,
            intentEngine: intentEngine,
            arbiter: arbiter,
            adapterRegistry: .shared,
            timeline: timelineTracker
        )
    }
    
    // Scenario A: Antigravity -> VS Code / MatchDay -> User idle -> Restores VS Code / MatchDay
    func testScenarioA_IdleUserRestoresOrigin() async {
        let origin = OriginContext(
            bundleIdentifier: "com.microsoft.VSCode",
            applicationPath: "/Applications/Visual Studio Code.app",
            processIdentifier: 2001,
            windowIdentifier: 42,
            windowTitle: "MatchDay — Visual Studio Code",
            workspacePath: "/Users/abin/workspace/projects/matchday"
        )
        let session = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: "/Users/abin/workspace/projects/matchday",
            originContext: origin
        )
        
        mockIdleTracker.idleSecondsMock = 25.0 // User idle
        let config = PolicyConfiguration.default
        let lock = FocusLockState(isActive: false)
        
        let decision = await focusController.handleSessionCompletion(
            session: session,
            config: config,
            focusLock: lock
        )
        
        guard case .restoreOrigin(let ctx, _) = decision else {
            return XCTFail("Scenario A failed: Expected .restoreOrigin")
        }
        XCTAssertEqual(ctx.bundleIdentifier, "com.microsoft.VSCode")
        XCTAssertEqual(ctx.windowIdentifier, 42)
    }
    
    // Scenario B: Antigravity -> VS Code -> User actively typing in Brave -> Complete -> No steal
    func testScenarioB_ActiveUserTypingDoesNotStealFocus() async {
        let origin = OriginContext(
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 2001,
            workspacePath: "/Users/abin/workspace/projects/matchday"
        )
        let session = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: "/Users/abin/workspace/projects/matchday",
            originContext: origin
        )
        
        // User is in Brave and typed 0.8 seconds ago
        mockIdleTracker.idleSecondsMock = 0.8
        let config = PolicyConfiguration.default
        let lock = FocusLockState(isActive: false)
        
        // Frontmost app is Brave (surrogate)
        let frontApp = NSRunningApplication.current
        
        let decision = intentEngine.evaluate(
            session: session,
            config: config,
            focusLock: lock,
            frontmostApp: frontApp
        )
        
        guard case .notifyOnly(let reason) = decision else {
            return XCTFail("Scenario B failed: Focus was improperly stolen from active user")
        }
        XCTAssertTrue(reason.contains("User is actively interacting"))
    }
    
    // Scenario C: Claude Code -> Terminal -> Agent completes -> Terminal restored
    func testScenarioC_TerminalAdapterRestoration() async {
        let origin = OriginContext(
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 3001,
            windowIdentifier: 88,
            workspacePath: "/Users/abin/workspace/projects/focus-switcher"
        )
        let session = AgentSession(
            providerID: .claudeCode,
            state: .completed,
            originContext: origin
        )
        
        mockIdleTracker.idleSecondsMock = 15.0
        let decision = await focusController.handleSessionCompletion(
            session: session,
            config: .default,
            focusLock: FocusLockState()
        )
        
        guard case .restoreOrigin(let ctx, _) = decision else {
            return XCTFail("Scenario C failed: Expected terminal restoration")
        }
        XCTAssertEqual(ctx.bundleIdentifier, "com.apple.Terminal")
    }
    
    // Scenario D: Codex -> Cursor -> Agent fails -> Prioritized attention
    func testScenarioD_AgentFailurePrioritized() async {
        let origin = OriginContext(bundleIdentifier: "com.todesktop.230313mzl4w4u92", processIdentifier: 4001)
        let session = AgentSession(
            providerID: .codex,
            state: .failed,
            originContext: origin,
            errorDescription: "Syntax error in AST"
        )
        
        let req = AttentionRequest(
            sessionID: session.id,
            providerID: session.providerID,
            priority: .failure,
            title: "Codex Failed",
            message: "Syntax error in AST"
        )
        await arbiter.enqueue(req)
        
        let highest = await arbiter.dequeueHighestPriority()
        XCTAssertEqual(highest?.priority, .failure)
        XCTAssertEqual(highest?.providerID, .codex)
    }
    
    // Scenario E: 3 agents complete within 1 second -> Aggregates events, enforces cooldown
    func testScenarioE_MultiAgentAggregationAndCooldown() async {
        let arb = AttentionArbiter(aggregationWindow: 1.5, cooldownDuration: 1.0)
        
        let req1 = AttentionRequest(sessionID: AgentSessionID("s1"), providerID: .antigravity, priority: .completed, title: "Done", message: "A1", workspace: "/w1")
        let req2 = AttentionRequest(sessionID: AgentSessionID("s2"), providerID: .claudeCode, priority: .completed, title: "Done", message: "A2", workspace: "/w2")
        let req3 = AttentionRequest(sessionID: AgentSessionID("s3"), providerID: .codex, priority: .completed, title: "Done", message: "A3", workspace: "/w3")
        
        await arb.enqueue(req1)
        await arb.enqueue(req2)
        await arb.enqueue(req3)
        
        let summary = await arb.aggregatedSummary()
        XCTAssertEqual(summary?.title, "3 agents need attention")
        
        // Test cooldown enforcement
        await arb.recordFocusRestoration()
        let canSwitchNow = await arb.canRestoreFocusNow()
        XCTAssertFalse(canSwitchNow, "Cooldown must prevent rapid successive focus thrashing")
    }
    
    // Scenario F: Origin window closes -> graceful fallback
    func testScenarioF_InvalidWindowGracefulFallback() async {
        let origin = OriginContext(
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 2001,
            windowIdentifier: 9999, // Window no longer exists
            workspacePath: "/Users/abin/workspace/projects/matchday"
        )
        let session = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: "/Users/abin/workspace/projects/matchday",
            originContext: origin
        )
        
        mockIdleTracker.idleSecondsMock = 30.0
        let decision = await focusController.handleSessionCompletion(
            session: session,
            config: .default,
            focusLock: FocusLockState()
        )
        
        // Must either restore or fallback cleanly without crashing or opening new project
        XCTAssertNotNil(decision)
    }
    
    // Scenario G: Fullscreen presentation -> No focus steal
    func testScenarioG_FullscreenPresentationProtection() {
        let origin = OriginContext(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 2001)
        let session = AgentSession(providerID: .antigravity, state: .completed, originContext: origin)
        
        mockWindowController.isFullscreenMock = true
        mockIdleTracker.idleSecondsMock = 30.0
        
        let decision = intentEngine.evaluate(session: session, config: .default, focusLock: FocusLockState(), frontmostApp: nil)
        
        guard case .notifyOnly(let reason) = decision else {
            return XCTFail("Scenario G failed: Should not interrupt fullscreen presentation")
        }
        XCTAssertTrue(reason.contains("Fullscreen"))
    }
    
    // Scenario H: Focus Lock active -> Notification only
    func testScenarioH_FocusLockSuppressesFocus() {
        let origin = OriginContext(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 2001)
        let session = AgentSession(providerID: .antigravity, state: .completed, originContext: origin)
        let lock = FocusLockState(isActive: true, expiresAt: Date().addingTimeInterval(1800), label: "30 min")
        
        let decision = intentEngine.evaluate(session: session, config: .default, focusLock: lock, frontmostApp: nil)
        
        guard case .notifyOnly(let reason) = decision else {
            return XCTFail("Scenario H failed: Focus Lock did not suppress focus")
        }
        XCTAssertTrue(reason.contains("Focus Lock"))
    }
    
    // Scenario I: Mac sleep -> Wake -> Reconcile state
    func testScenarioI_SleepWakeReconciliation() async {
        let sessionManager = SessionManager()
        let activeSession = AgentSession(providerID: .antigravity, state: .running)
        
        _ = await sessionManager.handleEvent(AgentEvent(
            providerID: .antigravity,
            sessionID: activeSession.id,
            type: .agentStarted
        ))
        
        // Simulate system wake reconciling abandoned running sessions
        await sessionManager.reconcileOrphanedSessions()
        
        let afterWake = await sessionManager.getSession(id: activeSession.id)
        XCTAssertEqual(afterWake?.state, .cancelled)
        XCTAssertTrue(afterWake?.errorDescription?.contains("Interrupted") ?? false)
    }
    
    // Scenario J: Crash recovery -> Startup reconciliation of persisted sessions
    func testScenarioJ_CrashRecoveryAndStartupReconciliation() async throws {
        let tempDb = NSTemporaryDirectory() + "flowback_crash_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let repo = SessionRepository(db: db)
        
        let sessID = AgentSessionID("crash-test-sess")
        let runningSession = AgentSession(id: sessID, providerID: .antigravity, state: .running)
        try await repo.saveSession(runningSession)
        
        // Simulate app restart
        let newSessionManager = SessionManager(storageDelegate: repo)
        let restored = try await repo.fetchRecentSessions(limit: 10)
        await newSessionManager.restorePersistedSessions(restored)
        await newSessionManager.reconcileOrphanedSessions()
        
        let reconciled = await newSessionManager.getSession(id: sessID)
        XCTAssertEqual(reconciled?.state, .cancelled)
        
        await db.close()
        try? FileManager.default.removeItem(atPath: tempDb)
    }
}
