import SwiftUI
import FlowbackCore

public final class TimelineViewModel: ObservableObject {
    @Published public var selectedSessionID: AgentSessionID?
    
    public init(initialID: AgentSessionID? = nil) {
        self.selectedSessionID = initialID
    }
}

public struct SessionTimelineView: View {
    public let sessions: [AgentSession]
    public let timelineEntries: [TimelineEntry]
    
    @StateObject private var viewModel: TimelineViewModel
    
    public init(sessions: [AgentSession], timelineEntries: [TimelineEntry]) {
        self.sessions = sessions
        self.timelineEntries = timelineEntries
        self._viewModel = StateObject(wrappedValue: TimelineViewModel(initialID: sessions.first?.id))
    }
    
    public var currentEntries: [TimelineEntry] {
        if let id = viewModel.selectedSessionID {
            return timelineEntries.filter { $0.sessionID == id }
        }
        return timelineEntries
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Decision & Event Timeline")
                    .font(.title2.bold())
                Spacer()
                if !sessions.isEmpty {
                    Picker("Session", selection: $viewModel.selectedSessionID) {
                        ForEach(sessions) { s in
                            Text("\(s.providerID.rawValue) — \(s.projectName)").tag(Optional(s.id))
                        }
                    }
                    .frame(width: 300)
                    .accessibilityIdentifier("timeline-session-picker")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            if currentEntries.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No timeline entries recorded yet.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Decisions and lifecycle events will appear as agents execute.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("timeline-empty-state")
                    Spacer()
                }
                Spacer()
            } else {
                List(currentEntries) { entry in
                    HStack(alignment: .top, spacing: 16) {
                        Text(entry.formattedTime)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 65, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.summary)
                                    .font(.headline)
                                Spacer()
                                Text(entry.category)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            if let details = entry.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let exp = entry.decisionExplanation, !exp.isEmpty {
                                Text("Why: \(exp)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(entry.category) at \(entry.formattedTime): \(entry.summary)." +
                        (entry.decisionExplanation.map { " Reason: \($0)" } ?? "")
                    )
                    .accessibilityIdentifier("timeline-entry-\(entry.id)")
                }
            }
        }
    }
}
