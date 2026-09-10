import SwiftUI
import FlowbackCore
import FlowbackFocus

public struct OverviewView: View {
    @Binding var activeSessions: [AgentSession]
    @Binding var attentionQueue: [AttentionRequest]
    @Binding var focusLock: FocusLockState
    public var onFocusSession: (AgentSession) -> Void
    
    public init(
        activeSessions: Binding<[AgentSession]>,
        attentionQueue: Binding<[AttentionRequest]>,
        focusLock: Binding<FocusLockState>,
        onFocusSession: @escaping (AgentSession) -> Void
    ) {
        self._activeSessions = activeSessions
        self._attentionQueue = attentionQueue
        self._focusLock = focusLock
        self.onFocusSession = onFocusSession
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Focus Lock banner if active
                if focusLock.isCurrentlyLocked {
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Focus Lock Active")
                                .font(.headline)
                            if let rem = focusLock.remainingSeconds {
                                Text("Automatic focus switching is paused for \(Int(rem / 60)) more minutes.")
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
                    }
                    .padding()
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(10)
                }
                
                // Stat Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Attention Required")
                            .font(.title2.bold())
                        ForEach(attentionQueue) { req in
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading) {
                                    Text(req.title).font(.headline)
                                    Text(req.message).font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                
                // Active Sessions
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Active Agents")
                            .font(.title2.bold())
                        Spacer()
                    }
                    
                    if activeSessions.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("No agents currently running")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Flowback is monitoring background agent lifecycle events.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 40)
                            Spacer()
                        }
                    } else {
                        ForEach(activeSessions) { session in
                            HStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.projectName)
                                        .font(.headline)
                                    Text("\(session.providerID.rawValue) • Started \(session.formattedDuration) ago")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                StatusBadge(state: session.state)
                                Button("Restore Focus") {
                                    onFocusSession(session)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundColor(color)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
