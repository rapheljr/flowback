import Foundation
import AppKit
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackTestHarness
import FlowbackUI

// MARK: - Thread-safe Test Box for Swift 6 Concurrency

final class TestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - Native Swift Async Coordination Signal

actor AsyncSignal {
    private var isSignaled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignaled = true
        for cont in continuations {
            cont.resume()
        }
        continuations.removeAll()
    }

    func wait() async {
        if isSignaled { return }
        await withCheckedContinuation { cont in
            continuations.append(cont)
        }
    }
}

// MARK: - Controllable Test Adapter

final class ControllableApplicationAdapter: ApplicationAdapter, @unchecked Sendable {
    let adapterName: String
    let bundleID: String
    var onRestore: (@Sendable () async -> Bool)?

    init(name: String? = nil, bundleID: String, onRestore: (@Sendable () async -> Bool)? = nil) {
        self.adapterName = name ?? "Controllable Test Adapter (\(bundleID))"
        self.bundleID = bundleID
        self.onRestore = onRestore
    }

    func canHandle(bundleIdentifier: String) -> Bool {
        bundleIdentifier == self.bundleID
    }

    func restoreContext(
        context: OriginContext,
        appController: ApplicationControlling,
        windowController: WindowControlling
    ) async -> Bool {
        if let onRestore = onRestore {
            return await onRestore()
        }
        return true
    }
}

// MARK: - Focus Hardening and Concurrency Suites

@MainActor
public func runFocusHardeningAndConcurrencySuites() async {
    print("\n================================================================")
    print("FLOWBACK FOCUS HARDENING & NAVIGATION CONCURRENCY SUITES")
    print("================================================================")

    // MARK: - 1. Restoration Contract & Honest Outcomes
    await testGroup("Focus Hardening — Restoration Contract & Honest Outcomes") {
        let mockApp = MockApplicationController()
        let mockWin = MockWindowController()
        let arbiter = AttentionArbiter(aggregationWindow: 1.0, cooldownDuration: 0.0)

        // Test 1: Window-only adapter never reports exactConversationRestored
        let focusController = FocusController(
            appController: mockApp,
            windowController: mockWin,
            arbiter: arbiter,
            permissionChecker: { true }
        )

        let sessionWindowOnly = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: nil,
            originContext: OriginContext(
                bundleIdentifier: "com.apple.TextEdit",
                processIdentifier: 1234,
                windowIdentifier: 10,
                restorationCapability: .exactWindowAndWorkspace
            ),
            focusCapability: .windowOnly
        )
        let resultWindow = await focusController.restoreSession(sessionWindowOnly)
        assertTest(resultWindow.outcome == .windowActivatedOnly, "Contract: Window-only origin yields .windowActivatedOnly")
        assertTest(resultWindow.isSuccessful, "Contract: .windowActivatedOnly is classified as successful")
        assertTest(!resultWindow.outcome.isExactConversation, "Contract: .windowActivatedOnly is NOT exact conversation")

        // Test 2: Workspace-only navigation reports .workspaceActivatedOnly
        let sessionWorkspace = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: "/Users/flowback/project",
            originContext: OriginContext(
                bundleIdentifier: "com.microsoft.VSCode",
                processIdentifier: 5678,
                workspacePath: "/Users/flowback/project",
                restorationCapability: .workspaceWindow
            ),
            focusCapability: .windowOnly
        )
        let resultWorkspace = await focusController.restoreSession(sessionWorkspace)
        assertTest(resultWorkspace.outcome == .workspaceActivatedOnly, "Contract: Workspace path yields .workspaceActivatedOnly")
        assertTest(!resultWorkspace.outcome.isExactConversation, "Contract: .workspaceActivatedOnly is NOT exact conversation")

        // Test 3: Ambiguous target when multiple windows match workspace folder
        mockWin.windowsMock = [
            WindowInfo(
                windowID: 101,
                processIdentifier: 9999,
                ownerName: "VSCode",
                title: "project — main.swift",
                bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
                isOnScreen: true
            ),
            WindowInfo(
                windowID: 102,
                processIdentifier: 9999,
                ownerName: "VSCode",
                title: "project — tests.swift",
                bounds: CGRect(x: 50, y: 50, width: 800, height: 600),
                isOnScreen: true
            )
        ]
        let sessionAmbiguous = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: "/Users/flowback/project",
            originContext: OriginContext(
                bundleIdentifier: "com.microsoft.VSCode",
                processIdentifier: 9999,
                windowIdentifier: nil,
                workspacePath: "/Users/flowback/project"
            )
        )
        let resultAmbig = await focusController.restoreSession(sessionAmbiguous)
        assertTest(resultAmbig.outcome == .targetAmbiguous, "Contract: Ambiguous candidate windows yield .targetAmbiguous")
        assertTest(!resultAmbig.isSuccessful, "Contract: .targetAmbiguous is NOT successful")

        // Test 4: Missing target yields conversationUnavailable or restorationUnsupported
        let sessionNoTarget = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: nil,
            originContext: nil,
            focusCapability: .windowOnly
        )
        let resultMissing = await focusController.restoreSession(sessionNoTarget)
        assertTest(resultMissing.outcome == .conversationUnavailable, "Contract: Missing origin context yields .conversationUnavailable")
        assertTest(!resultMissing.isSuccessful, "Contract: .conversationUnavailable is NOT successful")

        // Test 5: Permission denial does not become success
        let deniedController = FocusController(
            appController: mockApp,
            windowController: mockWin,
            arbiter: arbiter,
            permissionChecker: { false }
        )
        let sessionReqPerm = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: nil,
            originContext: OriginContext(
                bundleIdentifier: "com.apple.Terminal",
                processIdentifier: 4321,
                windowIdentifier: 777,
                restorationCapability: .exactWindowAndWorkspace
            )
        )
        let resultDenied = await deniedController.restoreSession(sessionReqPerm)
        assertTest(resultDenied.outcome == .permissionDenied, "Contract: Denied accessibility yields .permissionDenied")
        assertTest(!resultDenied.isSuccessful, "Contract: .permissionDenied is NOT successful")
        assertTest(resultDenied.message.contains("denied"), "Contract: Permission denial message is honest")

        // Test 6: Outcome property semantics
        assertTest(!RestorationOutcome.operationCancelled.isSuccessful, "Contract: .operationCancelled is not successful")
        assertTest(!RestorationOutcome.operationTimedOut.isSuccessful, "Contract: .operationTimedOut is not successful")
        assertTest(!RestorationOutcome.permissionDenied.isSuccessful, "Contract: .permissionDenied is not successful")
        assertTest(RestorationOutcome.operationCancelled.userFacingLabel.contains("cancelled"), "Contract: .operationCancelled label")
        assertTest(RestorationOutcome.operationTimedOut.userFacingLabel.contains("timed out"), "Contract: .operationTimedOut label")
        assertTest(RestorationOutcome.permissionDenied.userFacingLabel.contains("denied"), "Contract: .permissionDenied label")
    }

    // MARK: - 2. LaunchServices Activation Fallback
    await testGroup("Focus Hardening — LaunchServices Activation Fallback") {
        let openerCalledBox = TestBox<Bool>(false)
        let capturedURLBox = TestBox<URL?>(nil)
        let capturedConfigBox = TestBox<NSWorkspace.OpenConfiguration?>(nil)

        let targetURL = URL(fileURLWithPath: "/Applications/MockTarget.app")
        let appController = ApplicationController(
            workspaceOpener: { url, config in
                openerCalledBox.value = true
                capturedURLBox.value = url
                capturedConfigBox.value = config
                return true
            },
            directActivator: { _ in false },
            bundleURLResolver: { _ in targetURL }
        )

        let currentApp = NSRunningApplication.current

        // 1. Direct activation failure deterministically triggers synchronous LaunchServices fallback on background thread
        let bgFallbackSuccess = await Task.detached {
            appController.activate(application: currentApp)
        }.value

        assertTest(openerCalledBox.value == true, "LaunchServices: Synchronous fallback invoked injected workspaceOpener")
        assertTest(bgFallbackSuccess == true, "LaunchServices: Fallback activation returned true when opener succeeded")
        assertTest(capturedURLBox.value?.path == targetURL.path, "LaunchServices: Opener received correct application URL")
        assertTest(capturedConfigBox.value?.createsNewApplicationInstance == false, "LaunchServices: Config prevents new process instance")
        assertTest(capturedConfigBox.value?.activates == true, "LaunchServices: Config activates existing process")

        // 2. Synchronous activation on Main Thread returns false to avoid semaphore deadlock
        let mainThreadAppController = ApplicationController(
            workspaceOpener: nil,
            directActivator: { _ in false },
            bundleURLResolver: { _ in targetURL }
        )
        let syncMainResult = mainThreadAppController.activate(application: currentApp)
        assertTest(!syncMainResult, "LaunchServices: Synchronous activation on main thread returns false without deadlock")

        // 3. Fallback error visibility when opener returns false
        let failingOpener = ApplicationController(
            workspaceOpener: { _, _ in false },
            directActivator: { _ in false },
            bundleURLResolver: { _ in targetURL }
        )
        let failingResult = await Task.detached {
            failingOpener.activate(application: currentApp)
        }.value
        assertTest(!failingResult, "LaunchServices: Synchronous fallback returns false when opener returns false")

        // 4. Missing bundleURL returns false without invoking opener
        let noOpenerCalledBox = TestBox<Bool>(false)
        let noURLController = ApplicationController(
            workspaceOpener: { _, _ in
                noOpenerCalledBox.value = true
                return true
            },
            directActivator: { _ in false },
            bundleURLResolver: { _ in nil }
        )
        let noURLResult = noURLController.activate(application: currentApp)
        assertTest(!noURLResult, "LaunchServices: Direct failure with no bundleURL returns false")
        assertTest(!noOpenerCalledBox.value, "LaunchServices: Opener not invoked when bundleURL is missing")
    }

    // MARK: - 3. Concurrency Scenarios A through H
    await testGroup("Focus Hardening — Concurrency Scenarios A through H") {
        let mockApp = MockApplicationController()
        let mockWin = MockWindowController()

        // SCENARIO A: Newer request wins
        let regA = ApplicationAdapterRegistry()
        let adapterA = ControllableApplicationAdapter(bundleID: "com.flowback.test.a")
        regA.register(adapter: adapterA)

        let controllerA = FocusController(
            appController: mockApp,
            windowController: mockWin,
            adapterRegistry: regA,
            permissionChecker: { true }
        )

        let sessionA1 = AgentSession(
            providerID: .antigravity,
            state: .running,
            workspace: "/projects/a1",
            originContext: OriginContext(bundleIdentifier: "com.flowback.test.a", processIdentifier: 101, workspacePath: "/projects/a1")
        )
        let sessionA2 = AgentSession(
            providerID: .antigravity,
            state: .running,
            workspace: "/projects/a2",
            originContext: OriginContext(bundleIdentifier: "com.flowback.test.a", processIdentifier: 102, workspacePath: "/projects/a2")
        )

        // Set up controllable suspension for A1
        let a1Started = AsyncSignal()
        let a1CanFinish = AsyncSignal()

        adapterA.onRestore = {
            await a1Started.signal()
            await a1CanFinish.wait()
            return true
        }

        let taskA1 = Task {
            await controllerA.restoreSession(sessionA1)
        }

        // Wait until A1 is inside adapter
        await a1Started.wait()

        // Submit A2 while A1 is suspended
        adapterA.onRestore = { true }
        let resultA2 = await controllerA.restoreSession(sessionA2)
        assertTest(resultA2.isSuccessful, "Scenario A: Request A2 succeeded as the newest request")

        // Allow A1 to complete
        await a1CanFinish.signal()
        let resultA1 = await taskA1.value
        assertTest(!resultA1.isSuccessful, "Scenario A: Superseded Request A1 was NOT reported as successful")
        assertTest(resultA1.outcome == .operationCancelled, "Scenario A: Request A1 returned .operationCancelled")

        // SCENARIO B: Superseded operation generation check
        let genBefore = await controllerA.activeGeneration()
        let isSuperBefore = await controllerA.isSuperseded(generation: genBefore - 1)
        assertTest(isSuperBefore, "Scenario B: Older generation is recognized as superseded")

        // SCENARIO C: Out-of-order completions
        let regC = ApplicationAdapterRegistry()
        let adapterC = ControllableApplicationAdapter(bundleID: "com.flowback.test.c")
        regC.register(adapter: adapterC)
        let controllerC = FocusController(appController: mockApp, windowController: mockWin, adapterRegistry: regC, permissionChecker: { true })

        let c1Started = AsyncSignal()
        let c1Finish = AsyncSignal()

        adapterC.onRestore = {
            await c1Started.signal()
            await c1Finish.wait()
            return true
        }

        let sessionC1 = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.flowback.test.c", processIdentifier: 301))
        let sessionC2 = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.flowback.test.c", processIdentifier: 302))

        let taskC1 = Task { await controllerC.restoreSession(sessionC1) }
        await c1Started.wait()

        // C2 runs and finishes first
        adapterC.onRestore = { true }
        let resultC2 = await controllerC.restoreSession(sessionC2)
        assertTest(resultC2.isSuccessful, "Scenario C: C2 finished first and succeeded")

        // C1 finishes after C2
        await c1Finish.signal()
        let resultC1 = await taskC1.value
        assertTest(resultC1.outcome == .operationCancelled, "Scenario C: Late C1 completion is marked .operationCancelled")

        // SCENARIO D: Bounded timeout
        let regD = ApplicationAdapterRegistry()
        let adapterD = ControllableApplicationAdapter(bundleID: "com.flowback.test.d")
        adapterD.onRestore = {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            return true
        }
        regD.register(adapter: adapterD)
        let controllerD = FocusController(
            appController: mockApp,
            windowController: mockWin,
            adapterRegistry: regD,
            defaultTimeout: 0.05, // 50ms timeout
            permissionChecker: { true }
        )
        let sessionD = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.flowback.test.d", processIdentifier: 401))
        let resultD = await controllerD.restoreSession(sessionD, timeout: 0.05)
        assertTest(resultD.outcome == .operationTimedOut, "Scenario D: Operation exceeding timeout returns .operationTimedOut")
        assertTest(!resultD.isSuccessful, "Scenario D: Timed-out operation is NOT successful")

        // SCENARIO E: Burst repeated selection
        let regE = ApplicationAdapterRegistry()
        let adapterE = ControllableApplicationAdapter(bundleID: "com.flowback.test.e") {
            try? await Task.sleep(nanoseconds: 10_000_000)
            return true
        }
        regE.register(adapter: adapterE)
        let controllerE = FocusController(appController: mockApp, windowController: mockWin, adapterRegistry: regE, permissionChecker: { true })

        var burstTasks: [Task<RestorationResult, Never>] = []
        for i in 1...10 {
            let context = OriginContext(bundleIdentifier: "com.flowback.test.e", processIdentifier: Int32(500 + i))
            let s = AgentSession(providerID: .antigravity, state: .running, originContext: context)
            burstTasks.append(Task { await controllerE.restoreSession(s) })
        }
        var burstResults: [RestorationResult] = []
        for t in burstTasks {
            burstResults.append(await t.value)
        }
        assertTest(burstResults.count == 10, "Scenario E: Burst of 10 requests completed without deadlocks")
        let finalSuccess = burstResults.last?.isSuccessful ?? false
        assertTest(finalSuccess, "Scenario E: Final request in burst succeeded")

        // SCENARIO F: Explicit cancellation
        let regF = ApplicationAdapterRegistry()
        let adapterF = ControllableApplicationAdapter(bundleID: "com.flowback.test.f")
        let fStarted = AsyncSignal()
        let fCanFinish = AsyncSignal()
        adapterF.onRestore = {
            await fStarted.signal()
            await fCanFinish.wait()
            return true
        }
        regF.register(adapter: adapterF)
        let controllerF = FocusController(appController: mockApp, windowController: mockWin, adapterRegistry: regF, permissionChecker: { true })
        let sessionF = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.flowback.test.f", processIdentifier: 601))

        let taskF = Task { await controllerF.restoreSession(sessionF) }
        await fStarted.wait()
        await controllerF.cancelCurrentNavigation()
        await fCanFinish.signal()
        let resultF = await taskF.value
        assertTest(resultF.outcome == .operationCancelled, "Scenario F: Explicitly cancelled request returns .operationCancelled")

        // SCENARIO G: Failure isolation
        let regG = ApplicationAdapterRegistry()
        let shouldFailBox = TestBox<Bool>(true)
        let adapterG = ControllableApplicationAdapter(bundleID: "com.flowback.test.g") {
            return !shouldFailBox.value
        }
        regG.register(adapter: adapterG)
        let controllerG = FocusController(appController: mockApp, windowController: mockWin, adapterRegistry: regG, permissionChecker: { true })
        let sessionG1 = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.flowback.test.g", processIdentifier: 701))
        let sessionG2 = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.flowback.test.g", processIdentifier: 702))

        let resultG1 = await controllerG.restoreSession(sessionG1)
        assertTest(resultG1.outcome == .restorationFailed, "Scenario G: Failing request reports .restorationFailed")

        shouldFailBox.value = false
        let resultG2 = await controllerG.restoreSession(sessionG2)
        assertTest(resultG2.isSuccessful, "Scenario G: Subsequent request succeeds independently (failure isolation)")

        // SCENARIO H: Shutdown
        await controllerG.shutdown()
        let resultH = await controllerG.restoreSession(sessionG2)
        assertTest(resultH.outcome == .operationCancelled, "Scenario H: Requests rejected after shutdown with .operationCancelled")
        assertTest(resultH.message.contains("shut down"), "Scenario H: Shutdown reason reported in message")
    }

    // MARK: - 4. Frozen Menu-Slot Ordering
    await testGroup("Focus Hardening — Frozen Menu-Slot Ordering") {
        let menuController = MenuBarController()
        let menu = NSMenu()

        let session1 = AgentSession(providerID: .antigravity, state: .running, workspace: "/p/1", conversationTitle: "Session 1")
        let session2 = AgentSession(providerID: .antigravity, state: .running, workspace: "/p/2", conversationTitle: "Session 2")
        let session3 = AgentSession(providerID: .antigravity, state: .running, workspace: "/p/3", conversationTitle: "Session 3")

        menuController.updateState(
            activeSessions: [session1, session2],
            recentSessions: [session1, session2],
            attentionQueue: [],
            focusLock: FocusLockState()
        )

        // 1. Before opening: menu is not open
        assertTest(!menuController.isMenuOpen, "MenuSlots: Initial state isMenuOpen is false")
        assertTest(menuController.frozenRecentSessions == nil, "MenuSlots: Initial frozenRecentSessions is nil")

        // 2. Open menu: snapshot captured
        menuController.menuWillOpen(menu)
        assertTest(menuController.isMenuOpen, "MenuSlots: menuWillOpen sets isMenuOpen to true")
        assertTest(menuController.frozenRecentSessions?.count == 2, "MenuSlots: frozenRecentSessions captured 2 sessions")
        assertTest(menuController.frozenRecentSessions?.first?.id == session1.id, "MenuSlots: Slot 1 is session 1")

        // 3. Background state mutation while menu is OPEN
        // Session 3 arrives and order is reversed: [session3, session2, session1]
        menuController.updateState(
            activeSessions: [session3, session2, session1],
            recentSessions: [session3, session2, session1],
            attentionQueue: [],
            focusLock: FocusLockState()
        )

        // Render menu while open
        menuController.menuNeedsUpdate(menu)

        // Verify that Recent Sessions submenu still renders the FROZEN items (session 1, then session 2)
        let recentParent = menu.items.first(where: { $0.title == "Recent Agent Sessions" })
        assertTest(recentParent != nil, "MenuSlots: Recent Agent Sessions menu item exists")
        let recentSubmenu = recentParent?.submenu
        assertTest(recentSubmenu?.items.count == 2, "MenuSlots: Open menu still has exactly 2 recent items from snapshot")
        let slot1 = recentSubmenu?.items.first
        assertTest(slot1?.representedObject as? String == session1.id.rawValue, "MenuSlots: Slot 1 (⌘1) remains session 1 despite background reordering")
        let slot2 = recentSubmenu?.items.dropFirst().first
        assertTest(slot2?.representedObject as? String == session2.id.rawValue, "MenuSlots: Slot 2 (⌘2) remains session 2 despite background reordering")

        // 4. Close menu: snapshot is cleared
        menuController.menuDidClose(menu)
        assertTest(!menuController.isMenuOpen, "MenuSlots: menuDidClose sets isMenuOpen to false")
        assertTest(menuController.frozenRecentSessions == nil, "MenuSlots: menuDidClose clears frozenRecentSessions")

        // 5. Reopen menu: new snapshot incorporates updated state
        menuController.menuWillOpen(menu)
        assertTest(menuController.frozenRecentSessions?.count == 3, "MenuSlots: Reopened menu captures 3 recent sessions")
        assertTest(menuController.frozenRecentSessions?.first?.id == session3.id, "MenuSlots: Reopened menu Slot 1 is now session 3")
        menuController.menuDidClose(menu)
    }

    // MARK: - 5. Remediated Concurrency, Lifecycle & Fallback Verifications
    await testGroup("Focus Hardening — Remediated Concurrency, Lifecycle & Fallback Verifications") {
        // --- Test 1: Task Cancellation Propagation in executeWithTimeout ---
        let cancelSignal = AsyncSignal()
        let slowAdapter = ControllableApplicationAdapter(bundleID: "com.test.cancellation") {
            await cancelSignal.wait()
            return true
        }
        let regCancel = ApplicationAdapterRegistry()
        regCancel.register(adapter: slowAdapter)
        let controllerCancel = FocusController(
            appController: MockApplicationController(),
            windowController: MockWindowController(),
            adapterRegistry: regCancel,
            permissionChecker: { true }
        )
        let sessionCancel = AgentSession(
            providerID: .antigravity,
            state: .running,
            workspace: "/p/cancel",
            originContext: OriginContext(bundleIdentifier: "com.test.cancellation", processIdentifier: 1001)
        )
        let cancelTask = Task {
            await controllerCancel.restoreSession(sessionCancel, timeout: 5.0)
        }
        // Yield briefly to let task enter executeWithTimeout
        try? await Task.sleep(nanoseconds: 10_000_000)
        cancelTask.cancel()
        let cancelResult = await cancelTask.value
        assertTest(cancelResult.outcome == .operationCancelled, "Cancellation: Propagated task cancellation yields .operationCancelled")
        assertTest(!cancelResult.isSuccessful, "Cancellation: Cancelled task is not reported as successful")
        await cancelSignal.signal()

        // --- Test 2: In-Flight Supersession Aborts Child Tasks Before OS Mutations ---
        let step1Started = AsyncSignal()
        let step1CanProceed = AsyncSignal()
        let secondStepReached = TestBox<Bool>(false)
        let adapterSupersede1 = ControllableApplicationAdapter(bundleID: "com.test.supersede1") {
            await step1Started.signal()
            await step1CanProceed.wait()
            if !Task.isCancelled {
                secondStepReached.value = true
            }
            return true
        }
        let adapterSupersede2 = ControllableApplicationAdapter(bundleID: "com.test.supersede2") {
            return true
        }
        let regSupersede = ApplicationAdapterRegistry()
        regSupersede.register(adapter: adapterSupersede1)
        regSupersede.register(adapter: adapterSupersede2)
        let controllerSupersede = FocusController(
            appController: MockApplicationController(),
            windowController: MockWindowController(),
            adapterRegistry: regSupersede,
            permissionChecker: { true }
        )
        let sessionSupersede1 = AgentSession(
            providerID: .antigravity,
            state: .running,
            workspace: "/p/s1",
            originContext: OriginContext(bundleIdentifier: "com.test.supersede1", processIdentifier: 1002, workspacePath: "/p/s1")
        )
        let sessionSupersede2 = AgentSession(
            providerID: .antigravity,
            state: .running,
            workspace: "/p/s2",
            originContext: OriginContext(bundleIdentifier: "com.test.supersede2", processIdentifier: 1003, workspacePath: "/p/s2")
        )
        let task1 = Task {
            await controllerSupersede.restoreSession(sessionSupersede1, timeout: 5.0)
        }
        await step1Started.wait()
        let task2 = Task {
            await controllerSupersede.restoreSession(sessionSupersede2, timeout: 5.0)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await step1CanProceed.signal()
        let res2 = await task2.value
        let res1 = await task1.value
        assertTest(res2.isSuccessful, "Supersession: Newest request 2 succeeded")
        assertTest(res1.outcome == .operationCancelled, "Supersession: Superseded request 1 was cancelled")
        assertTest(!secondStepReached.value, "Supersession: Request 1 child task halted before second OS mutation step")

        // --- Test 3: fallbackApplication in handleSessionCompletion Supersession Protection ---
        let arbiterFallback = AttentionArbiter(aggregationWindow: 1.0, cooldownDuration: 10.0)
        let mockAppFallback = MockApplicationController()
        let controllerFallback = FocusController(
            appController: mockAppFallback,
            windowController: MockWindowController(),
            arbiter: arbiterFallback,
            permissionChecker: { true }
        )
        // Explicitly cancel navigation right before evaluating fallback decision
        await controllerFallback.cancelCurrentNavigation()
        let sessionFallback = AgentSession(
            providerID: .antigravity,
            state: .completed,
            workspace: "/p/fb",
            originContext: OriginContext(bundleIdentifier: "com.apple.Terminal", processIdentifier: 2001)
        )
        // IntentEngine will evaluate fallbackApplication if frontmost matches rule or direct config
        _ = await controllerFallback.handleSessionCompletion(
            session: sessionFallback,
            config: .default,
            focusLock: FocusLockState()
        )
        // Since controller was cancelled, fallbackApplication must fail gracefully
        assertTest(mockAppFallback.activatedApps.isEmpty, "FallbackSafety: Cancelled navigation did not activate application")
        assertTest(await arbiterFallback.canRestoreFocusNow(), "FallbackSafety: Arbiter did not record restoration on cancelled fallback")

        // --- Test 4: restoreContext Uniform Timeout, Cancellation, and Supersession ---
        let hangingContextAdapter = ControllableApplicationAdapter(bundleID: "com.test.hanging-context") {
            try? await Task.sleep(nanoseconds: 200_000_000)
            return true
        }
        let regContext = ApplicationAdapterRegistry()
        regContext.register(adapter: hangingContextAdapter)
        let controllerContext = FocusController(
            appController: MockApplicationController(),
            windowController: MockWindowController(),
            adapterRegistry: regContext,
            permissionChecker: { true }
        )
        let context1 = OriginContext(bundleIdentifier: "com.test.hanging-context", processIdentifier: 3001)
        let timedOut = await controllerContext.restoreContext(context1, timeout: 0.05)
        assertTest(!timedOut, "RestoreContext: Exceeding timeout safely returns false")

        // Competing restoreContext requests
        let ctxTask1 = Task {
            await controllerContext.restoreContext(context1, timeout: 2.0)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let fastContext = OriginContext(bundleIdentifier: "com.test.generic-ok", processIdentifier: 3002)
        let fastSuccess = await controllerContext.restoreContext(fastContext, timeout: 2.0)
        let ctx1Result = await ctxTask1.value
        assertTest(fastSuccess, "RestoreContext: Competing newer request succeeds")
        assertTest(!ctx1Result, "RestoreContext: Older superseded request fails")

        // --- Test 5: ApplicationAdapterRegistry Deterministic FIFO Precedence & No Duplicates ---
        final class NamedAdapter: ApplicationAdapter, @unchecked Sendable {
            let adapterName: String
            let bundleID: String
            init(name: String, bundleID: String) {
                self.adapterName = name
                self.bundleID = bundleID
            }
            func canHandle(bundleIdentifier: String) -> Bool { bundleIdentifier == self.bundleID }
            func restoreContext(context: OriginContext, appController: ApplicationControlling, windowController: WindowControlling) async -> Bool { true }
        }

        let regPrec = ApplicationAdapterRegistry()
        let adapterFirst = NamedAdapter(name: "PriorityFirst", bundleID: "com.test.fifo")
        let adapterSecond = NamedAdapter(name: "PrioritySecond", bundleID: "com.test.fifo")
        regPrec.register(adapter: adapterFirst)
        regPrec.register(adapter: adapterSecond)

        // FIFO: first registered specialized adapter should win
        let resolvedAdapter = regPrec.findAdapter(for: "com.test.fifo")
        assertTest(resolvedAdapter?.adapterName == "PriorityFirst", "AdapterRegistry: FIFO order preserved; first registered specialized adapter wins")

        // Specialized adapter always wins over Generic fallback
        let genericResolved = regPrec.findAdapter(for: "com.random.unregistered")
        assertTest(genericResolved is GenericApplicationAdapter, "AdapterRegistry: Unregistered bundle falls back to GenericApplicationAdapter")

        // Duplicate registration updates in place without duplicating
        let initialCount = regPrec.allAdapters.count
        regPrec.register(adapter: NamedAdapter(name: "PriorityFirst", bundleID: "com.test.fifo"))
        let afterCount = regPrec.allAdapters.count
        assertTest(initialCount == afterCount, "AdapterRegistry: Re-registering adapter with same name does not duplicate entry")

        // --- Test 6: Asynchronous Non-Blocking ApplicationController ---
        let asyncOpenerCalledBox = TestBox<Bool>(false)
        let capturedAsyncURLBox = TestBox<URL?>(nil)
        let capturedAsyncConfigBox = TestBox<NSWorkspace.OpenConfiguration?>(nil)
        let asyncTargetURL = URL(fileURLWithPath: "/Applications/MockAsyncTarget.app")

        let mockAsyncOpener: ApplicationController.AsyncWorkspaceOpener = { url, config in
            asyncOpenerCalledBox.value = true
            capturedAsyncURLBox.value = url
            capturedAsyncConfigBox.value = config
            return true
        }
        let asyncAppController = ApplicationController(
            asyncWorkspaceOpener: mockAsyncOpener,
            directActivator: { _ in false },
            bundleURLResolver: { _ in asyncTargetURL }
        )
        if let currentApp = NSRunningApplication.current as NSRunningApplication? {
            let asyncSuccess = await asyncAppController.activateApplication(currentApp)
            assertTest(asyncSuccess, "ApplicationController: Asynchronous activateApplication succeeds via async fallback")
            assertTest(asyncOpenerCalledBox.value, "ApplicationController: Injected asyncWorkspaceOpener was actually called")
            assertTest(capturedAsyncURLBox.value?.path == asyncTargetURL.path, "ApplicationController: Async opener received correct application URL")
            assertTest(capturedAsyncConfigBox.value?.activates == true, "ApplicationController: Async config activates process")
            assertTest(capturedAsyncConfigBox.value?.createsNewApplicationInstance == false, "ApplicationController: Async config prevents new instance")
        }

        // Asynchronous fallback failure propagation
        let failingAsyncController = ApplicationController(
            asyncWorkspaceOpener: { _, _ in throw NSError(domain: "test", code: -1) },
            directActivator: { _ in false },
            bundleURLResolver: { _ in asyncTargetURL }
        )
        if let currentApp = NSRunningApplication.current as NSRunningApplication? {
            let failResult = await failingAsyncController.activateApplication(currentApp)
            assertTest(!failResult, "ApplicationController: Asynchronous fallback returns false when opener throws")
        }

        // Asynchronous cancellation suppression
        let cancelledAsyncSignal = AsyncSignal()
        let slowAsyncController = ApplicationController(
            asyncWorkspaceOpener: { _, _ in
                await cancelledAsyncSignal.wait()
                return true
            },
            directActivator: { _ in false },
            bundleURLResolver: { _ in asyncTargetURL }
        )
        if let currentApp = NSRunningApplication.current as NSRunningApplication? {
            let cancelTask = Task {
                await slowAsyncController.activateApplication(currentApp)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
            cancelTask.cancel()
            await cancelledAsyncSignal.signal()
            let cancelResult = await cancelTask.value
            assertTest(!cancelResult, "ApplicationController: Asynchronous fallback returns false when cancelled")
        }

        // --- Test 7: Deterministic Three-Request Regression Test for F-01 (Actor Reentrancy Ownership) ---
        let aStarted = AsyncSignal()
        let aCanExit = AsyncSignal()

        let bStarted = AsyncSignal()
        let bCancelled = AsyncSignal()
        let bObservedCancellationBox = TestBox<Bool>(false)

        let adapterA = ControllableApplicationAdapter(bundleID: "com.test.f01.a") {
            await aStarted.signal()
            await aCanExit.wait()
            return true
        }

        let adapterB = ControllableApplicationAdapter(bundleID: "com.test.f01.b") {
            await bStarted.signal()
            // Wait until cancelled by C, with upper bound to avoid infinite hang if bug exists
            for _ in 0..<50 {
                if Task.isCancelled {
                    bObservedCancellationBox.value = true
                    await bCancelled.signal()
                    return false
                }
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms check
            }
            return true
        }

        let adapterC = ControllableApplicationAdapter(bundleID: "com.test.f01.c") {
            return true
        }

        let regF01 = ApplicationAdapterRegistry()
        regF01.register(adapter: adapterA)
        regF01.register(adapter: adapterB)
        regF01.register(adapter: adapterC)

        let controllerF01 = FocusController(
            appController: MockApplicationController(),
            windowController: MockWindowController(),
            adapterRegistry: regF01,
            permissionChecker: { true }
        )

        let sessionA = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.test.f01.a", processIdentifier: 901))
        let sessionB = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.test.f01.b", processIdentifier: 902))
        let sessionC = AgentSession(providerID: .antigravity, state: .running, originContext: OriginContext(bundleIdentifier: "com.test.f01.c", processIdentifier: 903))

        // 1. Request A begins and suspends in its worker
        let taskA = Task {
            await controllerF01.restoreSession(sessionA, timeout: 5.0)
        }
        await aStarted.wait()

        // 2. Request B supersedes A and becomes active
        let taskB = Task {
            await controllerF01.restoreSession(sessionB, timeout: 5.0)
        }
        await bStarted.wait()

        // 3. A resumes and exits executeWithTimeout while B is still running
        await aCanExit.signal()
        let resultA = await taskA.value
        assertTest(resultA.outcome == .operationCancelled, "F-01 Regression: Request A completed with .operationCancelled")

        // 4. Request C arrives and supersedes B
        let taskC = Task {
            await controllerF01.restoreSession(sessionC, timeout: 5.0)
        }

        // 5. Assert B's worker observes cancellation promptly (without waiting for 5.0s timeout)
        await bCancelled.wait()
        let resultB = await taskB.value
        assertTest(bObservedCancellationBox.value, "F-01 Regression: Request B worker observed prompt cancellation upon arrival of C")
        assertTest(resultB.outcome == .operationCancelled, "F-01 Regression: Request B result is .operationCancelled")

        // 6. Assert C remains active request and succeeds
        let resultC = await taskC.value
        assertTest(resultC.isSuccessful, "F-01 Regression: Request C succeeded as the winning request")
        assertTest(await controllerF01.activeRequestToken()?.sessionID == sessionC.id, "F-01 Regression: Active token belongs to Request C")

        // --- Test 8: Adversarial TimeoutCoordinator Concurrency & Lifecycle Suite ---
        // 1. Cancellation before continuation installation
        let coord1 = TimeoutCoordinator<String>()
        coord1.cancel()
        let coordRes1 = await withCheckedContinuation { cont in
            coord1.startWaiting(continuation: cont)
        }
        assertTest(coordRes1 == .cancelled, "TimeoutCoordinator: Cancellation before startWaiting resumes immediately with .cancelled")

        // 2. Operation completion racing with cancellation (20 parallel iterations)
        for i in 1...20 {
            let coord2 = TimeoutCoordinator<String>()
            let signalReady2 = AsyncSignal()
            let signalGo2 = AsyncSignal()

            let task2 = Task {
                await withCheckedContinuation { cont in
                    coord2.startWaiting(continuation: cont)
                    Task { await signalReady2.signal() }
                }
            }
            await signalReady2.wait()

            let t1 = Task {
                await signalGo2.wait()
                coord2.complete(with: .success("worker_\(i)"))
            }
            let t2 = Task {
                await signalGo2.wait()
                coord2.cancel()
            }
            await signalGo2.signal()
            _ = await (t1.value, t2.value)
            let winningResult = await task2.value
            assertTest(winningResult == .success("worker_\(i)") || winningResult == .cancelled, "TimeoutCoordinator Race: Exactly one terminal result won in race \(i)")
        }

        // 3. Timeout racing with operation completion (20 parallel iterations)
        for i in 1...20 {
            let coord3 = TimeoutCoordinator<String>()
            let signalReady3 = AsyncSignal()
            let signalGo3 = AsyncSignal()

            let task3 = Task {
                await withCheckedContinuation { cont in
                    coord3.startWaiting(continuation: cont)
                    Task { await signalReady3.signal() }
                }
            }
            await signalReady3.wait()

            let tWorker = Task {
                await signalGo3.wait()
                coord3.complete(with: .success("val_\(i)"))
            }
            let tTimer = Task {
                await signalGo3.wait()
                coord3.complete(with: .timedOut)
            }
            await signalGo3.signal()
            _ = await (tWorker.value, tTimer.value)
            let winner3 = await task3.value
            assertTest(winner3 == .success("val_\(i)") || winner3 == .timedOut, "TimeoutCoordinator Race: Exactly one winner between timeout and completion in race \(i)")
        }

        // 4. Worker completing after timeout has already returned
        let coord4 = TimeoutCoordinator<String>()
        let task4 = Task {
            await withCheckedContinuation { cont in
                coord4.startWaiting(continuation: cont)
            }
        }
        coord4.complete(with: .timedOut)
        let coordRes4 = await task4.value
        assertTest(coordRes4 == .timedOut, "TimeoutCoordinator: First completed result is .timedOut")

        // Late worker completes after continuation has already resumed
        coord4.complete(with: .success("late_value"))
        // Idempotent: late completion is dropped without throwing or corrupting state

        // 5. Repeated terminal completion attempts
        let coord5 = TimeoutCoordinator<String>()
        let task5 = Task {
            await withCheckedContinuation { cont in
                coord5.startWaiting(continuation: cont)
            }
        }
        coord5.complete(with: .success("first_win"))
        coord5.complete(with: .timedOut)
        coord5.cancel()
        coord5.complete(with: .success("second_win"))
        let coordRes5 = await task5.value
        assertTest(coordRes5 == .success("first_win"), "TimeoutCoordinator: Repeated completion calls are idempotent and first result wins")

        // 6. Child-task handles installed after coordinator has already reached terminal state & Resource Lifecycle
        let coord6 = TimeoutCoordinator<String>()
        coord6.cancel()

        let dummyWorker: Task<Void, Never> = Task {
            _ = try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let dummyTimer: Task<Void, Never> = Task {
            _ = try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Set child tasks AFTER coordinator already reached .completed
        coord6.setChildTasks(worker: dummyWorker, timeout: dummyTimer)

        _ = await (dummyWorker.value, dummyTimer.value)
        assertTest(dummyWorker.isCancelled, "TimeoutCoordinator Lifecycle: Worker task cancelled when set on terminal coordinator")
        assertTest(dummyTimer.isCancelled, "TimeoutCoordinator Lifecycle: Timeout task cancelled when set on terminal coordinator")
        assertTest(!coord6.hasRetainedChildTasks, "TimeoutCoordinator Lifecycle: Completed coordinator does not retain child tasks")
    }
}
