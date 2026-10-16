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
public final class FlowbackService: ObservableObject, MenuBarActionDelegate, NotificationActionDelegate {
    public static let shared = FlowbackService()
    
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
    
    // Observable UI state
    @Published public var activeSessions: [AgentSession] = []
    @Published public var allSessions: [AgentSession] = []
    @Published public var attentionQueue: [AttentionRequest] = []
    @Published public var timelineEntries: [TimelineEntry] = []
    @Published public var providerHealths: [ProviderHealth] = []
    @Published public var permissionStatus: PermissionStatus = PermissionStatus()
    @Published public var configuration: PolicyConfiguration = .default
    @Published public var focusLock: FocusLockState = FocusLockState()
    
    // Dashboard window & navigation model
    private var dashboardWindow: NSWindow?
    private let dashboardViewModel = DashboardViewModel()
    
    public init() {}
    
    public func start() async {
        logger.info("Starting Flowback Universal Context & Focus Manager...")
        
        // 1. Storage setup & corruption recovery
        let dbPath = ("~/.flowback/flowback.sqlite" as NSString).expandingTildeInPath
        self.database = await RecoveryManager.shared.initializeStorage(path: dbPath)
        self.sessionRepository = SessionRepository(db: database)
        self.settingsRepository = SettingsRepository(db: database)
        self.eventRepository = EventRepository(db: database)
        
        // 2. Load preferences
        self.configuration = await settingsRepository.loadConfiguration()
        
        // 3. Coordinate core subsystems
        self.sessionManager = SessionManager(timeline: timelineTracker, storageDelegate: sessionRepository)
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
        await providerRegistry.register(provider: GeminiCLIProvider())
        await providerRegistry.register(provider: AiderProvider())
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
        
        // 7. Setup IPC Server
        self.ipcHandler = IPCHandler(
            eventBus: eventBus,
            sessionManager: sessionManager,
            focusController: focusController,
            providerRegistry: providerRegistry,
            settingsRepo: settingsRepository,
            focusLock: focusLock
        )
        self.socketServer = UnixSocketServer(delegate: ipcHandler)
        try? socketServer.start()
        
        // 8. Observe Events and System changes
        startEventLoops()
        setupSystemObservers()
        setupGlobalHotkeys()
        
        // 9. Initial state refresh
        await refreshUIState()
        
        logger.info("Flowback initialized and monitoring.")
    }
    
    // MARK: - Event Loops
    
    private func startEventLoops() {
        // Observe AgentEvents
        Task { [weak self] in
            guard let self = self else { return }
            for await event in await self.eventBus.agentEvents() {
                await self.handleAgentEvent(event)
            }
        }
    }
    
    private func handleAgentEvent(_ event: AgentEvent) async {
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
                title: "\(session.providerID.rawValue) \(session.state.displayName)",
                message: "\(session.projectName) finished with \(session.state.rawValue)",
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
                    title: "\(session.providerID.rawValue) Finished",
                    body: "\(session.projectName) • \(decision.explanation)"
                )
            }
        }
        
        await refreshUIState()
    }
    
    // MARK: - System Observers
    
    private func setupSystemObservers() {
        // App activation observation
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let focusEvent = FocusEvent(
                type: .frontmostChanged,
                bundleIdentifier: app.bundleIdentifier,
                processIdentifier: app.processIdentifier
            )
            Task { [weak self] in
                await self?.eventBus.publish(focusEvent: focusEvent)
            }
        }
        
        // Sleep & Wake
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            logger.info("Mac woke from sleep; reconciling process states...")
            Task { [weak self] in
                await self?.sessionManager.reconcileOrphanedSessions()
                await self?.refreshUIState()
            }
        }
        
        // Background active agent discovery (every 10s)
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self = self else { break }
                await self.refreshUIState()
            }
        }
    }
    
    private func setupGlobalHotkeys() {
        // Monitor global key events for ⌥⌘Tab and ⌥⌘A
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .option])
            if flags == [.command, .option] {
                if event.keyCode == 48 { // Tab
                    Task { @MainActor [weak self] in
                        self?.focusMostRecentAgent()
                    }
                } else if event.keyCode == 0 { // 'A'
                    Task { @MainActor [weak self] in
                        self?.focusMostRecentAgent()
                    }
                }
            }
        }
    }
    
    public func focusMostRecentAgent() {
        Task {
            if let recent = await sessionManager.getRecentSessions(limit: 1).first {
                _ = await focusController.manualFocusSession(recent)
            }
        }
    }
    
    // MARK: - UI State Refresh
    
    public func refreshUIState() async {
        // Proactively scan for live running agent sessions across providers
        let discovered = await providerRegistry.discoverAllActiveSessions()
        if !discovered.isEmpty {
            await sessionManager.mergeDiscoveredSessions(discovered)
        }
        
        let active = await sessionManager.getActiveSessions()
        let all = await sessionManager.getAllSessions()
        let recent = await sessionManager.getRecentSessions(limit: 10)
        let queue = await attentionArbiter.pendingRequests()
        let healths = await providerRegistry.checkAllHealth()
        let perms = await PermissionManager.shared.currentStatus()
        let timeline = await timelineTracker.allRecentEntries(limit: 50)
        
        self.activeSessions = active
        self.allSessions = all
        self.attentionQueue = queue
        self.providerHealths = healths
        self.permissionStatus = perms
        self.timelineEntries = timeline
        
        if !isHeadless {
            menuBarController.updateState(
                activeSessions: active,
                recentSessions: recent,
                attentionQueue: queue,
                focusLock: focusLock
            )
        }
    }
    
    // MARK: - MenuBarActionDelegate
    
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
        ipcHandler.setFocusLock(focusLock)
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
        socketServer?.stop()
        Task {
            await self.database?.close()
            NSApplication.shared.terminate(nil)
        }
    }
    
    // MARK: - NotificationActionDelegate
    
    public func didRequestFocus(sessionID: AgentSessionID) async {
        if let session = await sessionManager.getSession(id: sessionID) {
            _ = await focusController.manualFocusSession(session)
        }
    }
    
    public func didRequestReview() async {
        openDashboardWindow(tab: .overview)
    }
    
    // MARK: - Dashboard Window Management
    
    public func openDashboardWindow(tab: DashboardTab = .overview) {
        dashboardViewModel.selectedTab = tab
        setupStandardMainMenu()
        
        if let existing = dashboardWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let dashboardView = DashboardView(
            viewModel: dashboardViewModel,
            activeSessions: Binding(get: { self.activeSessions }, set: { self.activeSessions = $0 }),
            allSessions: Binding(get: { self.allSessions }, set: { self.allSessions = $0 }),
            attentionQueue: Binding(get: { self.attentionQueue }, set: { self.attentionQueue = $0 }),
            timelineEntries: Binding(get: { self.timelineEntries }, set: { self.timelineEntries = $0 }),
            providerHealths: Binding(get: { self.providerHealths }, set: { self.providerHealths = $0 }),
            permissionStatusBinding: Binding(get: { self.permissionStatus }, set: { self.permissionStatus = $0 }),
            config: Binding(get: { self.configuration }, set: { self.configuration = $0 }),
            focusLock: Binding(get: { self.focusLock }, set: { self.focusLock = $0 }),
            onFocusSession: { [weak self] session in
                Task { [weak self] in
                    _ = await self?.focusController.manualFocusSession(session)
                }
            },
            onSaveConfig: { [weak self] updated in
                Task { [weak self] in
                    try? await self?.settingsRepository.saveConfiguration(updated)
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
