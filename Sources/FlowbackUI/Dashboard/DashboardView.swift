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
    
    @StateObject private var viewModel = DashboardViewModel()
    
    public init(
        activeSessions: Binding<[AgentSession]>,
        allSessions: Binding<[AgentSession]>,
        attentionQueue: Binding<[AttentionRequest]>,
        timelineEntries: Binding<[TimelineEntry]>,
        providerHealths: Binding<[ProviderHealth]>,
        permissionStatusBinding: Binding<PermissionStatus>,
        config: Binding<PolicyConfiguration>,
        focusLock: Binding<FocusLockState>,
        onFocusSession: @escaping (AgentSession) -> Void,
        onSaveConfig: @escaping (PolicyConfiguration) -> Void,
        onRepairAntigravity: @escaping () -> Void,
        onTestFocus: @escaping () -> Void,
        onTestNotification: @escaping () -> Void
    ) {
        self._activeSessions = activeSessions
        self._allSessions = allSessions
        self._attentionQueue = attentionQueue
        self._timelineEntries = timelineEntries
        self._providerHealths = providerHealths
        self._permissionStatus = permissionStatusBinding
        self._config = config
        self._focusLock = focusLock
        self.onFocusSession = onFocusSession
        self.onSaveConfig = onSaveConfig
        self.onRepairAntigravity = onRepairAntigravity
        self.onTestFocus = onTestFocus
        self.onTestNotification = onTestNotification
    }
    
    public var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: $viewModel.selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
            switch viewModel.selectedTab {
            case .overview:
                OverviewView(
                    activeSessions: $activeSessions,
                    attentionQueue: $attentionQueue,
                    focusLock: $focusLock,
                    onFocusSession: onFocusSession
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
        .frame(minWidth: 800, minHeight: 550)
    }
}
