import SwiftUI
import FlowbackCore

public enum AgentFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
    case failed = "Failed"
}

public final class AgentsViewModel: ObservableObject {
    @Published public var filter: AgentFilter = .all
    @Published public var searchText: String = ""
    public init() {}
}

public struct AgentsView: View {
    @Environment(\.colorScheme) private var colorScheme
    public let sessions: [AgentSession]
    public var onFocusSession: (AgentSession) -> Void

    @StateObject private var viewModel = AgentsViewModel()

    public init(sessions: [AgentSession], onFocusSession: @escaping (AgentSession) -> Void) {
        self.sessions = sessions
        self.onFocusSession = onFocusSession
    }

    public var filteredSessions: [AgentSession] {
        let baseSessions: [AgentSession]
        switch viewModel.filter {
        case .all: baseSessions = sessions
        case .active: baseSessions = sessions.filter { $0.state.isActive }
        case .completed: baseSessions = sessions.filter { $0.state == .completed }
        case .failed: baseSessions = sessions.filter { $0.state == .failed }
        }

        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return baseSessions }

        return baseSessions.filter { session in
            session.displayTitle.lowercased().contains(query) ||
            session.projectName.lowercased().contains(query) ||
            session.providerDisplayName.lowercased().contains(query) ||
            (session.workspace?.lowercased().contains(query) ?? false) ||
            (session.taskSummary?.lowercased().contains(query) ?? false)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                    HStack(spacing: FlowbackSpacing.xs) {
                        Text("Agent Sessions")
                            .font(.title2.bold())
                        Text("\(filteredSessions.count) of \(sessions.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(FlowbackRadius.badge)
                    }
                    Text("Multi-agent observation across active and background workspaces")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(AgentFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .accessibilityIdentifier("agent-filter-picker")
            }
            .padding(.horizontal, FlowbackSpacing.xl)
            .padding(.top, FlowbackSpacing.lg)

            // Search bar
            HStack(spacing: FlowbackSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions, projects, or workspaces...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("agent-search-field")
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("agent-search-clear-button")
                }
            }
            .padding(.horizontal, FlowbackSpacing.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                    .fill(ThemeTokens.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                    .strokeBorder(ThemeTokens.cardBorder(for: colorScheme), lineWidth: ThemeTokens.cardBorderWidth)
            )
            .padding(.horizontal, FlowbackSpacing.xl)

            if filteredSessions.isEmpty {
                Spacer()
                if !viewModel.searchText.isEmpty {
                    FlowbackEmptyState(
                        icon: "magnifyingglass",
                        title: "No matching sessions",
                        message: "No agent sessions match '\(viewModel.searchText)'. Check spelling or clear your search query.",
                        actionTitle: "Clear Search",
                        onAction: { viewModel.searchText = "" }
                    )
                    .accessibilityIdentifier("agents-empty-state")
                } else if viewModel.filter != .all {
                    FlowbackEmptyState(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "No \(viewModel.filter.rawValue) sessions",
                        message: "There are currently no sessions matching the '\(viewModel.filter.rawValue)' filter.",
                        actionTitle: "Show All Sessions",
                        onAction: { viewModel.filter = .all }
                    )
                    .accessibilityIdentifier("agents-empty-state")
                } else {
                    FlowbackEmptyState(
                        icon: "cpu",
                        title: "No agent sessions found",
                        message: "Flowback will automatically detect background agent activity."
                    )
                    .accessibilityIdentifier("agents-empty-state")
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: FlowbackSpacing.sm) {
                        ForEach(filteredSessions) { session in
                            HStack(spacing: FlowbackSpacing.md) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                                        .fill(ThemeTokens.iconTileFill(tint: .accentColor, scheme: colorScheme))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: ThemeTokens.statusIcon(for: session.state))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline, spacing: FlowbackSpacing.xs) {
                                        Text(session.displayTitle)
                                            .font(.headline)
                                            .lineLimit(1)

                                        if sessions.filter({ $0.projectName == session.projectName }).count > 1 {
                                            Text("Shared Repo")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.15))
                                                .foregroundColor(.orange)
                                                .cornerRadius(FlowbackRadius.badge)
                                        }
                                    }

                                    HStack(spacing: FlowbackSpacing.xs) {
                                        Text(session.providerDisplayName)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text(session.projectName)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text(session.focusCapability.displayLabel)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(session.focusCapability == .windowOnly ? Color.gray.opacity(0.15) : Color.blue.opacity(0.15))
                                            .foregroundColor(session.focusCapability == .windowOnly ? .secondary : .accentColor)
                                            .cornerRadius(FlowbackRadius.badge)
                                    }

                                    if let summary = session.taskSummary, !summary.isEmpty {
                                        Text(summary)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    HStack(spacing: FlowbackSpacing.sm) {
                                        if let origin = session.originContext {
                                            Text("Origin: \(origin.displayLabel)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Text("Duration: \(session.formattedDuration)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                StatusBadge(state: session.state)

                                Button("Focus") {
                                    onFocusSession(session)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .accessibilityLabel("Focus session \(session.displayTitle)")
                                .accessibilityIdentifier("agent-focus-\(session.id.rawValue)")
                            }
                            .padding(FlowbackSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: FlowbackRadius.card, style: .continuous)
                                    .fill(ThemeTokens.cardFill(for: colorScheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: FlowbackRadius.card, style: .continuous)
                                    .strokeBorder(ThemeTokens.cardBorder(for: colorScheme), lineWidth: ThemeTokens.cardBorderWidth)
                            )
                        }
                    }
                    .padding(.horizontal, FlowbackSpacing.xl)
                    .padding(.bottom, FlowbackSpacing.xl)
                }
            }
        }
    }
}
