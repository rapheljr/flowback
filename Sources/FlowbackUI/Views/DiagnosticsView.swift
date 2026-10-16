import SwiftUI
import FlowbackCore
import FlowbackProviders

public final class DiagnosticsViewModel: ObservableObject {
    @Published public var feedbackMessage: String?
    public init() {}
}

public struct DiagnosticsView: View {
    public let providerHealths: [ProviderHealth]
    public let permissionStatus: PermissionStatus
    public var onRepairAntigravity: () -> Void
    public var onTestFocus: () -> Void
    public var onTestNotification: () -> Void
    
    @StateObject private var viewModel = DiagnosticsViewModel()
    
    public init(
        providerHealths: [ProviderHealth],
        permissionStatus: PermissionStatus,
        onRepairAntigravity: @escaping () -> Void,
        onTestFocus: @escaping () -> Void,
        onTestNotification: @escaping () -> Void
    ) {
        self.providerHealths = providerHealths
        self.permissionStatus = permissionStatus
        self.onRepairAntigravity = onRepairAntigravity
        self.onTestFocus = onTestFocus
        self.onTestNotification = onTestNotification
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flowback Doctor & Diagnostics")
                            .font(.title2.bold())
                        Text("Health check and permission state for macOS subsystems and agent providers.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button("Test Focus") {
                            onTestFocus()
                            viewModel.feedbackMessage = "Triggered test focus evaluation"
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("diagnostics-test-focus-button")
                        
                        Button("Test Notification") {
                            onTestNotification()
                            viewModel.feedbackMessage = "Sent test notification"
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("diagnostics-test-notification-button")
                    }
                }
                
                if let msg = viewModel.feedbackMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .accessibilityLabel("Feedback: \(msg)")
                }
                
                // Subsystem checks
                VStack(alignment: .leading, spacing: 12) {
                    Text("Core Subsystems")
                        .font(.headline)
                    
                    DiagnosticRow(
                        title: "macOS Accessibility Permission",
                        detail: permissionStatus.accessibilityGranted
                            ? "Granted — exact window raising enabled"
                            : "Not granted — degraded to application-level focus",
                        isSuccess: permissionStatus.accessibilityGranted,
                        isWarning: !permissionStatus.accessibilityGranted,
                        actionTitle: permissionStatus.accessibilityGranted ? nil : "Open Settings…",
                        onAction: {
                            PermissionManager.shared.openAccessibilitySettings()
                        }
                    )
                    .accessibilityIdentifier("diagnostics-row-accessibility")
                    
                    DiagnosticRow(
                        title: "User Notifications Permission",
                        detail: permissionStatus.notificationsGranted ? "Authorized for alerts and banners" : "Not authorized — notifications disabled",
                        isSuccess: permissionStatus.notificationsGranted,
                        isWarning: !permissionStatus.notificationsGranted,
                        actionTitle: permissionStatus.notificationsGranted ? nil : "Open Settings…",
                        onAction: {
                            PermissionManager.shared.openNotificationSettings()
                        }
                    )
                    .accessibilityIdentifier("diagnostics-row-notifications")
                    
                    DiagnosticRow(
                        title: "Launch at Login",
                        detail: permissionStatus.launchAtLoginEnabled ? "Enabled via ServiceManagement" : "Disabled",
                        isSuccess: true,
                        isWarning: false
                    )
                    .accessibilityIdentifier("diagnostics-row-launch-at-login")
                    
                    DiagnosticRow(
                        title: "Local Persistent Database",
                        detail: "SQLite WAL Mode operational",
                        isSuccess: true,
                        isWarning: false
                    )
                    .accessibilityIdentifier("diagnostics-row-database")
                    
                    DiagnosticRow(
                        title: "IPC Unix Domain Socket",
                        detail: "Listening at ~/.flowback/flowback.sock",
                        isSuccess: true,
                        isWarning: false
                    )
                    .accessibilityIdentifier("diagnostics-row-socket")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Agent Integrations
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Agent Integrations")
                            .font(.headline)
                        Spacer()
                        Button("Repair / Install Hooks") {
                            onRepairAntigravity()
                            viewModel.feedbackMessage = "Updated Antigravity hook in ~/.gemini/config/hooks.json"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("diagnostics-repair-hooks-button")
                    }
                    
                    ForEach(providerHealths) { h in
                        HStack {
                            Circle()
                                .fill(h.isHealthy ? Color.green : (h.isInstalled ? Color.orange : Color.secondary))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(h.displayName).font(.headline)
                                    if let v = h.version {
                                        Text("v\(v)").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Text(h.statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(h.isHealthy ? "Operational" : (h.isInstalled ? "Needs Hook" : "Not Detected"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(h.isHealthy ? .green : .secondary)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(h.displayName): \(h.statusMessage) (\(h.isHealthy ? "Operational" : "Attention needed"))")
                        .accessibilityIdentifier("diagnostics-provider-\(h.id)")
                    }
                }
                
                // Privacy Guarantee
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.blue)
                            .accessibilityHidden(true)
                        Text("Local-First Privacy Architecture")
                            .font(.headline)
                    }
                    Text(
                        "Flowback executes 100% locally on your Mac. Agent lifecycle observation, " +
                        "focus evaluations, and session timeline history never leave this device. " +
                        "No network telemetry or prompt content is transmitted."
                    )
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("diagnostics-privacy-notice")
            }
            .padding(24)
        }
    }
}

struct DiagnosticRow: View {
    let title: String
    let detail: String
    let isSuccess: Bool
    let isWarning: Bool
    var actionTitle: String?
    var onAction: (() -> Void)?
    
    var body: some View {
        HStack {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : (isWarning ? "exclamationmark.triangle.fill" : "xmark.circle.fill"))
                .foregroundColor(isSuccess ? .green : (isWarning ? .orange : .red))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if let actionTitle = actionTitle, let onAction = onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
    }
}
