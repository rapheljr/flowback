import SwiftUI
import FlowbackCore
import FlowbackProviders

public enum DashboardTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case agents = "Agents"
    case timeline = "Timeline"
    case applications = "Applications"
    case diagnostics = "Diagnostics"
    case settings = "Settings"
    case advanced = "Advanced"
    case whatsNew = "What's New"
    case support = "Support"
    case about = "About"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .agents: return "cpu"
        case .timeline: return "clock.arrow.circlepath"
        case .applications: return "macwindow"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        case .advanced: return "wrench.and.screwdriver"
        case .whatsNew: return "sparkles"
        case .support: return "heart.fill"
        case .about: return "info.circle"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .overview: return "Live agent activity & attention"
        case .agents: return "Active and completed agent sessions"
        case .timeline: return "Orchestration decision history"
        case .applications: return "Focus protection rules"
        case .diagnostics: return "System capabilities & integrations"
        case .settings: return "Focus policy configuration"
        case .advanced: return "Specialized orchestration controls & configuration"
        case .whatsNew: return "Recent release highlights and improvements"
        case .support: return "Support development, documentation & diagnostics export"
        case .about: return "App details, licensing & project resources"
        }
    }

    public var accessibilityKey: String {
        rawValue.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "'", with: "")
    }

    public static let workspaceTabs: [DashboardTab] = [
        .overview,
        .agents,
        .applications,
        .timeline,
        .diagnostics
    ]

    public static let preferencesAndHelpTabs: [DashboardTab] = [
        .settings,
        .advanced,
        .whatsNew,
        .support,
        .about
    ]
}

public final class DashboardViewModel: ObservableObject {
    @Published public var selectedTab: DashboardTab {
        didSet {
            guard selectedTab != oldValue else { return }
            if !isTraversingHistory {
                if historyIndex + 1 < navigationHistory.count {
                    navigationHistory.removeSubrange((historyIndex + 1)..<navigationHistory.count)
                }
                navigationHistory.append(selectedTab)
                historyIndex = navigationHistory.count - 1
            }
        }
    }
    @Published public private(set) var navigationHistory: [DashboardTab]
    @Published public private(set) var historyIndex: Int
    private var isTraversingHistory: Bool = false

    public var canGoBack: Bool {
        historyIndex > 0
    }

    public var canGoForward: Bool {
        historyIndex < navigationHistory.count - 1
    }

    public func goBack() {
        guard canGoBack else { return }
        isTraversingHistory = true
        historyIndex -= 1
        selectedTab = navigationHistory[historyIndex]
        isTraversingHistory = false
    }

    public func goForward() {
        guard canGoForward else { return }
        isTraversingHistory = true
        historyIndex += 1
        selectedTab = navigationHistory[historyIndex]
        isTraversingHistory = false
    }

    public func navigateTo(_ tab: DashboardTab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
    }

    @Published public var columnVisibility: NavigationSplitViewVisibility = .all

    public var sidebarShown: Bool { columnVisibility != .detailOnly }

    public func toggleSidebar() {
        let next: NavigationSplitViewVisibility = sidebarShown ? .detailOnly : .all
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            columnVisibility = next
        } else {
            withAnimation { columnVisibility = next }
        }
    }

    @Published public var activeSessions: [AgentSession] = []
    @Published public var allSessions: [AgentSession] = []
    @Published public var attentionQueue: [AttentionRequest] = []
    @Published public var timelineEntries: [TimelineEntry] = []
    @Published public var providerHealths: [ProviderHealth] = []
    @Published public var permissionStatus: PermissionStatus = PermissionStatus()
    @Published public var config: PolicyConfiguration = .default
    @Published public var focusLock: FocusLockState = FocusLockState()
    @Published public var isDatabaseReady: Bool = true
    @Published public var isStorageDurable: Bool = true
    @Published public var storageRecoveryNotice: String?
    @Published public var isIPCReady: Bool = true
    @Published public var feedbackMessage: String?
    
    public init(
        selectedTab: DashboardTab = .overview,
        activeSessions: [AgentSession] = [],
        allSessions: [AgentSession] = [],
        attentionQueue: [AttentionRequest] = [],
        timelineEntries: [TimelineEntry] = [],
        providerHealths: [ProviderHealth] = [],
        permissionStatus: PermissionStatus = PermissionStatus(),
        config: PolicyConfiguration = .default,
        focusLock: FocusLockState = FocusLockState(),
        isDatabaseReady: Bool = true,
        isStorageDurable: Bool = true,
        storageRecoveryNotice: String? = nil,
        isIPCReady: Bool = true
    ) {
        self.selectedTab = selectedTab
        self.navigationHistory = [selectedTab]
        self.historyIndex = 0
        self.activeSessions = activeSessions
        self.allSessions = allSessions
        self.attentionQueue = attentionQueue
        self.timelineEntries = timelineEntries
        self.providerHealths = providerHealths
        self.permissionStatus = permissionStatus
        self.config = config
        self.focusLock = focusLock
        self.isDatabaseReady = isDatabaseReady
        self.isStorageDurable = isStorageDurable
        self.storageRecoveryNotice = storageRecoveryNotice
        self.isIPCReady = isIPCReady
    }
}

public struct DashboardView: View {
    @ObservedObject public var viewModel: DashboardViewModel
    
    public var onFocusSession: (AgentSession) -> Void
    public var onSaveConfig: (PolicyConfiguration) -> Void
    public var onUpdateFocusLock: ((FocusLockState) -> Void)?
    public var onRepairAntigravity: () -> Void
    public var onTestFocus: () -> Void
    public var onTestNotification: () -> Void
    public var onRefresh: () -> Void
    
    private var externalActiveSessions: Binding<[AgentSession]>?
    private var externalAllSessions: Binding<[AgentSession]>?
    private var externalAttentionQueue: Binding<[AttentionRequest]>?
    private var externalTimelineEntries: Binding<[TimelineEntry]>?
    private var externalProviderHealths: Binding<[ProviderHealth]>?
    private var externalPermissionStatus: Binding<PermissionStatus>?
    private var externalConfig: Binding<PolicyConfiguration>?
    private var externalFocusLock: Binding<FocusLockState>?
    
    var activeSessionsBinding: Binding<[AgentSession]> {
        externalActiveSessions ?? $viewModel.activeSessions
    }
    var attentionQueueBinding: Binding<[AttentionRequest]> {
        externalAttentionQueue ?? $viewModel.attentionQueue
    }
    var configBinding: Binding<PolicyConfiguration> {
        externalConfig ?? $viewModel.config
    }
    var focusLockBinding: Binding<FocusLockState> {
        externalFocusLock ?? $viewModel.focusLock
    }
    
    var activeSessions: [AgentSession] {
        externalActiveSessions?.wrappedValue ?? viewModel.activeSessions
    }
    var allSessions: [AgentSession] {
        externalAllSessions?.wrappedValue ?? viewModel.allSessions
    }
    var attentionQueue: [AttentionRequest] {
        externalAttentionQueue?.wrappedValue ?? viewModel.attentionQueue
    }
    var timelineEntries: [TimelineEntry] {
        externalTimelineEntries?.wrappedValue ?? viewModel.timelineEntries
    }
    var providerHealths: [ProviderHealth] {
        externalProviderHealths?.wrappedValue ?? viewModel.providerHealths
    }
    var permissionStatus: PermissionStatus {
        externalPermissionStatus?.wrappedValue ?? viewModel.permissionStatus
    }
    var isDatabaseReady: Bool { viewModel.isDatabaseReady }
    var isStorageDurable: Bool { viewModel.isStorageDurable }
    var storageRecoveryNotice: String? { viewModel.storageRecoveryNotice }
    var isIPCReady: Bool { viewModel.isIPCReady }
    
    public init(
        viewModel: DashboardViewModel = DashboardViewModel(),
        activeSessions: Binding<[AgentSession]>? = nil,
        allSessions: Binding<[AgentSession]>? = nil,
        attentionQueue: Binding<[AttentionRequest]>? = nil,
        timelineEntries: Binding<[TimelineEntry]>? = nil,
        providerHealths: Binding<[ProviderHealth]>? = nil,
        permissionStatusBinding: Binding<PermissionStatus>? = nil,
        config: Binding<PolicyConfiguration>? = nil,
        focusLock: Binding<FocusLockState>? = nil,
        isDatabaseReady: Bool = true,
        isStorageDurable: Bool = true,
        storageRecoveryNotice: String? = nil,
        isIPCReady: Bool = true,
        onFocusSession: @escaping (AgentSession) -> Void,
        onSaveConfig: @escaping (PolicyConfiguration) -> Void,
        onUpdateFocusLock: ((FocusLockState) -> Void)? = nil,
        onRepairAntigravity: @escaping () -> Void,
        onTestFocus: @escaping () -> Void,
        onTestNotification: @escaping () -> Void,
        onRefresh: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.externalActiveSessions = activeSessions
        self.externalAllSessions = allSessions
        self.externalAttentionQueue = attentionQueue
        self.externalTimelineEntries = timelineEntries
        self.externalProviderHealths = providerHealths
        self.externalPermissionStatus = permissionStatusBinding
        self.externalConfig = config
        self.externalFocusLock = focusLock
        self.onFocusSession = onFocusSession
        self.onSaveConfig = onSaveConfig
        self.onUpdateFocusLock = onUpdateFocusLock
        self.onRepairAntigravity = onRepairAntigravity
        self.onTestFocus = onTestFocus
        self.onTestNotification = onTestNotification
        self.onRefresh = onRefresh
        self.viewModel.isDatabaseReady = isDatabaseReady
        self.viewModel.isStorageDurable = isStorageDurable
        self.viewModel.storageRecoveryNotice = storageRecoveryNotice
        self.viewModel.isIPCReady = isIPCReady
    }
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            List(selection: $viewModel.selectedTab) {
                Section("Workspace") {
                    ForEach(DashboardTab.workspaceTabs) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.rawValue, systemImage: tab.icon)
                        }
                        .accessibilityIdentifier("dashboard-sidebar-tab-\(tab.accessibilityKey)")
                    }
                }

                Section("Preferences & Help") {
                    ForEach(DashboardTab.preferencesAndHelpTabs) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.rawValue, systemImage: tab.icon)
                        }
                        .accessibilityIdentifier("dashboard-sidebar-tab-\(tab.accessibilityKey)")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if !isStorageDurable {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(storageRecoveryNotice ?? "Operating in transient in-memory database fallback (changes will not persist to disk).")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.15))
                    }

                    Group {
                        switch viewModel.selectedTab {
                        case .overview:
                            OverviewView(
                                activeSessions: activeSessionsBinding,
                                allSessions: allSessions,
                                attentionQueue: attentionQueueBinding,
                                focusLock: Binding(
                                    get: { focusLockBinding.wrappedValue },
                                    set: { newValue in
                                        focusLockBinding.wrappedValue = newValue
                                        onUpdateFocusLock?(newValue)
                                    }
                                ),
                                onFocusSession: onFocusSession,
                                onRefresh: onRefresh
                            )
                        case .agents:
                            AgentsView(
                                sessions: allSessions,
                                onFocusSession: onFocusSession
                            )
                        case .timeline:
                            SessionTimelineView(
                                sessions: allSessions,
                                timelineEntries: timelineEntries
                            )
                        case .applications:
                            ApplicationsView(
                                protectedApps: Binding(
                                    get: { configBinding.wrappedValue.protectedApplications },
                                    set: { newValue in
                                        configBinding.wrappedValue.protectedApplications = newValue
                                        onSaveConfig(configBinding.wrappedValue)
                                    }
                                )
                            )
                        case .diagnostics:
                            DiagnosticsView(
                                providerHealths: providerHealths,
                                permissionStatus: permissionStatus,
                                isDatabaseReady: isDatabaseReady,
                                isStorageDurable: isStorageDurable,
                                storageRecoveryNotice: storageRecoveryNotice,
                                isIPCReady: isIPCReady,
                                onRepairAntigravity: onRepairAntigravity,
                                onTestFocus: onTestFocus,
                                onTestNotification: onTestNotification
                            )
                        case .settings:
                            SettingsView(
                                config: configBinding,
                                onSave: onSaveConfig
                            )
                        case .advanced:
                            AdvancedView(
                                config: configBinding,
                                isStorageDurable: isStorageDurable,
                                isIPCReady: isIPCReady,
                                onSave: onSaveConfig
                            )
                        case .whatsNew:
                            WhatsNewView()
                        case .support:
                            SupportView(
                                diagnosticContext: DiagnosticReportContext(
                                    appVersion: FlowbackVersion.current,
                                    appBuild: FlowbackVersion.currentBuild,
                                    permissionStatus: permissionStatus,
                                    isDatabaseReady: isDatabaseReady,
                                    isStorageDurable: isStorageDurable,
                                    storageNotice: storageRecoveryNotice,
                                    isIPCReady: isIPCReady,
                                    providerHealths: providerHealths,
                                    configuration: configBinding.wrappedValue,
                                    recentTimeline: timelineEntries
                                ),
                                onNavigateToDiagnostics: {
                                    viewModel.selectedTab = .diagnostics
                                }
                            )
                        case .about:
                            AboutView(
                                appVersion: FlowbackVersion.current,
                                buildNumber: FlowbackVersion.currentBuild,
                                onNavigateToWhatsNew: {
                                    viewModel.selectedTab = .whatsNew
                                }
                            )
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                let title = viewModel.sidebarShown ? "Hide Sidebar" : "Show Sidebar"
                Button(action: { viewModel.toggleSidebar() }) {
                    Label(title, systemImage: "sidebar.left")
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help(title)
                .accessibilityIdentifier("toolbar-sidebar-toggle-button")
            }

            ToolbarItemGroup(placement: .navigation) {
                Button(action: { viewModel.goBack() }) {
                    Label("Back", systemImage: "chevron.backward")
                }
                .disabled(!viewModel.canGoBack)
                .help("Back (⌘[)")
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityIdentifier("toolbar-back-button")

                Button(action: { viewModel.goForward() }) {
                    Label("Forward", systemImage: "chevron.forward")
                }
                .disabled(!viewModel.canGoForward)
                .help("Forward (⌘])")
                .keyboardShortcut("]", modifiers: .command)
                .accessibilityIdentifier("toolbar-forward-button")
            }
        }
        .background {
            Group {
                Button("") { onRefresh() }.keyboardShortcut("r", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .overview }.keyboardShortcut("1", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .agents }.keyboardShortcut("2", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .applications }.keyboardShortcut("3", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .timeline }.keyboardShortcut("4", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .diagnostics }.keyboardShortcut("5", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .settings }.keyboardShortcut("6", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .advanced }.keyboardShortcut("7", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .whatsNew }.keyboardShortcut("8", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .support }.keyboardShortcut("9", modifiers: .command).hidden()
                Button("") { viewModel.selectedTab = .about }.keyboardShortcut("0", modifiers: .command).hidden()
            }
        }
        .frame(minWidth: 800, minHeight: 550)
    }
}
