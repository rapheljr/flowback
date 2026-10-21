import SwiftUI
import AppKit
import FlowbackCore

public final class SupportViewModel: ObservableObject {
    @Published public var exportMessage: String?
    @Published public var exportSucceeded: Bool?

    public init() {}

    @MainActor
    public func exportDiagnosticReport(context: DiagnosticReportContext) {
        exportMessage = nil
        exportSucceeded = nil

        let report = DiagnosticReportExporter.generateSanitizedReport(context: context)
        let result = DiagnosticReportExporter.runSavePanel(reportContent: report)

        if result.saved {
            exportSucceeded = true
            exportMessage = "Diagnostic report saved successfully."
        } else if let error = result.error {
            exportSucceeded = false
            exportMessage = "Failed to save diagnostic report: \(error)"
        }
    }
}

public struct SupportView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = SupportViewModel()

    public var diagnosticContext: DiagnosticReportContext
    public var onNavigateToDiagnostics: (() -> Void)?

    public static let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/flowback")!
    public static let supportWebURL = URL(string: "https://rapheljr.github.io/flowback/support/")!

    private let repoURL = URL(string: "https://github.com/rapheljr/flowback")!
    private let discussionsURL = URL(string: "https://github.com/rapheljr/flowback/discussions")!
    private let issuesURL = URL(string: "https://github.com/rapheljr/flowback/issues")!
    private let securityURL = URL(string: "https://github.com/rapheljr/flowback/security/advisories/new")!
    private let troubleshootingDocURL = URL(string: "https://github.com/rapheljr/flowback/blob/main/TROUBLESHOOTING.md")!
    private let architectureDocURL = URL(string: "https://github.com/rapheljr/flowback/blob/main/ARCHITECTURE.md")!
    private let coffeeURL = SupportView.buyMeACoffeeURL
    private let supportPageURL = SupportView.supportWebURL

    public init(
        diagnosticContext: DiagnosticReportContext = DiagnosticReportContext(),
        onNavigateToDiagnostics: (() -> Void)? = nil
    ) {
        self.diagnosticContext = diagnosticContext
        self.onNavigateToDiagnostics = onNavigateToDiagnostics
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowbackSpacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                    Text("Support & Troubleshooting")
                        .font(.title2.bold())
                    Text("Support development, get help, review troubleshooting guides, and export sanitized diagnostic logs.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Section 1: Support Development on Buy Me a Coffee
                FlowbackSettingsCard(
                    title: "Support Flowback Development",
                    subtitle: "Independent, open-source AI focus orchestration built for macOS."
                ) {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
                        HStack(alignment: .top, spacing: FlowbackSpacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.pink, Color.red.opacity(0.85)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .shadow(color: Color.pink.opacity(0.30), radius: 4, x: 0, y: 2)

                                Image(systemName: "heart.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                                Text("Flowback is free, open source, and built to keep you in flow while autonomous AI coding agents work.")
                                    .font(.subheadline.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(
                                    "If Flowback saves you context-switching overhead and distraction, " +
                                    "supporting on Buy Me a Coffee directly funds continuous releases, automated testing, and agent adapters."
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(spacing: FlowbackSpacing.md) {
                            Link(destination: coffeeURL) {
                                Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.orange)
                            .accessibilityIdentifier("support-buy-me-a-coffee-button")

                            Link(destination: supportPageURL) {
                                Label("Support & Memberships", systemImage: "heart.circle")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-memberships-link")

                            Link(destination: repoURL) {
                                Label("Star on GitHub", systemImage: "star.fill")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-github-star-link")
                        }
                    }
                }

                // Section 2: Self-Diagnostics & Doctor
                FlowbackSettingsCard(
                    title: "Diagnostic Self-Check",
                    subtitle: "Verify macOS permissions, database health, and agent socket responsiveness."
                ) {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
                        Text("Before filing an issue, inspect your local system state using Flowback's built-in doctor checks or the interactive Diagnostics panel.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: FlowbackSpacing.md) {
                            if let onNavigateToDiagnostics {
                                Button {
                                    onNavigateToDiagnostics()
                                } label: {
                                    Label("Open Diagnostics Panel", systemImage: "stethoscope")
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("support-open-diagnostics-button")
                            }

                            Button {
                                let terminalScript = """
                                tell application "Terminal"
                                    do script "flowback doctor"
                                    activate
                                end tell
                                """
                                DispatchQueue.global(qos: .userInitiated).async {
                                    if let script = NSAppleScript(source: terminalScript) {
                                        var error: NSDictionary?
                                        script.executeAndReturnError(&error)
                                    }
                                }
                            } label: {
                                Label("Run 'flowback doctor' in Terminal", systemImage: "terminal")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-run-doctor-button")
                        }

                        HStack(spacing: FlowbackSpacing.xs) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("Checks accessibility permissions, notification authorization, database WAL integrity, and agent hook configurations.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Section 3: Sanitized Diagnostic Report Exporter
                FlowbackSettingsCard(
                    title: "Sanitized Diagnostic Report Export",
                    subtitle: "Generate a shareable troubleshooting log with all private tokens and file paths redacted."
                ) {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
                        Text(
                            "Need to share diagnostic information in a GitHub issue or discussion? " +
                            "Generate an offline Markdown report containing system versions, permission states, and active focus rules."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: FlowbackSpacing.xs) {
                            HStack(spacing: FlowbackSpacing.xs) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                Text("Privacy-Guaranteed Sanitization")
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                            }
                            Text(
                                "The report automatically scrubs Bearer tokens, API keys, passwords, private keys, and user home directory names. " +
                                "Conversation prompts and code contents are never exported."
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                        .padding(FlowbackSpacing.sm)
                        .background(Color.green.opacity(0.10))
                        .cornerRadius(FlowbackRadius.subcard)

                        Button {
                            viewModel.exportDiagnosticReport(context: diagnosticContext)
                        } label: {
                            Label("Export Sanitized Report…", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("support-export-report-button")

                        if let msg = viewModel.exportMessage {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.exportSucceeded == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(viewModel.exportSucceeded == true ? .green : .red)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundColor(viewModel.exportSucceeded == true ? .green : .red)
                            }
                            .accessibilityIdentifier("support-export-status-banner")
                        }
                    }
                }

                // Section 4: Community & Issue Tracker
                FlowbackSettingsCard(
                    title: "Community & Issue Reporting",
                    subtitle: "Search known issues, ask questions, or contribute feature proposals."
                ) {
                    VStack(spacing: FlowbackSpacing.md) {
                        FlowbackSettingsRow(
                            icon: "bubble.left.and.bubble.right",
                            iconColor: .purple,
                            title: "GitHub Discussions & Q&A",
                            caption: "Ask questions, share workflows, and discuss agent orchestration patterns."
                        ) {
                            Link(destination: discussionsURL) {
                                Label("Join Discussions", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-discussions-link")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "ant",
                            iconColor: .orange,
                            title: "Issue Tracker & Bug Reports",
                            caption: "Search existing reports or submit a new bug with reproduction steps."
                        ) {
                            Link(destination: issuesURL) {
                                Label("Open Issues", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-issues-link")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "shield.checkered",
                            iconColor: .blue,
                            title: "Security Advisories",
                            caption: "Report security vulnerabilities privately via GitHub Security Advisories."
                        ) {
                            Link(destination: securityURL) {
                                Label("Report Privately", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-security-link")
                        }
                    }
                }

                // Section 5: Project Documentation
                FlowbackSettingsCard(
                    title: "Documentation & Resources",
                    subtitle: "Step-by-step guides for troubleshooting, architecture, and provider hooks."
                ) {
                    VStack(spacing: FlowbackSpacing.md) {
                        FlowbackSettingsRow(
                            icon: "questionmark.circle",
                            iconColor: .teal,
                            title: "Troubleshooting Guide",
                            caption: "Resolutions for common permission, window raising, and socket issues."
                        ) {
                            Link(destination: troubleshootingDocURL) {
                                Label("View Guide", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-troubleshooting-doc-link")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "doc.text",
                            iconColor: .indigo,
                            title: "Architecture & Security Model",
                            caption: "Detailed reference on User Intent Engine, state transitions, and IPC."
                        ) {
                            Link(destination: architectureDocURL) {
                                Label("View Architecture", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-architecture-doc-link")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "link",
                            iconColor: .secondary,
                            title: "Source Code Repository",
                            caption: "Visit the Flowback repository on GitHub."
                        ) {
                            Link(destination: repoURL) {
                                Label("github.com/rapheljr/flowback", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support-repo-link")
                        }
                    }
                }
            }
            .padding(FlowbackSpacing.xxl)
        }
        .accessibilityIdentifier("support-scroll-view")
    }
}
