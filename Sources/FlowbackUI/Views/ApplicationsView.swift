import SwiftUI
import AppKit
import FlowbackCore

public final class ApplicationsViewModel: ObservableObject {
    @Published public var newAppBundleID: String = ""
    public init() {}
}

public struct ApplicationsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var protectedApps: [String]
    @StateObject private var viewModel = ApplicationsViewModel()

    public static let suggestedPresets: [(name: String, bundleID: String, icon: String)] = [
        ("Zoom", "us.zoom.xos", "video.fill"),
        ("Keynote", "com.apple.Keynote", "play.rectangle.fill"),
        ("Teams", "com.microsoft.teams", "person.2.fill"),
        ("FaceTime", "com.apple.FaceTime", "phone.fill"),
        ("QuickTime", "com.apple.QuickTimePlayerX", "film.fill")
    ]

    private var suggestedApps: [(name: String, bundleID: String, icon: String)] {
        Self.suggestedPresets
    }

    public init(protectedApps: Binding<[String]>) {
        self._protectedApps = protectedApps
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowbackSpacing.xl) {
                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                    Text("Protected Applications")
                        .font(.title2.bold())
                    Text("Flowback will NEVER steal focus when any of these applications are frontmost. Notifications will be displayed instead.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Add app input
                VStack(alignment: .leading, spacing: FlowbackSpacing.xs) {
                    HStack(spacing: FlowbackSpacing.sm) {
                        TextField("Add bundle identifier (e.g. us.zoom.xos)", text: $viewModel.newAppBundleID)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Application bundle identifier to protect")
                            .accessibilityIdentifier("applications-bundle-textfield")
                            .onSubmit(addApp)

                        Button("Add", action: addApp)
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("applications-add-button")
                    }

                    // Quick-add suggestions
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FlowbackSpacing.xs) {
                            Text("Presets:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(suggestedApps, id: \.bundleID) { item in
                                let isAdded = protectedApps.contains(item.bundleID)
                                Button {
                                    if !isAdded {
                                        protectedApps.append(item.bundleID)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isAdded ? "checkmark" : item.icon)
                                            .font(.system(size: 10))
                                        Text(item.name)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isAdded ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                                    .foregroundColor(isAdded ? .green : .primary)
                                    .cornerRadius(FlowbackRadius.badge)
                                }
                                .buttonStyle(.plain)
                                .disabled(isAdded)
                            }
                        }
                    }
                }

                if protectedApps.isEmpty {
                    FlowbackEmptyState(
                        icon: "shield.slash",
                        title: "No protected applications",
                        message: "Add bundle identifiers or choose a preset above to ensure Flowback never interrupts presentations, screen shares, or video calls.",
                        actionTitle: "Add Meeting Presets",
                        onAction: {
                            for item in suggestedApps where !protectedApps.contains(item.bundleID) {
                                protectedApps.append(item.bundleID)
                            }
                        }
                    )
                    .accessibilityIdentifier("applications-empty-state")
                } else {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.xs) {
                        Text("Protected Rules (\(protectedApps.count))")
                            .font(.headline)

                        VStack(spacing: FlowbackSpacing.sm) {
                            ForEach(protectedApps, id: \.self) { app in
                                HStack(spacing: FlowbackSpacing.md) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                                            .fill(ThemeTokens.iconTileFill(tint: .green, scheme: colorScheme))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "shield.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.green)
                                    }
                                    .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app)
                                            .font(.system(.body, design: .monospaced))
                                        Text(displayName(for: app))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button(
                                        action: {
                                            protectedApps.removeAll { $0 == app }
                                        },
                                        label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    )
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(app) from protected applications")
                                    .help("Remove \(app) from protected applications")
                                    .accessibilityIdentifier("applications-remove-\(app)")
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

    private func displayName(for bundleID: String) -> String {
        if let match = suggestedApps.first(where: { $0.bundleID == bundleID }) {
            return "\(match.name) • Suppresses focus stealing during meetings/presentations"
        }
        return "Custom application rule • Focus suppression enabled"
    }

    private func addApp() {
        let trimmed = viewModel.newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !protectedApps.contains(trimmed) {
            protectedApps.append(trimmed)
            viewModel.newAppBundleID = ""
        }
    }
}
