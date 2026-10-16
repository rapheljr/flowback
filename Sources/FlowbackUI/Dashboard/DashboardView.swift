import SwiftUI
import FlowbackCore
import FlowbackProviders

public enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case agents = "Agents"
    case timeline = "Timeline"
    case applications = "Applications"
    case diagnostics = "Diagnostics"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .agents: return "cpu"
        case .timeline: return "clock.arrow.circlepath"
        case .applications: return "macwindow"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
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
        }
    }
}

public final class DashboardViewModel: ObservableObject {
    @Published public var selectedTab: DashboardTab
    
    public init(selectedTab: DashboardTab = .overview) {
        self.selectedTab = selectedTab
    }
}

public struct DashboardView: View {
    @Binding var activeSessions: [AgentSession]
    @Binding var allSessions: [AgentSession]
    @Binding var attentionQueue: [AttentionRequest]
    @Binding var timelineEntries: [TimelineEntry]
    @Binding var providerHealths: [ProviderHealth]
    @Binding var permissionStatus: PermissionStatus
    @Binding var config: PolicyConfiguration
    @Binding var focusLock: FocusLockState
    
    public var onFocusSession: (AgentSession) -> Void
    public var onSaveConfig: (PolicyConfiguration) -> Void
    public var onRepairAntigravity: () -> Void
    public var onTestFocus: () -> Void
    public var onTestNotification: () -> Void
    public var onRefresh: () -> Void
    public var isDatabaseReady: Bool = true
    public var isStorageDurable: Bool = true
    public var storageRecoveryNotice: String? = nil
    public var isIPCReady: Bool = true
    
    @ObservedObject public var viewModel: DashboardViewModel
    
    public init(
        viewModel: DashboardViewModel = DashboardViewModel(),
        activeSessions: Binding<[AgentSession]>,
        allSessions: Binding<[AgentSession]>,
        attentionQueue: Binding<[AttentionRequest]>,
        timelineEntries: Binding<[TimelineEntry]>,
        providerHealths: Binding<[ProviderHealth]>,
        permissionStatusBinding: Binding<PermissionStatus>,
        config: Binding<PolicyConfiguration>,
        focusLock: Binding<FocusLockState>,
        isDatabaseReady: Bool = true,
        isStorageDurable: Bool = true,
        storageRecoveryNotice: String? = nil,
        isIPCReady: Bool = true,
        onFocusSession: @escaping (AgentSession) -> Void,
        onSaveConfig: @escaping (PolicyConfiguration) -> Void,
        onRepairAntigravity: @escaping () -> Void,
        onTestFocus: @escaping () -> Void,
        onTestNotification: @escaping () -> Void,
        onRefresh: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self._activeSessions = activeSessions
        self._allSessions = allSessions
        self._attentionQueue = attentionQueue
        self._timelineEntries = timelineEntries
        self._providerHealths = providerHealths
        self._permissionStatus = permissionStatusBinding
        self._config = config
        self._focusLock = focusLock
        self.isDatabaseReady = isDatabaseReady
        self.isDatabaseReady = isDatabaseReady
        self.isStorageDurable = isStorageDurable
        self.storageRecoveryNotice = storageRecoveryNotice
        self.isIPCReady = isIPCReady
        self.onFocusSession = onFocusSession
        self.onSaveConfig = onSaveConfig
        self.onRepairAntigravity = onRepairAntigravity
        self.onTestFocus = onTestFocus
        self.onTestNotification = onTestNotification
        self.onRefresh = onRefresh
    }
    
    public var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $viewModel.selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
                .accessibilityIdentifier("dashboard-sidebar-tab-\(tab.rawValue.lowercased())")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
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
                            activeSessions: $activeSessions,
                            attentionQueue: $attentionQueue,
                            focusLock: $focusLock,
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
                            protectedApps: $config.protectedApplications
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
                            config: $config,
                            onSave: onSaveConfig
                        )
                    }
                }
            }
            .navigationTitle(viewModel.selectedTab.rawValue)
            .navigationSubtitle(viewModel.selectedTab.subtitle)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: onRefresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Scan and refresh active agent sessions (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityIdentifier("toolbar-refresh-button")
                }
            }
            .background {
                Group {
                    Button("") { viewModel.selectedTab = .overview }.keyboardShortcut("1", modifiers: .command).hidden()
                    Button("") { viewModel.selectedTab = .agents }.keyboardShortcut("2", modifiers: .command).hidden()
                    Button("") { viewModel.selectedTab = .timeline }.keyboardShortcut("3", modifiers: .command).hidden()
                    Button("") { viewModel.selectedTab = .applications }.keyboardShortcut("4", modifiers: .command).hidden()
                    Button("") { viewModel.selectedTab = .diagnostics }.keyboardShortcut("5", modifiers: .command).hidden()
                    Button("") { viewModel.selectedTab = .settings }.keyboardShortcut("6", modifiers: .command).hidden()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 550)
    }
}
