import SwiftUI
import FlowbackCore
import FlowbackFocus

public struct OverviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var activeSessions: [AgentSession]
    @Binding var attentionQueue: [AttentionRequest]
    @Binding var focusLock: FocusLockState
    public var onFocusSession: (AgentSession) -> Void
    public var onRefresh: () -> Void

    public init(
        activeSessions: Binding<[AgentSession]>,
        attentionQueue: Binding<[AttentionRequest]>,
        focusLock: Binding<FocusLockState>,
        onFocusSession: @escaping (AgentSession) -> Void,
        onRefresh: @escaping () -> Void = {}
    ) {
        self._activeSessions = activeSessions
        self._attentionQueue = attentionQueue
        self._focusLock = focusLock
        self.onFocusSession = onFocusSession
        self.onRefresh = onRefresh
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowbackSpacing.xl) {
                // Focus Lock banner if active
                if focusLock.isCurrentlyLocked {
                    HStack(spacing: FlowbackSpacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                                .fill(ThemeTokens.iconTileFill(tint: .orange, scheme: colorScheme))
                                .frame(width: 32, height: 32)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Focus Lock Active")
                                .font(.headline)
                            if let rem = focusLock.remainingSeconds {
                                Text("Automatic focus switching is paused for \(max(1, Int(rem / 60))) more minutes.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Automatic focus switching is paused indefinitely.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("Disable") {
                            focusLock = FocusLockState(isActive: false)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Disable focus lock")
                        .accessibilityIdentifier("overview-disable-lock-button")
                    }
                    .padding(FlowbackSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: FlowbackRadius.card, style: .continuous)
                            .fill(Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowbackRadius.card, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: ThemeTokens.cardBorderWidth)
                    )
                    .accessibilityIdentifier("overview-focus-lock-banner")
                }

                // Stat Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: FlowbackSpacing.md) {
                    StatCard(
                        title: "Active Agents",
                        value: "\(activeSessions.count)",
                        systemImage: "waveform.path.ecg",
                        color: .blue
                    )
                    StatCard(
                        title: "Attention Queue",
                        value: "\(attentionQueue.count)",
                        systemImage: "bell.badge",
                        color: attentionQueue.isEmpty ? .secondary : .orange
                    )
                    StatCard(
                        title: "Focus Mode",
                        value: focusLock.isCurrentlyLocked ? "Locked" : "Smart",
                        systemImage: focusLock.isCurrentlyLocked ? "lock" : "sparkles",
                        color: focusLock.isCurrentlyLocked ? .orange : .green
                    )
                }

                // Attention Queue items
                if !attentionQueue.isEmpty {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.sm) {
                        Text("Attention Required")
                            .font(.title3.bold())
                        ForEach(attentionQueue) { req in
                            HStack(spacing: FlowbackSpacing.md) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                                        .fill(ThemeTokens.iconTileFill(tint: .orange, scheme: colorScheme))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.title).font(.headline)
                                    Text(req.message).font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                                if let session = activeSessions.first(where: { $0.id == req.sessionID }) {
                                    Button("Review & Focus") {
                                        onFocusSession(session)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
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
                            .accessibilityIdentifier("overview-attention-item-\(req.sessionID.rawValue)")
                        }
                    }
                }

                // Active Sessions
                VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                            Text("Active Agents")
                                .font(.title3.bold())
                            Text("Real-time orchestrator monitoring")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: onRefresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Scan and refresh active agent sessions")
                        .accessibilityIdentifier("overview-refresh-button")
                    }

                    if activeSessions.isEmpty {
                        FlowbackEmptyState(
                            icon: "checkmark.circle",
                            title: "No agents currently running",
                            message: "Flowback is monitoring background agent lifecycle events.",
                            actionTitle: "Scan Now",
                            onAction: onRefresh
                        )
                        .accessibilityIdentifier("overview-empty-state")
                    } else {
                        VStack(spacing: FlowbackSpacing.sm) {
                            ForEach(activeSessions) { session in
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
                                            if activeSessions.filter({ $0.projectName == session.projectName }).count > 1 {
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
                                                .font(.subheadline.weight(.semibold))
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
                                            Text("•")
                                                .foregroundColor(.secondary)
                                            Text(session.formattedDuration)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    StatusBadge(state: session.state)

                                    Button("Restore Focus") {
                                        onFocusSession(session)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.regular)
                                    .accessibilityLabel("Restore focus to \(session.displayTitle)")
                                    .accessibilityIdentifier("restore-focus-\(session.id.rawValue)")
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
                    }
                }
            }
            .padding(FlowbackSpacing.xl)
        }
    }
}

struct StatCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: FlowbackSpacing.md) {
            VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: FlowbackRadius.subcard, style: .continuous)
                    .fill(ThemeTokens.iconTileFill(tint: color, scheme: colorScheme))
                    .frame(width: 36, height: 36)
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            .accessibilityHidden(true)
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
        .accessibilityLabel("\(title): \(value)")
        .accessibilityIdentifier("overview-stat-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}
