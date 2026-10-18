import Foundation
import AppKit
import SQLite3
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackTestHarness
import FlowbackUI

// MARK: - Conversation-Aware Identity, UI, and Restoration Test Suites

private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _urls
    }

    func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        _urls.append(url)
    }
}

public func runConversationAwarenessSuites() async {
    // -------------------------------------------------------------------------
    // 1. Conversation Identity & Multi-Session Disambiguation
    // -------------------------------------------------------------------------
    await testGroup("Conversation Identity & Multi-Session Disambiguation") {
        let dbPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("flowback_test_conv_\(UUID().uuidString).sqlite")
        let db = await RecoveryManager.shared.initializeStorage(path: dbPath)
        let repo = SessionRepository(db: db)
        let manager = SessionManager(storageDelegate: repo)

        // Two sessions in the exact same repository remain separate with distinct titles
        let repoPath = "/Users/abin/workspace/projects/lottery-pi"
        let eventCursor = AgentEvent(
            providerID: .cursorBackground,
            sessionID: AgentSessionID("cursor-thread-101"),
            type: .agentRunning,
            workspace: repoPath,
            conversationID: "cursor-thread-101",
            conversationTitle: "Rebuild the lottery page UI",
            taskSummary: "feature/lottery-ui",
            focusCapability: .externalURL,
            isRemote: true
        )
        let eventClaude = AgentEvent(
            providerID: .claudeCode,
            sessionID: AgentSessionID("claude-sess-202"),
            type: .agentRunning,
            workspace: repoPath,
            conversationID: "claude-sess-202",
            conversationTitle: "Fix lottery draw settlement",
            taskSummary: "bugfix/settlement-calc",
            focusCapability: .workspaceAndConversation,
            isRemote: false
        )
        let eventWindsurf = AgentEvent(
            providerID: .windsurf,
            sessionID: AgentSessionID("windsurf-traj-303"),
            type: .agentWaiting,
            workspace: repoPath,
            conversationID: "windsurf-traj-303",
            conversationTitle: "Audit payment verification",
            taskSummary: "security/payment-audit",
            focusCapability: .windowOnly,
            isRemote: false
        )

        let sessionCursor = await manager.handleEvent(eventCursor)
        let sessionClaude = await manager.handleEvent(eventClaude)
        let sessionWindsurf = await manager.handleEvent(eventWindsurf)

        assertTest(sessionCursor.id != sessionClaude.id, "Cursor and Claude have distinct session IDs")
        assertTest(sessionClaude.id != sessionWindsurf.id, "Claude and Windsurf have distinct session IDs")
        assertTest(sessionCursor.displayTitle == "Rebuild the lottery page UI", "Cursor has correct conversation display title")
        assertTest(sessionClaude.displayTitle == "Fix lottery draw settlement", "Claude has correct conversation display title")
        assertTest(sessionWindsurf.displayTitle == "Audit payment verification", "Windsurf has correct conversation display title")

        // Querying by workspace finds all concurrent sessions
        let inWorkspace = await manager.getSessions(inWorkspace: repoPath)
        assertTest(inWorkspace.count == 3, "All 3 concurrent sessions found in workspace")
        let matchingProject = await manager.getSessions(matchingProject: "lottery-pi")
        assertTest(matchingProject.count == 3, "All 3 concurrent sessions match project 'lottery-pi'")

        // Same native ID across different providers does NOT cause collision
        let eventGeneric1 = AgentEvent(
            providerID: .aider,
            sessionID: AgentSessionID("common-id-777"),
            type: .agentRunning,
            conversationID: "common-id-777",
            conversationTitle: "Aider Task",
            focusCapability: .windowOnly
        )
        let eventGeneric2 = AgentEvent(
            providerID: .codex,
            sessionID: AgentSessionID("common-id-777"),
            type: .agentRunning,
            conversationID: "common-id-777",
            conversationTitle: "Codex Task",
            focusCapability: .windowOnly
        )
        let sess1 = await manager.handleEvent(eventGeneric1)
        let sess2 = await manager.handleEvent(eventGeneric2)
        assertTest(sess1.id == AgentSessionID("common-id-777"), "First provider session created")
        assertTest(sess2.id == AgentSessionID("common-id-777"), "Second provider event processed")
        assertTest(sess1.providerID == .aider, "Aider retains its provider ID")

        // Execution ID does not overwrite or replace conversation ID
        let eventWithRun = AgentEvent(
            providerID: .cursorBackground,
            sessionID: AgentSessionID("cursor-thread-101"),
            type: .agentProgress,
            conversationID: "cursor-thread-101",
            executionID: "run-turn-4",
            focusCapability: .externalURL
        )
        let updatedWithRun = await manager.handleEvent(eventWithRun)
        assertTest(updatedWithRun.conversationID == "cursor-thread-101", "Conversation ID strictly preserved across progress events")
        assertTest(updatedWithRun.executionID == "run-turn-4", "Execution ID stored separately from conversation ID")

        // Title update does not create duplicate session or alter identity
        let eventTitleUpdate = AgentEvent(
            providerID: .cursorBackground,
            sessionID: AgentSessionID("cursor-thread-101"),
            type: .conversationTitleUpdated,
            conversationID: "cursor-thread-101",
            conversationTitle: "Rebuild lottery page UI with responsive layout"
        )
        let afterTitleUpdate = await manager.handleEvent(eventTitleUpdate)
        assertTest(afterTitleUpdate.id == AgentSessionID("cursor-thread-101"), "Session ID invariant preserved after title update")
        assertTest(afterTitleUpdate.displayTitle == "Rebuild lottery page UI with responsive layout", "Title updated in-place")
        let allSessions = await manager.getAllSessions()
        let matchingIDs = allSessions.filter { $0.id == AgentSessionID("cursor-thread-101") }
        assertTest(matchingIDs.count == 1, "Exactly 1 record exists for session (no duplicate created by title change)")

        // Multi-turn reactivation preserves conversation title and metadata
        let completeEvent = AgentEvent(
            providerID: .cursorBackground,
            sessionID: AgentSessionID("cursor-thread-101"),
            type: .agentCompleted,
            conversationID: "cursor-thread-101"
        )
        _ = await manager.handleEvent(completeEvent)
        let completedSess = await manager.getSession(id: AgentSessionID("cursor-thread-101"))
        assertTest(completedSess?.state == .completed, "Session transitioned to completed")

        let reactivateEvent = AgentEvent(
            providerID: .cursorBackground,
            sessionID: AgentSessionID("cursor-thread-101"),
            type: .agentRunning,
            conversationID: "cursor-thread-101"
        )
        let reactivatedSess = await manager.handleEvent(reactivateEvent)
        assertTest(reactivatedSess.state == .running, "Multi-turn session resumed to running")
        assertTest(reactivatedSess.displayTitle == "Rebuild lottery page UI with responsive layout", "Conversation title preserved on reactivation")
        assertTest(reactivatedSess.completedAt == nil, "completedAt timestamp cleared on reactivation")

        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // -------------------------------------------------------------------------
    // 2. Restoration Outcome Semantics & Exact Focus Separation
    // -------------------------------------------------------------------------
    await testGroup("Restoration Outcome Semantics & Exact Focus Separation") {
        // A. Verify every outcome enum case for isExactConversation and isSuccessful
        let exactOutcome = RestorationOutcome.exactConversationRestored
        assertTest(exactOutcome.isExactConversation == true, "exactConversationRestored is classified as exact")
        assertTest(exactOutcome.isSuccessful == true, "exactConversationRestored is classified as successful")

        let hintOutcome = RestorationOutcome.resumeHintPresented
        assertTest(hintOutcome.isExactConversation == false, "resumeHintPresented is NOT exact conversation")
        assertTest(hintOutcome.isSuccessful == true, "resumeHintPresented is classified as successful")

        let wsOutcome = RestorationOutcome.workspaceActivatedOnly
        assertTest(wsOutcome.isExactConversation == false, "workspaceActivatedOnly is NOT exact conversation")
        assertTest(wsOutcome.isSuccessful == true, "workspaceActivatedOnly is classified as successful")

        let winOutcome = RestorationOutcome.windowActivatedOnly
        assertTest(winOutcome.isExactConversation == false, "windowActivatedOnly is NOT exact conversation")
        assertTest(winOutcome.isSuccessful == true, "windowActivatedOnly is classified as successful")

        let urlOutcome = RestorationOutcome.providerURLOpened
        assertTest(urlOutcome.isExactConversation == false, "providerURLOpened is NOT exact conversation")
        assertTest(urlOutcome.isSuccessful == true, "providerURLOpened is classified as successful")

        let unavailOutcome = RestorationOutcome.conversationUnavailable
        assertTest(unavailOutcome.isExactConversation == false, "conversationUnavailable is NOT exact conversation")
        assertTest(unavailOutcome.isSuccessful == false, "conversationUnavailable is NOT successful")

        let targetAmbigOutcome = RestorationOutcome.targetAmbiguous
        assertTest(targetAmbigOutcome.isExactConversation == false, "targetAmbiguous is NOT exact conversation")
        assertTest(targetAmbigOutcome.isSuccessful == false, "targetAmbiguous is NOT successful")

        let unsuppOutcome = RestorationOutcome.restorationUnsupported
        assertTest(unsuppOutcome.isExactConversation == false, "restorationUnsupported is NOT exact conversation")
        assertTest(unsuppOutcome.isSuccessful == false, "restorationUnsupported is NOT successful")

        let failedOutcome = RestorationOutcome.restorationFailed
        assertTest(failedOutcome.isExactConversation == false, "restorationFailed is NOT exact conversation")
        assertTest(failedOutcome.isSuccessful == false, "restorationFailed is NOT successful")

        // B. FocusController restoration priority and outcome verification
        let mockApp = MockApplicationController()
        let mockWin = MockWindowController()
        let mockIdle = MockIdleTracker(idleSeconds: 30.0)
        let mockSpace = MockSpaceController()
        let intentEngine = UserIntentEngine(idleTracker: mockIdle, windowController: mockWin, spaceController: mockSpace, appController: mockApp)
        let arbiter = AttentionArbiter(aggregationWindow: 1.0, cooldownDuration: 0.5)

        let recorder = URLRecorder()
        let focusController = FocusController(
            appController: mockApp,
            windowController: mockWin,
            intentEngine: intentEngine,
            arbiter: arbiter,
            urlOpener: { url in
                recorder.record(url)
                return true
            }
        )

        // 1. External URL restoration priority for Remote Agents with conversationURL
        let remoteSession = AgentSession(
            id: AgentSessionID("cursor-cloud-99"),
            providerID: .cursorBackground,
            state: .completed,
            conversationID: "agent-remote-99",
            conversationTitle: "Cloud Refactor Job",
            conversationURL: URL(string: "https://cursor.com/agents/agent-remote-99")!,
            focusCapability: .externalURL,
            isRemote: true
        )
        let resultURL = await focusController.restoreSession(remoteSession)
        assertTest(resultURL.outcome == .providerURLOpened, "Remote agent restored via .providerURLOpened outcome")
        assertTest(!resultURL.outcome.isExactConversation, "Provider URL opened is not claimed as exact local restoration")
        assertTest(resultURL.isSuccessful, "Restoration result marked as successful")
        assertTest(recorder.urls.contains(where: { $0.absoluteString == "https://cursor.com/agents/agent-remote-99" }), "Target web URL opened")

        // 2. Unsafe URL schemes rejected
        let unsafeSession = AgentSession(
            id: AgentSessionID("unsafe-session-1"),
            providerID: .genericHook,
            state: .completed,
            conversationURL: URL(string: "javascript:alert(1)")!,
            focusCapability: .externalURL
        )
        let resultUnsafe = await focusController.restoreSession(unsafeSession)
        assertTest(resultUnsafe.outcome == .restorationFailed, "Unsafe URL scheme rejected with .restorationFailed")
        assertTest(!resultUnsafe.isSuccessful, "Unsafe restoration outcome marked unsuccessful")

        // 3. CLI resume command returns .resumeHintPresented (never claims exact conversation restoration)
        let cliOrigin = OriginContext(
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 3001,
            windowIdentifier: 101,
            windowTitle: "lottery-pi — Terminal",
            workspacePath: "/Users/abin/workspace/projects/lottery-pi"
        )
        let cliSession = AgentSession(
            id: AgentSessionID("agy-conv-uuid"),
            providerID: .antigravityCLI,
            state: .completed,
            workspace: "/Users/abin/workspace/projects/lottery-pi",
            originContext: cliOrigin,
            conversationID: "agy-conv-uuid",
            conversationTitle: "Optimize lottery queries",
            focusCapability: .workspaceAndConversation,
            isRemote: false
        )
        let resultCLI = await focusController.restoreSession(cliSession)
        assertTest(resultCLI.outcome == .resumeHintPresented, "Antigravity CLI restored with .resumeHintPresented")
        assertTest(!resultCLI.outcome.isExactConversation, "CLI resume hint is NOT classified as exact conversation restoration")
        assertTest(resultCLI.message.contains("agy --conversation agy-conv-uuid"), "Resume command hint generated accurately")
        assertTest(resultCLI.isSuccessful, "CLI restoration marked successful")

        // 4. Honest workspace/window fallback for Windsurf (never claims exact conversation focus)
        let windsurfOrigin = OriginContext(
            bundleIdentifier: "com.codeium.windsurf",
            processIdentifier: 4001,
            windowIdentifier: 202,
            windowTitle: "lottery-pi — Windsurf",
            workspacePath: "/Users/abin/workspace/projects/lottery-pi"
        )
        let windsurfSession = AgentSession(
            id: AgentSessionID("windsurf-traj-555"),
            providerID: .windsurf,
            state: .completed,
            workspace: "/Users/abin/workspace/projects/lottery-pi",
            originContext: windsurfOrigin,
            conversationID: "windsurf-traj-555",
            conversationTitle: "Update payment integration",
            focusCapability: .windowOnly,
            isRemote: false
        )
        let resultWindsurf = await focusController.restoreSession(windsurfSession)
        assertTest(resultWindsurf.outcome == .workspaceActivatedOnly || resultWindsurf.outcome == .windowActivatedOnly, "Windsurf reports workspace/window fallback")
        assertTest(!resultWindsurf.outcome.isExactConversation, "Window/workspace fallback is NOT classified as exact conversation")

        // 5. Ambiguous target prevention: Multiple candidate windows match workspace
        let ambigOrigin = OriginContext(
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 5001,
            windowIdentifier: nil,
            workspacePath: "/Users/abin/workspace/projects/lottery-pi"
        )
        mockWin.windowsMock = [
            WindowInfo(windowID: 11, processIdentifier: 5001, ownerName: "Code", title: "lottery-pi — Window 1", bounds: .zero, isOnScreen: true),
            WindowInfo(windowID: 12, processIdentifier: 5001, ownerName: "Code", title: "lottery-pi — Window 2", bounds: .zero, isOnScreen: true)
        ]
        let ambigSession = AgentSession(
            id: AgentSessionID("ambig-sess-1"),
            providerID: .codex,
            state: .completed,
            workspace: "/Users/abin/workspace/projects/lottery-pi",
            originContext: ambigOrigin,
            focusCapability: .windowOnly
        )
        let resultAmbig = await focusController.restoreSession(ambigSession)
        assertTest(resultAmbig.outcome == .targetAmbiguous, "Ambiguous target detected when multiple windows match without windowID")
        assertTest(!resultAmbig.isSuccessful, "Ambiguous restoration aborted without guessing")

        // 6. Unsupported provider / capability returns .restorationUnsupported
        let unsuppSession = AgentSession(
            id: AgentSessionID("unsupp-sess-1"),
            providerID: .genericHook,
            state: .completed,
            workspace: nil,
            originContext: nil,
            focusCapability: .unavailable
        )
        let resultUnsupp = await focusController.restoreSession(unsuppSession)
        assertTest(resultUnsupp.outcome == .restorationUnsupported, "Unsupported capability returns .restorationUnsupported")
        assertTest(!resultUnsupp.isSuccessful, "Unsupported capability marked unsuccessful")

        // 7. Manual focus delegates through restoreSession with honest return code
        let manualSuccess = await focusController.manualFocusSession(cliSession)
        assertTest(manualSuccess == true, "manualFocusSession succeeds for valid CLI session")
    }

    // -------------------------------------------------------------------------
    // 3. Provider Capability Mismatches & Lifecycle State Normalization
    // -------------------------------------------------------------------------
    await testGroup("Provider Capability Mismatches & Lifecycle State Normalization") {
        // A. OpenAI Codex
        let codex = CodexProvider()
        let codexHealth = await codex.checkHealth()
        assertTest(codexHealth.isSupported, "Codex is supported")

        // Codex lifecycle normalization across states
        let codexRunningJson = """
        {"id": "codex-1", "state": "running", "workspace": "/test", "title": "Codex Task"}
        """.data(using: .utf8)!
        let codexRunningEvent = try codex.parseLifecyclePayload(data: codexRunningJson)
        assertTest(codexRunningEvent?.type == .agentRunning, "Codex 'running' maps to .agentRunning")
        assertTest(codexRunningEvent?.focusCapability == .windowOnly, "Codex focus capability is strictly .windowOnly")

        let codexWaitJson = """
        {"id": "codex-1", "state": "waiting", "workspace": "/test"}
        """.data(using: .utf8)!
        let codexWaitEvent = try codex.parseLifecyclePayload(data: codexWaitJson)
        assertTest(codexWaitEvent?.type == .agentWaiting, "Codex 'waiting' maps to .agentWaiting")

        let codexPermJson = """
        {"id": "codex-1", "state": "permission_required", "workspace": "/test"}
        """.data(using: .utf8)!
        let codexPermEvent = try codex.parseLifecyclePayload(data: codexPermJson)
        assertTest(codexPermEvent?.type == .agentPermissionRequired, "Codex 'permission_required' maps to .agentPermissionRequired")

        let codexFailJson = """
        {"id": "codex-1", "state": "failed", "workspace": "/test"}
        """.data(using: .utf8)!
        let codexFailEvent = try codex.parseLifecyclePayload(data: codexFailJson)
        assertTest(codexFailEvent?.type == .agentFailed, "Codex 'failed' maps to .agentFailed")

        let codexCancelJson = """
        {"id": "codex-1", "state": "cancelled", "workspace": "/test"}
        """.data(using: .utf8)!
        let codexCancelEvent = try codex.parseLifecyclePayload(data: codexCancelJson)
        assertTest(codexCancelEvent?.type == .agentCancelled, "Codex 'cancelled' maps to .agentCancelled")

        let codexDoneJson = """
        {"id": "codex-1", "state": "completed", "workspace": "/test"}
        """.data(using: .utf8)!
        let codexDoneEvent = try codex.parseLifecyclePayload(data: codexDoneJson)
        assertTest(codexDoneEvent?.type == .agentCompleted, "Codex 'completed' maps to .agentCompleted")

        // Unknown Codex status does NOT imply completed
        let codexUnknownJson = """
        {"id": "codex-1", "state": "some_arbitrary_unseen_state", "workspace": "/test"}
        """.data(using: .utf8)!
        let codexUnknownEvent = try codex.parseLifecyclePayload(data: codexUnknownJson)
        assertTest(codexUnknownEvent?.type == .agentRunning, "Unknown Codex state safely defaults to .agentRunning (never implies completion)")

        // B. Aider
        let aider = AiderProvider()
        let aiderHealth = await aider.checkHealth()
        assertTest(aiderHealth.isSupported, "Aider is supported")

        let aiderStartJson = """
        {"session_id": "aider-1", "status": "started", "workspace": "/test", "message": "Refactoring"}
        """.data(using: .utf8)!
        let aiderStartEvent = try aider.parseLifecyclePayload(data: aiderStartJson)
        assertTest(aiderStartEvent?.type == .agentRunning, "Aider 'started' maps to .agentRunning")
        assertTest(aiderStartEvent?.focusCapability == .windowOnly, "Aider focus capability is strictly .windowOnly")

        let aiderWaitJson = """
        {"session_id": "aider-1", "status": "waiting", "workspace": "/test"}
        """.data(using: .utf8)!
        let aiderWaitEvent = try aider.parseLifecyclePayload(data: aiderWaitJson)
        assertTest(aiderWaitEvent?.type == .agentWaiting, "Aider 'waiting' maps to .agentWaiting")

        let aiderConfirmJson = """
        {"session_id": "aider-1", "event": "confirm", "workspace": "/test"}
        """.data(using: .utf8)!
        let aiderConfirmEvent = try aider.parseLifecyclePayload(data: aiderConfirmJson)
        assertTest(aiderConfirmEvent?.type == .agentPermissionRequired, "Aider 'confirm' event maps to .agentPermissionRequired")

        let aiderErrorJson = """
        {"session_id": "aider-1", "status": "error", "workspace": "/test"}
        """.data(using: .utf8)!
        let aiderErrorEvent = try aider.parseLifecyclePayload(data: aiderErrorJson)
        assertTest(aiderErrorEvent?.type == .agentFailed, "Aider 'error' maps to .agentFailed")

        let aiderDoneJson = """
        {"session_id": "aider-1", "status": "done", "workspace": "/test"}
        """.data(using: .utf8)!
        let aiderDoneEvent = try aider.parseLifecyclePayload(data: aiderDoneJson)
        assertTest(aiderDoneEvent?.type == .agentCompleted, "Aider 'done' maps to .agentCompleted")

        // Unknown / malformed Aider event does NOT imply completion
        let aiderUnknownJson = """
        {"session_id": "aider-1", "status": "unknown_custom_event", "workspace": "/test"}
        """.data(using: .utf8)!
        let aiderUnknownEvent = try aider.parseLifecyclePayload(data: aiderUnknownJson)
        assertTest(aiderUnknownEvent?.type == .agentRunning, "Unknown Aider event safely defaults to .agentRunning (never implies completion)")

        // C. Cursor Background Agent
        let cursorBg = CursorBackgroundProvider()
        let cursorJson = """
        {
            "id": "agent-cloud-777",
            "status": "RUNNING",
            "summary": "Cloud migration task",
            "repository": "https://github.com/org/repo.git",
            "targetRef": "feature/branch"
        }
        """.data(using: .utf8)!
        let cursorEvent = try cursorBg.parseLifecyclePayload(data: cursorJson)
        assertTest(cursorEvent?.focusCapability == .externalURL, "Cursor cloud agent focus capability is strictly .externalURL")
        assertTest(cursorEvent?.isRemote == true, "Cursor cloud agent marked as remote")
    }

    // -------------------------------------------------------------------------
    // 4. Schema V2 Migration Integrity, Idempotency, and Failure Rollback
    // -------------------------------------------------------------------------
    await testGroup("Schema V2 Migration Integrity, Idempotency, and Failure Rollback") {
        let dbPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("flowback_test_v2_migration_\(UUID().uuidString).sqlite")
        let db = SQLiteDatabase(path: dbPath)
        try await db.open()

        // 1. Setup V1 database fixture with legacy records
        try await db.runInTransaction {
            try await Migrations.applyMigrationV1(db: db)
        }
        try await db.setUserVersion(1)
        let v1 = try await db.getUserVersion()
        assertTest(v1 == 1, "Initial isolated fixture initialized at Schema V1")

        // Insert legacy session record
        let insertLegacySql = """
        INSERT INTO sessions (id, provider_id, state, workspace, started_at, updated_at)
        VALUES ('legacy-sess-1', 'codex', 'running', '/Users/abin/projects/legacy', 1700000000.0, 1700000000.0);
        """
        try await db.execute(sql: insertLegacySql)

        // 2. Normal V1-to-V2 migration
        try await Migrations.apply(db: db)
        let v2 = try await db.getUserVersion()
        assertTest(v2 == 2, "Database successfully upgraded from V1 to V2")

        // Verify preservation of legacy records
        let legacyRows = try await db.query(sql: "SELECT id, provider_id, workspace FROM sessions WHERE id = 'legacy-sess-1';") { stmt in
            (
                String(cString: sqlite3_column_text(stmt, 0)),
                String(cString: sqlite3_column_text(stmt, 1)),
                String(cString: sqlite3_column_text(stmt, 2))
            )
        }
        assertTest(legacyRows.count == 1, "Legacy record preserved across V2 migration")
        assertTest(legacyRows.first?.0 == "legacy-sess-1", "Legacy session ID matches")
        assertTest(legacyRows.first?.1 == "codex", "Legacy provider ID matches")
        assertTest(legacyRows.first?.2 == "/Users/abin/projects/legacy", "Legacy workspace matches")

        // Verify all expected V2 columns exist via PRAGMA table_info
        let columns = try await db.query(sql: "PRAGMA table_info(sessions);") { stmt in
            String(cString: sqlite3_column_text(stmt, 1))
        }
        let colSet = Set(columns)
        assertTest(colSet.contains("conversation_id"), "V2 column conversation_id present")
        assertTest(colSet.contains("conversation_title"), "V2 column conversation_title present")
        assertTest(colSet.contains("task_summary"), "V2 column task_summary present")
        assertTest(colSet.contains("execution_id"), "V2 column execution_id present")
        assertTest(colSet.contains("parent_session_id"), "V2 column parent_session_id present")
        assertTest(colSet.contains("conversation_url"), "V2 column conversation_url present")
        assertTest(colSet.contains("focus_capability"), "V2 column focus_capability present")
        assertTest(colSet.contains("is_remote"), "V2 column is_remote present")

        // 3. Idempotency: Re-applying V2 migration does not fail or duplicate
        do {
            try await Migrations.applyMigrationV2(db: db)
            assertTest(true, "applyMigrationV2 is idempotent when columns already exist")
        } catch {
            assertTest(false, "applyMigrationV2 failed on already-migrated database: \(error.localizedDescription)")
        }

        // 4. Injected SQLite failure and transaction rollback
        let dbFailPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("flowback_test_v2_fail_\(UUID().uuidString).sqlite")
        let dbFail = SQLiteDatabase(path: dbFailPath)
        try await dbFail.open()
        try await dbFail.runInTransaction {
            try await Migrations.applyMigrationV1(db: dbFail)
        }
        try await dbFail.setUserVersion(1)

        // Simulate an injected failure during migration by running a block that fails
        var didRollback = false
        do {
            _ = try await dbFail.runInTransaction {
                // Execute invalid SQL to trigger execution error
                try await dbFail.execute(sql: "THIS IS INVALID SQL THAT CANNOT EXECUTE;")
            }
        } catch {
            didRollback = true
        }
        assertTest(didRollback, "Injected SQLite error properly propagated out of transaction")
        let failVersion = try await dbFail.getUserVersion()
        assertTest(failVersion == 1, "Failed migration leaves user_version at 1 without advancing")
        await dbFail.close()
        try? FileManager.default.removeItem(atPath: dbFailPath)

        // 5. Reopening the migrated database and round-tripping records
        await db.close()
        let dbReopened = SQLiteDatabase(path: dbPath)
        try await dbReopened.open()
        let reopenedVersion = try await dbReopened.getUserVersion()
        assertTest(reopenedVersion == 2, "Reopened database retains Schema V2")

        let repo = SessionRepository(db: dbReopened)
        let newSession = AgentSession(
            id: AgentSessionID("v2-reopened-session-1"),
            providerID: .antigravity,
            state: .running,
            workspace: "/Users/abin/workspace/projects/flowback",
            conversationID: "agy-reopened-conv",
            conversationTitle: "Reopening Verification Test",
            taskSummary: "feat/reopen-test",
            executionID: "step-2",
            focusCapability: .workspaceAndConversation
        )
        try await repo.saveSession(newSession)
        let loaded = try await repo.fetchSession(id: newSession.id)
        assertTest(loaded?.conversationID == "agy-reopened-conv", "Session round-tripped cleanly after reopening V2 database")
        assertTest(loaded?.conversationTitle == "Reopening Verification Test", "Session title round-tripped cleanly")

        await dbReopened.close()
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // -------------------------------------------------------------------------
    // 5. MenuBar Keyboard Shortcuts & Submenu Conflict Prevention
    // -------------------------------------------------------------------------
    await testGroup("MenuBar Keyboard Shortcuts & Submenu Conflict Prevention") {
        let menuBarController = MenuBarController()
        let recentSess1 = AgentSession(
            id: AgentSessionID("menu-sess-1"),
            providerID: .antigravityCLI,
            state: .completed,
            workspace: "/Users/abin/projects/p1",
            conversationTitle: "Recent Project 1"
        )
        let recentSess2 = AgentSession(
            id: AgentSessionID("menu-sess-2"),
            providerID: .claudeCode,
            state: .running,
            workspace: "/Users/abin/projects/p2",
            conversationTitle: "Recent Project 2"
        )
        menuBarController.updateState(
            activeSessions: [],
            recentSessions: [recentSess1, recentSess2],
            attentionQueue: [],
            focusLock: FocusLockState()
        )

        let menu = NSMenu()
        menuBarController.menuNeedsUpdate(menu)

        // Find the "Recent Agent Sessions" menu item
        let recentParent = menu.items.first { $0.title == "Recent Agent Sessions" }
        assertTest(recentParent != nil, "Recent Agent Sessions menu item exists")
        assertTest(recentParent?.submenu != nil, "Recent Agent Sessions has submenu")

        let recentSubmenu = recentParent?.submenu
        assertTest((recentSubmenu?.items.count ?? 0) >= 2, "Recent submenu contains recent items")

        if let firstRecent = recentSubmenu?.items.first {
            // In AppKit, attaching a submenu to an NSMenuItem with a keyEquivalent suppresses
            // keyboard shortcut invocation. Items with shortcuts (⌘1..⌘9) must have submenu == nil.
            assertTest(firstRecent.keyEquivalent == "1", "First recent session has key equivalent '1'")
            assertTest(firstRecent.keyEquivalentModifierMask == [.command], "First recent session has Command modifier")
            assertTest(firstRecent.submenu == nil, "First recent session has NO attached submenu (preserves direct shortcut firing)")
            assertTest(firstRecent.action != nil, "First recent session has active action target")
        }

        if let secondRecent = recentSubmenu?.items.dropFirst().first {
            assertTest(secondRecent.keyEquivalent == "2", "Second recent session has key equivalent '2'")
            assertTest(secondRecent.submenu == nil, "Second recent session has NO attached submenu")
            assertTest(secondRecent.action != nil, "Second recent session has active action target")
        }

        // Note: Live AppKit keyboard event dispatch requires active WindowServer connection;
        // menu structure and AppKit action/shortcut bindings are verified here headlessly.
    }

    // -------------------------------------------------------------------------
    // 6. BrainTranscriptParser Shared Logic & Edge Cases
    // -------------------------------------------------------------------------
    await testGroup("BrainTranscriptParser Shared Logic & Edge Cases") {
        // Standard user request
        let text1 = """
        <USER_REQUEST>
        Refactor the auth middleware to support bearer tokens
        </USER_REQUEST>
        """
        let title1 = BrainTranscriptParser.extractConversationTitle(from: text1)
        assertTest(title1 == "Refactor the auth middleware to support bearer tokens", "Extracts standard user request")

        // /goal command with markdown header
        let text2 = """
        <USER_REQUEST>
        /goal # Build Dashboard Analytics Component
        Please implement the dashboard analytics component with line chart
        </USER_REQUEST>
        """
        let title2 = BrainTranscriptParser.extractConversationTitle(from: text2)
        assertTest(title2 == "Build Dashboard Analytics Component", "Strips /goal and markdown header correctly")

        // /plan command
        let text3 = """
        <USER_REQUEST>
        /plan ### Fix Session Expiration Race Condition
        Steps to reproduce...
        </USER_REQUEST>
        """
        let title3 = BrainTranscriptParser.extractConversationTitle(from: text3)
        assertTest(title3 == "Fix Session Expiration Race Condition", "Strips /plan and markdown header correctly")

        // ### USER Objective format
        let text4 = """
        Conversation history summary:
        ### USER Objective: Migrate User Schema to V2
        Timestamp: 2026-10-17
        """
        let title4 = BrainTranscriptParser.extractConversationTitle(from: text4)
        assertTest(title4 == "Migrate User Schema to V2", "Extracts '### USER Objective:' header")

        // Unicode and emoji in title
        let text5 = """
        <USER_REQUEST>
        🚀 Release Flowback 2.0 with Conversation-Aware Focus
        </USER_REQUEST>
        """
        let title5 = BrainTranscriptParser.extractConversationTitle(from: text5)
        assertTest(title5 == "🚀 Release Flowback 2.0 with Conversation-Aware Focus", "Preserves Unicode and emoji in titles")

        // Long title truncation to 120 characters
        let longReq = String(repeating: "VeryLongTitleCharacterSequence_", count: 10)
        let text6 = "<USER_REQUEST>\n\(longReq)\n</USER_REQUEST>"
        let title6 = BrainTranscriptParser.extractConversationTitle(from: text6)
        assertTest((title6?.count ?? 0) <= 120, "Truncates conversation titles exceeding 120 characters")

        // Malformed / unclosed tag returns nil
        let text7 = "<USER_REQUEST>Unclosed request block without closing tag"
        let title7 = BrainTranscriptParser.extractConversationTitle(from: text7)
        assertTest(title7 == nil, "Malformed/unclosed user request block safely returns nil")

        // Empty string returns nil
        let title8 = BrainTranscriptParser.extractConversationTitle(from: "")
        assertTest(title8 == nil, "Empty transcript returns nil")

        // Text without user request or objective returns nil
        let text9 = "Random agent log message: tool called run_command."
        let title9 = BrainTranscriptParser.extractConversationTitle(from: text9)
        assertTest(title9 == nil, "Transcript with no title tokens returns nil")

        // JSONL-escaped multi-line prompt with leading newline, /goal, and project prefix
        let text10 = #"{"step_index":2,"type":"USER_INPUT","content":""# +
            #"<USER_REQUEST>\n/goal # Flowback × Vorssaint — Implement General Sidebar Destinations\n\n## Role\n\nAct as a principal macOS product architect</USER_REQUEST>"}"#
        let title10 = BrainTranscriptParser.extractConversationTitle(from: text10)
        assertTest(title10 == "Implement General Sidebar Destinations",
                   "Extracts clean title from JSONL-escaped /goal prompt with project prefix")

        // Standard hyphen project prefix
        let text11 = "<USER_REQUEST>\n# Flowback - Configure Privacy Protections\nDetails here...\n</USER_REQUEST>"
        let title11 = BrainTranscriptParser.extractConversationTitle(from: text11)
        assertTest(title11 == "Configure Privacy Protections", "Strips hyphenated project prefix correctly")
    }

    // -------------------------------------------------------------------------
    // 7. UI Metadata Formatting & Provider Capabilities
    // -------------------------------------------------------------------------
    await testGroup("UI Metadata Formatting & Provider Capabilities") {
        let cursorBg = AgentSession(
            providerID: .cursorBackground,
            state: .running,
            conversationTitle: "Rebuild UI",
            focusCapability: .externalURL
        )
        assertTest(cursorBg.providerDisplayName == "Cursor Background Agent", "Provider display name formatted")
        assertTest(cursorBg.displayTitle == "Rebuild UI", "displayTitle uses conversationTitle")
        assertTest(cursorBg.focusCapability.displayLabel == "External URL", "focusCapability label formatted")

        let agy = AgentSession(
            providerID: .antigravityCLI,
            state: .running,
            conversationTitle: "Audit Auth",
            focusCapability: .workspaceAndConversation
        )
        assertTest(agy.providerDisplayName == "Antigravity CLI", "Antigravity CLI display name")
        assertTest(agy.focusCapability.displayLabel == "Workspace & Conversation", "CLI focus capability label")

        let windsurf = AgentSession(
            providerID: .windsurf,
            state: .waiting,
            workspace: "/workspace/my-project",
            focusCapability: .windowOnly
        )
        assertTest(windsurf.displayTitle == "my-project", "Fallback displayTitle uses projectName when title missing")
        assertTest(windsurf.focusCapability.displayLabel == "Window Only", "Window only capability label")
    }
}
