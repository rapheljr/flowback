import Foundation
import AppKit
import SwiftUI
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackNotifications
import FlowbackUI
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "FlowbackService")

@MainActor
public final class FlowbackService: NSObject, ObservableObject {
    public static let shared = FlowbackService()

    // Lifecycle State
    @Published public private(set) var lifecycleState: ServiceLifecycleState = .notStarted
    @Published public private(set) var isIPCReady: Bool = false
    @Published public private(set) var isDatabaseReady: Bool = false
    @Published public private(set) var isStorageDurable: Bool = true
    @Published public private(set) var storageRecoveryNotice: String?
    @Published public private(set) var startupErrorMessage: String?

    // Core Engine
    public let eventBus = EventBus.shared
    public let timelineTracker = TimelineTracker.shared
    public private(set) var database: SQLiteDatabase!
    public private(set) var sessionRepository: SessionRepository!
    public private(set) var settingsRepository: SettingsRepository!
    public private(set) var eventRepository: EventRepository!

    public private(set) var sessionManager: SessionManager!
    public private(set) var attentionArbiter: AttentionArbiter!
    public private(set) var focusController: FocusController!
    public private(set) var providerRegistry: ProviderRegistry!

    // Server & Notifications
    public var isHeadless: Bool = false
    private var socketServer: UnixSocketServer!
    private var ipcHandler: IPCHandler!
    private let notificationManager = NotificationManager.shared
    private let menuBarController = MenuBarController()

    // Managed Background Tasks & Observers (Owned lifecycle resources)
    private var agentEventsTask: Task<Void, Never>?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var globalHotkeyMonitor: Any?

    // Observable UI state
    @Published public var activeSessions: [AgentSession] = []
    @Published public var allSessions: [AgentSession] = []
    @Published public var attentionQueue: [AttentionRequest] = []
    @Published public var timelineEntries: [TimelineEntry] = []
    @Published public var providerHealths: [ProviderHealth] = []
    @Published public var permissionStatus: PermissionStatus = PermissionStatus()
    @Published public var configuration: PolicyConfiguration = .default
    @Published public var focusLock: FocusLockState = FocusLockState()

    public let lifecycleCoordinator = LifecycleCoordinator()
    private var isPerformingMaintenance = false

    // Dashboard window & navigation model
    private var dashboardWindow: NSWindow?
    private let dashboardViewModel = DashboardViewModel()

    // UI Event Coalescer
    public private(set) var uiCoalescer: UIEventCoalescer!

    public init(uiCoalesceInterval: TimeInterval = 0.05) {
        super.init()
        self.uiCoalescer = UIEventCoalescer(interval: uiCoalesceInterval) { [weak self] in
            await self?.updateMinimalUIState()
        }
    }

    public override convenience init() {
        self.init(uiCoalesceInterval: 0.05)
    }

    public func setUICoalesceInterval(_ interval: TimeInterval) {
        self.uiCoalescer?.stop()
        self.uiCoalescer = UIEventCoalescer(interval: interval) { [weak self] in
            await self?.updateMinimalUIState()
        }
    }

    public func setUICoalescer(_ coalescer: UIEventCoalescer) {
        self.uiCoalescer?.stop()
        self.uiCoalescer = coalescer
    }

    public func flushPendingUIUpdates() async {
        await uiCoalescer?.flush()
    }


    // MARK: - Authoritative Lifecycle Start

    public func start() async {
        let currentCoordState = await lifecycleCoordinator.currentState
        guard currentCoordState != .starting && currentCoordState != .ready else {
            logger.warning("FlowbackService start() invoked while state is \(self.lifecycleState.rawValue); ignoring duplicate invocation.")
            return
        }

        logger.info("Starting Flowback Universal Context & Focus Manager...")
        try? await lifecycleCoordinator.transition(to: .starting)
        lifecycleState = .starting
        startupErrorMessage = nil
        uiCoalescer?.reset()

        // 1. Storage setup & corruption recovery
        let dbPath = ("~/.flowback/flowback.sqlite" as NSString).expandingTildeInPath
        let storageResult = await RecoveryManager.shared.initializeStorageDetailed(path: dbPath)
        self.database = storageResult.database
        self.isStorageDurable = storageResult.isDurable
        self.storageRecoveryNotice = storageResult.recoveryNotice
        self.sessionRepository = SessionRepository(db: database)
        self.settingsRepository = SettingsRepository(db: database)
        self.eventRepository = EventRepository(db: database)
        self.isDatabaseReady = true

        if !storageResult.isDurable {
            self.lifecycleState = .degraded
            logger.warning("Operating in degraded storage mode: \(storageResult.recoveryNotice ?? "")")
        }

        // 2. Load preferences
        self.configuration = await settingsRepository.loadConfiguration()

        // 3. Coordinate core subsystems
        self.sessionManager = SessionManager(
            timeline: timelineTracker,
            storageDelegate: sessionRepository,
            eventBus: eventBus
        )
        self.attentionArbiter = AttentionArbiter(
            aggregationWindow: Double(configuration.attentionAggregationMs) / 1000.0,
            cooldownDuration: Double(configuration.focusCooldownMs) / 1000.0
        )
        self.focusController = FocusController(
            intentEngine: UserIntentEngine(),
            arbiter: attentionArbiter,
            timeline: timelineTracker
        )

        // 4. Register Providers
        self.providerRegistry = ProviderRegistry.shared
        await providerRegistry.register(provider: AntigravityProvider())
        await providerRegistry.register(provider: ClaudeCodeProvider())
        await providerRegistry.register(provider: CodexProvider())
        await providerRegistry.register(provider: AntigravityCLIProvider())
        await providerRegistry.register(provider: AiderProvider())
        await providerRegistry.register(provider: WindsurfProvider())
        await providerRegistry.register(provider: OpenCodeProvider())
        await providerRegistry.register(provider: CursorBackgroundProvider())
        await providerRegistry.register(provider: GenericHookProvider())

        // 5. Restore persisted sessions and reconcile any orphaned ones
        let persisted = (try? await sessionRepository.fetchRecentSessions(limit: 50)) ?? []
        await sessionManager.restorePersistedSessions(persisted)
        await sessionManager.reconcileOrphanedSessions()

        // 6. Setup Notifications & Menu Bar
        notificationManager.setActionDelegate(self)
        notificationManager.registerDelegate()

        if !isHeadless {
            menuBarController.setDelegate(self)
            menuBarController.setup()
        }

        // 7. Setup IPC Server with graceful shutdown, authorization, and notification hooks
        let sessionToken = UUID().uuidString
        self.ipcHandler = IPCHandler(
            eventBus: eventBus,
            sessionManager: sessionManager,
            focusController: focusController,
            providerRegistry: providerRegistry,
            settingsRepo: settingsRepository,
            focusLock: focusLock,
            sessionToken: sessionToken,
            shutdownHandler: { [weak self] in
                Task { @MainActor in
                    self?.requestQuit()
                }
            },
            testNotificationHandler: { [weak self] in
                await self?.notificationManager.sendAggregatedNotification(
                    title: "Flowback Test Alert",
                    body: "Notification and focus routing verification succeeded."
                )
            }
        )
        self.socketServer = UnixSocketServer(delegate: ipcHandler, sessionToken: sessionToken)
        do {
            try socketServer.start()
            self.isIPCReady = socketServer.isListening
            logger.info("Unix Socket Server listening at \(self.socketServer.socketPath)")
        } catch {
            logger.error("Failed to start UnixSocketServer: \(error.localizedDescription)")
            self.isIPCReady = false
            self.startupErrorMessage = "IPC Socket error: \(error.localizedDescription)"
        }

        // 8. Observe Events and System changes with retained ownership
        startEventLoops()
        setupSystemObservers()
        setupGlobalHotkeys()

        // 9. Initial state refresh
        await refreshUIState()

        // 10. Conclude startup state
        let targetState: ServiceLifecycleState = (isIPCReady && isDatabaseReady) ? .ready : .degraded
        try? await lifecycleCoordinator.transition(to: targetState)
        lifecycleState = targetState
        logger.info("Flowback initialized and monitoring (State: \(targetState.rawValue)).")
    }

    // MARK: - Authoritative Single Shutdown Coordinator

    public func stop() async {
        let currentCoordState = await lifecycleCoordinator.currentState
        guard currentCoordState != .stopping && currentCoordState != .stopped else {
            logger.info("FlowbackService stop() called while state is \(self.lifecycleState.rawValue); ignoring duplicate invocation.")
            return
        }

        logger.info("Stopping Flowback Universal Context & Focus Manager...")
        lifecycleState = .stopping

        await lifecycleCoordinator.stop()

        // 1. Stop IPC server immediately so no new requests are accepted
        self.socketServer?.stop()
        self.isIPCReady = false

        // 2. Cancel and clean up background tasks
        self.agentEventsTask?.cancel()
        self.agentEventsTask = nil
        self.backgroundRefreshTask?.cancel()
        self.backgroundRefreshTask = nil
        self.uiCoalescer?.stop()

        // 3. Reset and finish all active event bus stream continuations
        await self.eventBus.finishAll()

        // 4. Remove all registered workspace notification center observers
        for token in self.workspaceObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        self.workspaceObserverTokens.removeAll()

        // 5. Remove global hotkey monitors
        if let monitor = self.globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalHotkeyMonitor = nil
        }

        // 6. Teardown MenuBar status item
        if !self.isHeadless {
            self.menuBarController.teardown()
        }

        // 7. Close companion dashboard window if open
        if let win = self.dashboardWindow {
            win.delegate = nil
            win.close()
            self.dashboardWindow = nil
        }

        // 8. Close persistent SQLite database
        if let db = self.database {
            await db.close()
            self.database = nil
            self.isDatabaseReady = false
        }

        lifecycleState = .stopped
        logger.info("FlowbackService stopped cleanly.")
    }

    /// Synchronous safety barrier invoked during OS application termination callbacks
    public func emergencySyncStop() {
        guard lifecycleState != .stopped else { return }
        lifecycleState = .stopping
        socketServer?.stop()
        socketServer = nil
        isIPCReady = false
        agentEventsTask?.cancel()
        agentEventsTask = nil
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        uiCoalescer?.stop()
        for token in workspaceObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObserverTokens.removeAll()
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalHotkeyMonitor = nil
        }
        if !isHeadless {
            menuBarController.teardown()
        }
        if let win = dashboardWindow {
            win.delegate = nil
            win.close()
            dashboardWindow = nil
        }
        lifecycleState = .stopped
    }

    /// Converges all Quit triggers (Menu Bar, App Menu, Hotkey, CLI) into single shutdown
    public func requestQuit() {
        logger.info("Authoritative Quit requested.")
        if NSApp != nil {
            NSApp.terminate(nil)
        } else {
            Task {
                await stop()
                exit(0)
            }
        }
    }

    // MARK: - Event Loops

    private func startEventLoops() {
        agentEventsTask?.cancel()
        agentEventsTask = Task { [weak self] in
            guard let self = self else { return }
            for await event in await self.eventBus.agentEvents() {
                if Task.isCancelled { break }
                await self.handleAgentEvent(event)
            }
        }
    }

    private func handleAgentEvent(_ event: AgentEvent) async {
        guard lifecycleState == .ready || lifecycleState == .degraded else { return }

        let session = await sessionManager.handleEvent(event)
        try? await eventRepository.saveEvent(event)

        // Check terminal states for attention
        if event.type == .agentCompleted || event.type == .agentFailed || event.type == .agentPermissionRequired {
            let priority: AttentionPriority = (event.type == .agentPermissionRequired) ? .permissionRequired :
                ((event.type == .agentFailed) ? .failure : .completed)

            let req = AttentionRequest(
                sessionID: session.id,
                providerID: session.providerID,
                priority: priority,
                title: "\(session.providerDisplayName): \(session.displayTitle)",
                message: "\(session.projectName) • \(session.state.displayName)",
                workspace: session.workspace
            )
            await attentionArbiter.enqueue(req)

            // Evaluate focus restoration
            let decision = await focusController.handleSessionCompletion(
                session: session,
                config: configuration,
                focusLock: focusLock
            )

            if !decision.shouldActivateApp {
                // Show actionable notification
                await notificationManager.sendAttentionNotification(
                    session: session,
                    title: "\(session.providerDisplayName): \(session.displayTitle)",
                    body: "\(session.projectName) • \(decision.explanation)"
                )
            }
        }

        uiCoalescer?.schedule()
    }

    // MARK: - System Observers

    private func setupSystemObservers() {
        for token in workspaceObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObserverTokens.removeAll()

        // App activation observation
        let actToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let pid = app?.processIdentifier ?? 0

            Task { @MainActor [weak self] in
                guard let self = self, self.lifecycleState == .ready || self.lifecycleState == .degraded else { return }
                let focusEvent = FocusEvent(
                    type: .frontmostChanged,
                    bundleIdentifier: bundleID,
                    processIdentifier: pid
                )
                await self.eventBus.publish(focusEvent: focusEvent)
            }
        }
        workspaceObserverTokens.append(actToken)

        // Sleep & Wake
        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.lifecycleState == .ready || self.lifecycleState == .degraded else { return }
                logger.info("Mac woke from sleep; reconciling process states...")
                await self.sessionManager?.reconcileOrphanedSessions()
                await self.refreshUIState()
            }
        }
        workspaceObserverTokens.append(wakeToken)

        // Background active agent discovery (every 10s)
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                guard let self = self else { break }
                let isOperational = await MainActor.run { self.lifecycleState == .ready || self.lifecycleState == .degraded }
                guard isOperational else { break }
                await self.refreshUIState()
            }
        }
    }

    private func setupGlobalHotkeys() {
        if let existing = globalHotkeyMonitor {
            NSEvent.removeMonitor(existing)
            globalHotkeyMonitor = nil
        }

        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .option])
            if flags == [.command, .option] {
                if event.keyCode == 48 || event.keyCode == 0 { // Tab or 'A'
                    Task { @MainActor [weak self] in
                        guard let self = self, self.lifecycleState == .ready || self.lifecycleState == .degraded else { return }
                        self.focusMostRecentAgent()
                    }
                }
            }
        }
    }

    public func focusMostRecentAgent() {
        Task {
            if let recent = await sessionManager?.getRecentSessions(limit: 1).first {
                _ = await focusController?.manualFocusSession(recent)
            }
        }
    }

    // MARK: - UI State Refresh

    /// Lightweight UI state update executing on the hot event path without filesystem discovery or process execution
    public func updateMinimalUIState() async {
        guard lifecycleState == .ready || lifecycleState == .degraded else { return }

        let active = await sessionManager.getActiveSessions()
        let all = await sessionManager.getAllSessions()
        let recent = await sessionManager.getRecentSessions(limit: 10)
        let queue = await attentionArbiter.pendingRequests()
        let timeline = await timelineTracker.allRecentEntries(limit: 50)

        self.activeSessions = active
        self.allSessions = all
        self.attentionQueue = queue
        self.timelineEntries = timeline

        // Synchronize published properties of dashboardViewModel for instant reactive UI re-renders
        dashboardViewModel.activeSessions = active
        dashboardViewModel.allSessions = all
        dashboardViewModel.attentionQueue = queue
        dashboardViewModel.timelineEntries = timeline
        dashboardViewModel.config = configuration
        dashboardViewModel.focusLock = focusLock
        dashboardViewModel.isDatabaseReady = isDatabaseReady
        dashboardViewModel.isStorageDurable = isStorageDurable
        dashboardViewModel.storageRecoveryNotice = storageRecoveryNotice
        dashboardViewModel.isIPCReady = isIPCReady

        if !isHeadless {
            menuBarController.updateState(
                activeSessions: active,
                recentSessions: recent,
                attentionQueue: queue,
                focusLock: focusLock
            )
        }
    }

    /// Authoritative reconciliation and provider health check run periodically, on startup, or upon manual user request
    public func refreshUIState() async {
        guard lifecycleState == .ready || lifecycleState == .degraded else { return }
        guard !isPerformingMaintenance else { return }
        isPerformingMaintenance = true
        defer { isPerformingMaintenance = false }

        // 1. Storage maintenance: prune completed sessions older than 30 days while retaining recent 50
        if let repo = sessionRepository {
            _ = try? await repo.pruneCompletedSessions(olderThanDays: 30, keepMinCount: 50)
        }

        // 2. Proactively scan for unobserved running agent sessions across providers
        let discovered = await providerRegistry.discoverAllActiveSessions()
        if !discovered.isEmpty {
            await sessionManager.mergeDiscoveredSessions(discovered)
        }

        // 3. Provider health checks & process probes
        let healths = await providerRegistry.checkAllHealth()
        let perms = await PermissionManager.shared.currentStatus()

        self.providerHealths = healths
        self.permissionStatus = perms
        dashboardViewModel.providerHealths = healths
        dashboardViewModel.permissionStatus = perms

        // 4. Update observable UI state
        await updateMinimalUIState()
    }
}

// MARK: - MenuBarActionDelegate

extension FlowbackService: MenuBarActionDelegate {
    public func didRequestRefresh() {
        Task { [weak self] in
            await self?.refreshUIState()
        }
    }

    public func didSelectFocus(sessionID: AgentSessionID) {
        Task {
            if let session = await sessionManager.getSession(id: sessionID) {
                _ = await focusController.manualFocusSession(session)
            }
        }
    }

    public func didToggleFocusLock(minutes: Int?) {
        if let mins = minutes {
            let exp = Date().addingTimeInterval(TimeInterval(mins * 60))
            focusLock = FocusLockState(isActive: true, expiresAt: exp, label: "\(mins) min")
        } else {
            focusLock = FocusLockState(isActive: false)
        }
        ipcHandler?.setFocusLock(focusLock)
        Task { await refreshUIState() }
    }

    public func didRequestOpenDashboard() {
        openDashboardWindow(tab: .overview)
    }

    public func didRequestOpenSettings() {
        openDashboardWindow(tab: .settings)
    }

    public func didRequestOpenDiagnostics() {
        openDashboardWindow(tab: .diagnostics)
    }

    public func didRequestQuit() {
        requestQuit()
    }
}

// MARK: - NotificationActionDelegate

extension FlowbackService: NotificationActionDelegate {
    public func didRequestFocus(sessionID: AgentSessionID) async {
        if let session = await sessionManager.getSession(id: sessionID) {
            _ = await focusController.manualFocusSession(session)
        }
    }

    public func didRequestReview() async {
        openDashboardWindow(tab: .overview)
    }
}

// MARK: - Dashboard Window Management & NSWindowDelegate

extension FlowbackService: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win === dashboardWindow {
            dashboardWindow = nil
            logger.info("Dashboard window closed. Flowback continues running in menu bar.")
        }
    }

    public func openDashboardWindow(tab: DashboardTab = .overview) {
        dashboardViewModel.selectedTab = tab
        setupStandardMainMenu()

        if let existing = dashboardWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        // Initialize dashboardViewModel with current state
        dashboardViewModel.activeSessions = activeSessions
        dashboardViewModel.allSessions = allSessions
        dashboardViewModel.attentionQueue = attentionQueue
        dashboardViewModel.providerHealths = providerHealths
        dashboardViewModel.permissionStatus = permissionStatus
        dashboardViewModel.timelineEntries = timelineEntries
        dashboardViewModel.config = configuration
        dashboardViewModel.focusLock = focusLock
        dashboardViewModel.isDatabaseReady = isDatabaseReady
        dashboardViewModel.isStorageDurable = isStorageDurable
        dashboardViewModel.storageRecoveryNotice = storageRecoveryNotice
        dashboardViewModel.isIPCReady = isIPCReady

        let dashboardView = DashboardView(
            viewModel: dashboardViewModel,
            onFocusSession: { [weak self] session in
                Task { [weak self] in
                    _ = await self?.focusController.manualFocusSession(session)
                }
            },
            onSaveConfig: { [weak self] updated in
                Task { [weak self] in
                    do {
                        try await self?.settingsRepository.saveConfiguration(updated)
                        self?.configuration = updated
                        self?.dashboardViewModel.config = updated
                        logger.info("Configuration successfully updated and persisted.")
                    } catch {
                        logger.error("Failed to persist updated configuration: \(error.localizedDescription)")
                    }
                }
            },
            onRepairAntigravity: { [weak self] in
                Task { [weak self] in
                    let provider = AntigravityProvider()
                    try? await provider.installIntegration()
                    await self?.refreshUIState()
                }
            },
            onTestFocus: { [weak self] in
                Task { [weak self] in
                    _ = await self?.ipcHandler.handleRequest(IPCRequest(command: "test-focus"))
                    await self?.refreshUIState()
                }
            },
            onTestNotification: { [weak self] in
                Task { [weak self] in
                    await self?.notificationManager.sendAggregatedNotification(
                        title: "Flowback Test Alert",
                        body: "Notification and focus routing verification succeeded."
                    )
                }
            },
            onRefresh: { [weak self] in
                Task { [weak self] in
                    await self?.refreshUIState()
                }
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.setFrameAutosaveName("FlowbackDashboardWindow")
        window.title = "Flowback — AI Focus & Context Manager"
        window.contentView = NSHostingView(rootView: dashboardView)
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - Native macOS Standard Main Menu

    private func setupStandardMainMenu() {
        guard NSApp.mainMenu == nil else { return }
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Flowback")
        appMenu.addItem(withTitle: "About Flowback", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let hideItem = NSMenuItem(title: "Hide Flowback", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Flowback", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit Menu (Enables ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z in text fields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window Menu (Enables ⌘W to close companion window)
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(closeItem)
        let minimizeItem = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
