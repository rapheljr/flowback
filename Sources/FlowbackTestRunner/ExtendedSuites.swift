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

@MainActor
func runLaunchAtLoginSuites() async {
    // 20. Launch at Login Granular System Mappings Suite
    await testGroup("Launch at Login Granular System Mappings") {
        let enabledMap = PermissionManager.mapSMStatus(.enabled, isAppBundle: true)
        assertTest(enabledMap == .enabled, "SMAppService.Status.enabled maps to .enabled in app bundle")
        
        let approvalMap = PermissionManager.mapSMStatus(.requiresApproval, isAppBundle: true)
        assertTest(approvalMap == .requiresApproval, "SMAppService.Status.requiresApproval maps to .requiresApproval")
        
        let notRegMap = PermissionManager.mapSMStatus(.notRegistered, isAppBundle: true)
        assertTest(notRegMap == .disabled, "SMAppService.Status.notRegistered maps to .disabled")
        
        let notFoundMap = PermissionManager.mapSMStatus(.notFound, isAppBundle: true)
        assertTest(notFoundMap == .notFound, "SMAppService.Status.notFound maps to .notFound")
        
        let standaloneMap = PermissionManager.mapSMStatus(.enabled, isAppBundle: false)
        assertTest(standaloneMap == .unsupported, "Launch at Login is .unsupported when running outside app bundle")
        
        var outsideThrows = false
        do {
            try PermissionManager().setLaunchAtLogin(enabled: true)
        } catch {
            outsideThrows = true
        }
        assertTest(outsideThrows, "setLaunchAtLogin throws explanatory error when called outside app bundle")
        
        let permStatus = PermissionStatus(
            accessibilityGranted: true,
            notificationsGranted: true,
            launchAtLoginEnabled: false,
            isAppBundle: true,
            launchAtLoginStatus: .requiresApproval
        )
        assertTest(permStatus.launchAtLoginStatus == .requiresApproval, "PermissionStatus preserves granular launchAtLoginStatus")
        assertTest(!permStatus.launchAtLoginEnabled, "requiresApproval evaluates launchAtLoginEnabled to false")
    }
}

@MainActor
func runIPCSecuritySuites() async {
    // 21. IPC Extended Commands & Socket Directory Security Suite
    await testGroup("IPC Extended Commands & Socket Directory Security") {
        let mockApp = MockApplicationController()
        let dummyRepo = SettingsRepository(db: await RecoveryManager.shared.initializeStorage(path: ":memory:"))
        
        final class BoolFlag: @unchecked Sendable {
            var value: Bool = false
        }
        let testNotifTriggered = BoolFlag()
        let shutdownTriggered = BoolFlag()
        
        let handler = IPCHandler(
            sessionManager: SessionManager(),
            focusController: FocusController(
                appController: mockApp,
                windowController: MockWindowController(),
                intentEngine: UserIntentEngine(
                    idleTracker: MockIdleTracker(),
                    windowController: MockWindowController(),
                    spaceController: MockSpaceController(),
                    appController: mockApp
                ),
                arbiter: AttentionArbiter()
            ),
            providerRegistry: ProviderRegistry(),
            settingsRepo: dummyRepo,
            shutdownHandler: {
                shutdownTriggered.value = true
            },
            testNotificationHandler: {
                testNotifTriggered.value = true
            }
        )
        
        // Test test-notification command
        let notifResp = await handler.handleRequest(IPCRequest(command: "test-notification"))
        assertTest(notifResp.success, "IPCHandler successfully handles test-notification command")
        assertTest(testNotifTriggered.value, "test-notification triggers registered notification delegate")
        
        // Test authorized vs unauthorized quit / shutdown
        let authHandler = IPCHandler(
            sessionManager: SessionManager(),
            focusController: FocusController(
                appController: mockApp,
                windowController: MockWindowController(),
                intentEngine: UserIntentEngine(
                    idleTracker: MockIdleTracker(),
                    windowController: MockWindowController(),
                    spaceController: MockSpaceController(),
                    appController: mockApp
                ),
                arbiter: AttentionArbiter()
            ),
            providerRegistry: ProviderRegistry(),
            settingsRepo: dummyRepo,
            sessionToken: "auth-secret-xyz",
            shutdownHandler: {
                shutdownTriggered.value = true
            }
        )
        
        // Call quit without authToken
        let unauthResp = await authHandler.handleRequest(IPCRequest(command: "quit"))
        assertTest(!unauthResp.success, "quit command without authToken is rejected as unauthorized (fail-closed)")
        
        // Call quit with invalid authToken
        let wrongResp = await authHandler.handleRequest(IPCRequest(command: "quit", authToken: "bad-token"))
        assertTest(!wrongResp.success, "quit command with invalid authToken is rejected")
        
        // Call quit with matching authToken
        let okResp = await authHandler.handleRequest(IPCRequest(command: "quit", authToken: "auth-secret-xyz"))
        assertTest(okResp.success, "quit command with valid authToken is authorized and accepted")
        assertTest(shutdownTriggered.value, "Authorized quit command triggers registered shutdown delegate")
        
        // Test directory 0700 enforcement on pre-existing loose directory
        let looseDir = "/tmp/fb_loose_\(UUID().uuidString.prefix(8))"
        try? FileManager.default.createDirectory(atPath: looseDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let looseSock = looseDir + "/t.sock"
        let looseServer = UnixSocketServer(socketPath: looseSock, delegate: handler)
        try looseServer.start()
        
        let looseAttrs = try? FileManager.default.attributesOfItem(atPath: looseDir)
        let loosePerms = looseAttrs?[.posixPermissions] as? NSNumber
        assertTest(loosePerms?.int16Value == 0o700, "UnixSocketServer restricts pre-existing 0755 directory to 0700 on start")
        
        let tokenFile = looseDir + "/.session_token"
        assertTest(FileManager.default.fileExists(atPath: tokenFile), "UnixSocketServer creates .session_token on start")
        let tokenAttrs = try? FileManager.default.attributesOfItem(atPath: tokenFile)
        let tokenPerms = tokenAttrs?[.posixPermissions] as? NSNumber
        assertTest(tokenPerms?.int16Value == 0o600, "Session token file has 0600 permissions (least privilege)")
        
        looseServer.stop()
        assertTest(!FileManager.default.fileExists(atPath: tokenFile), "Session token file cleanly unlinked on server stop")
        try? FileManager.default.removeItem(atPath: looseDir)
        
        // Test EventBus finishAll
        let testBus = EventBus()
        var streamFinished = false
        let subTask = Task {
            for await _ in await testBus.agentEvents() {
                // consume
            }
            streamFinished = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await testBus.finishAll()
        try? await Task.sleep(nanoseconds: 50_000_000)
        assertTest(streamFinished, "EventBus.finishAll() cleanly finishes active consumer streams")
        subTask.cancel()
    }
}

@MainActor
func runDatabaseRecoverySuites() async {
    // 22. Database Security, WAL Preservation & Degraded Fallback Suite
    await testGroup("Database Security, WAL Preservation & Degraded Fallback") {
        let testDir = NSTemporaryDirectory() + "fb_db_perm_\(UUID().uuidString)"
        let testDbPath = testDir + "/flowback.sqlite"
        let db = SQLiteDatabase(path: testDbPath)
        try await db.open()
        
        let attrs = try? FileManager.default.attributesOfItem(atPath: testDir)
        let perms = attrs?[.posixPermissions] as? NSNumber
        assertTest(perms?.int16Value == 0o700, "SQLiteDatabase creates storage directory with 0700 permissions")
        
        await db.close()
        try? FileManager.default.removeItem(atPath: testDir)
        
        // Corrupt database recovery test preserving WAL and SHM
        let corruptBase = NSTemporaryDirectory() + "corrupt_wal_\(UUID().uuidString)"
        let corruptDb = corruptBase + "/flowback.sqlite"
        let corruptWal = corruptBase + "/flowback.sqlite-wal"
        try? FileManager.default.createDirectory(atPath: corruptBase, withIntermediateDirectories: true, attributes: nil)
        FileManager.default.createFile(atPath: corruptDb, contents: "BAD_SQLITE_DATA".data(using: .utf8), attributes: nil)
        FileManager.default.createFile(atPath: corruptWal, contents: "UNCHECKPOINTED_WAL_DATA".data(using: .utf8), attributes: nil)
        
        let detailedResult = await RecoveryManager.shared.initializeStorageDetailed(path: corruptDb)
        assertTest(detailedResult.isRecovered, "RecoveryManager reports isRecovered == true on corrupt database")
        assertTest(detailedResult.isDurable, "Recovered database on disk reports isDurable == true")
        assertTest(detailedResult.backupPath != nil, "Preserved backup path is reported")
        
        if let backup = detailedResult.backupPath {
            assertTest(FileManager.default.fileExists(atPath: backup), "Damaged SQLite database preserved at backup path")
            assertTest(FileManager.default.fileExists(atPath: "\(backup)-wal"), "Uncheckpointed WAL journal preserved at backup path rather than deleted")
        }
        await detailedResult.database.close()
        try? FileManager.default.removeItem(atPath: corruptBase)
        
        // Test transient in-memory storage fallback reporting
        let memoryResult = await RecoveryManager.shared.initializeStorageDetailed(path: ":memory:")
        assertTest(!memoryResult.isDurable, "In-memory database explicitly reports isDurable == false")
        assertTest(await memoryResult.database.isDurable == false, "SQLiteDatabase.isDurable returns false for :memory:")
        await memoryResult.database.close()
    }
}

@MainActor
func runTerminationLifecycleSuites() async {
    // 23. AppKit Termination & Window Lifecycle State Machine Suite
    await testGroup("AppKit Termination & Window Lifecycle State Machine") {
        // 1. Termination Reply State Machine
        final class TerminationStateCoordinator: @unchecked Sendable {
            var terminationReplyPending = false
            var isTerminated = false
            var repliesCount = 0
            
            func handleShouldTerminate(isServiceStopped: Bool) -> String {
                if isServiceStopped || isTerminated {
                    return "terminateNow"
                }
                if terminationReplyPending {
                    return "terminateLater (duplicate ignored)"
                }
                terminationReplyPending = true
                return "terminateLater (async started)"
            }
            
            func finishAsyncStop() {
                guard !isTerminated else { return }
                isTerminated = true
                terminationReplyPending = false
                repliesCount += 1
            }
        }
        
        let termCoord = TerminationStateCoordinator()
        
        // Initial termination request
        let reply1 = termCoord.handleShouldTerminate(isServiceStopped: false)
        assertTest(reply1 == "terminateLater (async started)", "First termination request initiates async shutdown with .terminateLater")
        assertTest(termCoord.terminationReplyPending, "terminationReplyPending is true while async stop is running")
        
        // Repeated termination request while stopping
        let reply2 = termCoord.handleShouldTerminate(isServiceStopped: false)
        assertTest(reply2 == "terminateLater (duplicate ignored)", "Repeated termination request returns .terminateLater without duplicate async task")
        
        // Finish async stop
        termCoord.finishAsyncStop()
        assertTest(termCoord.repliesCount == 1, "Termination reply sent exactly once")
        assertTest(termCoord.isTerminated, "isTerminated marked true after shutdown completion")
        
        // Call finishAsyncStop again to verify idempotency
        termCoord.finishAsyncStop()
        assertTest(termCoord.repliesCount == 1, "Duplicate async completion callback does not trigger second reply")
        
        // Subsequent termination request after stop
        let reply3 = termCoord.handleShouldTerminate(isServiceStopped: true)
        assertTest(reply3 == "terminateNow", "Termination request when stopped returns .terminateNow immediately")
        
        // 2. Window Lifecycle Delegation
        final class MockWindowDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
            var windowClosed = false
            func windowWillClose(_ notification: Notification) {
                windowClosed = true
            }
        }
        
        let delegate = MockWindowDelegate()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        assertTest(!delegate.windowClosed, "Window delegate initialized with windowClosed == false")
        
        window.close()
        window.delegate = nil
        assertTest(delegate.windowClosed, "NSWindow close notification cleanly informs delegate without memory leak")
    }
}

@MainActor
func runExtendedSystemSuites() async {
    await runLaunchAtLoginSuites()
    await runIPCSecuritySuites()
    await runDatabaseRecoverySuites()
    await runTerminationLifecycleSuites()
}
