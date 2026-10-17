import SwiftUI
import AppKit
import FlowbackCore

public final class AboutViewModel: ObservableObject {
    @Published public var showLicenseSheet: Bool = false
    public init() {}
}

public struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = AboutViewModel()

    public let appVersion: String
    public let buildNumber: String

    private let repoURL = URL(string: "https://github.com/rapheljr/flowback")!
    private let architectureURL = URL(string: "https://github.com/rapheljr/flowback/blob/main/ARCHITECTURE.md")!
    private let securityURL = URL(string: "https://github.com/rapheljr/flowback/blob/main/SECURITY.md")!
    private let noticesURL = URL(string: "https://github.com/rapheljr/flowback/blob/main/THIRD_PARTY_NOTICES.md")!

    private let mitLicenseText = """
    MIT License

    Copyright (c) 2026 Abin Rapheal and Flowback Contributors

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """

    public init(
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
        buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: FlowbackSpacing.xl) {
                // Brand Hero Header
                VStack(spacing: FlowbackSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.blue.opacity(0.35), radius: 8, x: 0, y: 4)

                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: FlowbackSpacing.xxs) {
                        Text("Flowback")
                            .font(.system(size: 26, weight: .bold))

                        Text("AI Focus & Context Orchestrator for macOS")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        HStack(spacing: FlowbackSpacing.sm) {
                            Text("v\(appVersion) (build \(buildNumber))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text("MIT License")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                        .padding(.top, 2)
                    }

                    Text("Intelligently coordinates window focus and desktop attention across autonomous AI coding agents without disruptive window thrashing.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, FlowbackSpacing.lg)

                // Metadata Card
                FlowbackSettingsCard(
                    title: "Application Details",
                    subtitle: "Metadata, licensing, and system architecture"
                ) {
                    VStack(spacing: FlowbackSpacing.md) {
                        FlowbackSettingsRow(
                            icon: "person.2",
                            iconColor: .blue,
                            title: "Authors & Copyright",
                            caption: "Copyright © 2026 Abin Rapheal and Flowback Contributors"
                        ) {
                            EmptyView()
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "doc.text.fill",
                            iconColor: .purple,
                            title: "Software License",
                            caption: "Released openly under the permissive MIT License"
                        ) {
                            Button("View License") {
                                viewModel.showLicenseSheet = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("about-view-license-button")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "laptopcomputer",
                            iconColor: .teal,
                            title: "System Compatibility",
                            caption: "macOS 14 Sonoma or newer (Optimized for Apple Silicon & Intel)"
                        ) {
                            EmptyView()
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "lock.shield",
                            iconColor: .green,
                            title: "Privacy Guarantee",
                            caption: "100% local execution — zero analytics, zero telemetry, zero data egress"
                        ) {
                            EmptyView()
                        }
                    }
                }

                // Links & Resources Card
                FlowbackSettingsCard(
                    title: "Project Resources",
                    subtitle: "Source repository, technical architecture, and open-source notices"
                ) {
                    VStack(spacing: FlowbackSpacing.md) {
                        FlowbackSettingsRow(
                            icon: "link",
                            iconColor: .accentColor,
                            title: "GitHub Repository",
                            caption: "Inspect source code, release tags, and issue discussions."
                        ) {
                            Link(destination: repoURL) {
                                Label("github.com/rapheljr/flowback", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("about-repo-link")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "cpu",
                            iconColor: .orange,
                            title: "Architecture Guide",
                            caption: "Learn about the User Intent Engine, state reconciliation, and IPC."
                        ) {
                            Link(destination: architectureURL) {
                                Label("Read Guide", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("about-architecture-link")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "shield.lefthalf.filled",
                            iconColor: .blue,
                            title: "Security Policy",
                            caption: "Vulnerability disclosure process and local isolation model."
                        ) {
                            Link(destination: securityURL) {
                                Label("Read Policy", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("about-security-link")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "newspaper",
                            iconColor: .indigo,
                            title: "Third-Party Notices",
                            caption: "Notices for SQLite3 and platform dependencies."
                        ) {
                            Link(destination: noticesURL) {
                                Label("View Notices", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("about-notices-link")
                        }
                    }
                }
            }
            .padding(FlowbackSpacing.xxl)
        }
        .accessibilityIdentifier("about-scroll-view")
        .sheet(isPresented: $viewModel.showLicenseSheet) {
            VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
                HStack {
                    Text("MIT License")
                        .font(.headline)
                    Spacer()
                    Button("Done") {
                        viewModel.showLicenseSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                }

                Divider()

                ScrollView {
                    Text(mitLicenseText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(width: 480, height: 320)
            }
            .padding(FlowbackSpacing.lg)
        }
    }
}
