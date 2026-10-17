import SwiftUI
import FlowbackCore

public final class TimelineViewModel: ObservableObject {
    @Published public var selectedSessionID: AgentSessionID?
    
    public init(initialID: AgentSessionID? = nil) {
        self.selectedSessionID = initialID
    }
}

public struct SessionTimelineView: View {
    @Environment(\.colorScheme) private var colorScheme
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
        VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                    HStack(spacing: FlowbackSpacing.xs) {
                        Text("Decision & Event Timeline")
                            .font(.title2.bold())
                        Text("\(currentEntries.count) events")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(FlowbackRadius.badge)
                    }
                    Text("Immutable audit trail of focus evaluations and agent state transitions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !sessions.isEmpty {
                    Picker("Session", selection: $viewModel.selectedSessionID) {
                        Text("All Sessions").tag(nil as AgentSessionID?)
                        ForEach(sessions) { s in
                            Text("\(s.providerDisplayName) — \(s.projectName)").tag(Optional(s.id))
                        }
                    }
                    .frame(width: 260)
                    .accessibilityIdentifier("timeline-session-picker")
                }
            }
            .padding(.horizontal, FlowbackSpacing.xl)
            .padding(.top, FlowbackSpacing.lg)

            if currentEntries.isEmpty {
                Spacer()
                FlowbackEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No timeline entries recorded yet",
                    message: "Decisions and lifecycle events will appear here as background agents execute."
                )
                .accessibilityIdentifier("timeline-empty-state")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: FlowbackSpacing.sm) {
                        ForEach(currentEntries) { entry in
                            let catInfo = categoryInfo(for: entry.category)
                            HStack(alignment: .top, spacing: FlowbackSpacing.md) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                                        .fill(ThemeTokens.iconTileFill(tint: catInfo.color, scheme: colorScheme))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: catInfo.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(catInfo.color)
                                }
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(entry.summary)
                                            .font(.headline)
                                        Spacer()
                                        HStack(spacing: FlowbackSpacing.xs) {
                                            Text(entry.category)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(catInfo.color.opacity(0.15))
                                                .foregroundColor(catInfo.color)
                                                .cornerRadius(FlowbackRadius.badge)
                                            Text(entry.formattedTime)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    if let details = entry.details, !details.isEmpty {
                                        Text(details)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    if let exp = entry.decisionExplanation, !exp.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 11))
                                            Text("Decision: \(exp)")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.08))
                                        .cornerRadius(FlowbackRadius.subcard)
                                    }
                                }
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
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                "\(entry.category) at \(entry.formattedTime): \(entry.summary)." +
                                (entry.decisionExplanation.map { " Reason: \($0)" } ?? "")
                            )
                            .accessibilityIdentifier("timeline-entry-\(entry.id)")
                        }
                    }
                    .padding(.horizontal, FlowbackSpacing.xl)
                    .padding(.bottom, FlowbackSpacing.xl)
                }
            }
        }
    }

    private func categoryInfo(for category: String) -> (icon: String, color: Color) {
        let lower = category.lowercased()
        if lower.contains("focus") {
            return ("sparkles", .blue)
        } else if lower.contains("life") || lower.contains("start") || lower.contains("stop") {
            return ("arrow.triangle.branch", .green)
        } else if lower.contains("policy") || lower.contains("lock") {
            return ("shield.lefthalf.filled", .purple)
        } else if lower.contains("alert") || lower.contains("warn") || lower.contains("error") {
            return ("exclamationmark.triangle.fill", .orange)
        }
        return ("clock.circle", .secondary)
    }
}
