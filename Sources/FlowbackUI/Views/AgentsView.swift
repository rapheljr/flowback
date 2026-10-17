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
    public init() {}
}

public struct AgentsView: View {
    public let sessions: [AgentSession]
    public var onFocusSession: (AgentSession) -> Void

    @StateObject private var viewModel = AgentsViewModel()

    public init(sessions: [AgentSession], onFocusSession: @escaping (AgentSession) -> Void) {
        self.sessions = sessions
        self.onFocusSession = onFocusSession
    }

    public var filteredSessions: [AgentSession] {
        switch viewModel.filter {
        case .all: return sessions
        case .active: return sessions.filter { $0.state.isActive }
        case .completed: return sessions.filter { $0.state == .completed }
        case .failed: return sessions.filter { $0.state == .failed }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Agent Sessions")
                    .font(.title2.bold())
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
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if filteredSessions.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No agent sessions found")
                            .font(.headline)
                        Text(
                            viewModel.filter == .all
                                ? "Flowback will automatically detect background agent activity."
                                : "No sessions match the '\(viewModel.filter.rawValue)' filter."
                        )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("agents-empty-state")
                    Spacer()
                }
                Spacer()
            } else {
                List(filteredSessions) { session in
                    HStack(spacing: 16) {
                        Image(systemName: "cpu")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                            .frame(width: 32)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(session.displayTitle)
                                    .font(.headline)
                                    .lineLimit(1)

                                if sessions.filter({ $0.projectName == session.projectName }).count > 1 {
                                    Text("Shared Repo")
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                            }

                            HStack(spacing: 6) {
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
                                    .font(.caption)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(session.focusCapability == .windowOnly ? Color.gray.opacity(0.15) : Color.blue.opacity(0.15))
                                    .foregroundColor(session.focusCapability == .windowOnly ? .secondary : .accentColor)
                                    .cornerRadius(3)
                            }

                            if let summary = session.taskSummary, !summary.isEmpty {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 8) {
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
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Focus session \(session.displayTitle)")
                        .accessibilityIdentifier("agent-focus-\(session.id.rawValue)")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}
