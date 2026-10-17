import SwiftUI
import FlowbackCore

public final class SettingsViewModel: ObservableObject {
    @Published public var hasSavedRecently: Bool = false
    @Published public var errorMessage: String?
    public init() {}
}

public struct SettingsView: View {
    @Binding var config: PolicyConfiguration
    public var onSave: (PolicyConfiguration) -> Void
    @StateObject private var viewModel = SettingsViewModel()

    public init(config: Binding<PolicyConfiguration>, onSave: @escaping (PolicyConfiguration) -> Void) {
        self._config = config
        self.onSave = onSave
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowbackSpacing.xl) {
                // Section 1: Focus Policy Card
                FlowbackSettingsCard(
                    title: "Focus Restoration Policy",
                    subtitle: "Determines how Flowback manages window focus when coding agents finish or request review."
                ) {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
                        Picker("Policy", selection: $config.focusPolicy) {
                            ForEach(FocusPolicyType.allCases, id: \.self) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .accessibilityIdentifier("settings-policy-picker")

                        HStack(spacing: FlowbackSpacing.sm) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text(config.focusPolicy.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, FlowbackSpacing.xs)
                    }
                }

                // Section 2: macOS Spaces Policy Card
                FlowbackSettingsCard(
                    title: "macOS Spaces & Virtual Desktops",
                    subtitle: "Controls whether Flowback can automatically move between macOS Spaces when restoring windows."
                ) {
                    FlowbackSettingsRow(
                        icon: "macwindow.on.rectangle",
                        iconColor: .purple,
                        title: "Spaces Behavior",
                        caption: "Prevent unexpected desktop switching during active multi-monitor or multi-space work."
                    ) {
                        Picker("Space Policy", selection: $config.spacePolicy) {
                            ForEach(SpacePolicy.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                        .accessibilityIdentifier("settings-space-policy-picker")
                    }
                }

                // Section 3: Timing & Cooldowns Card
                FlowbackSettingsCard(
                    title: "Timing & Interaction Safeguards",
                    subtitle: "Fine-tune cooldowns and idle thresholds to avoid interrupting you while typing."
                ) {
                    VStack(spacing: FlowbackSpacing.md) {
                        FlowbackSettingsRow(
                            icon: "timer",
                            iconColor: .blue,
                            title: "Focus Cooldown",
                            caption: "Minimum delay between consecutive focus restorations."
                        ) {
                            HStack(spacing: FlowbackSpacing.sm) {
                                Slider(value: Binding(
                                    get: { Double(config.focusCooldownMs) },
                                    set: { config.focusCooldownMs = Int($0) }
                                ), in: 200...5000, step: 100)
                                .frame(width: 140)
                                .accessibilityLabel("Focus Cooldown")
                                .accessibilityValue("\(config.focusCooldownMs) milliseconds")
                                .accessibilityIdentifier("settings-focus-cooldown-slider")

                                Text("\(config.focusCooldownMs) ms")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "waveform.badge.magnifyingglass",
                            iconColor: .teal,
                            title: "Attention Window",
                            caption: "Time window for aggregating concurrent agent completion bursts."
                        ) {
                            HStack(spacing: FlowbackSpacing.sm) {
                                Slider(value: Binding(
                                    get: { Double(config.attentionAggregationMs) },
                                    set: { config.attentionAggregationMs = Int($0) }
                                ), in: 500...5000, step: 100)
                                .frame(width: 140)
                                .accessibilityLabel("Attention Aggregation Window")
                                .accessibilityValue("\(config.attentionAggregationMs) milliseconds")
                                .accessibilityIdentifier("settings-attention-aggregation-slider")

                                Text("\(config.attentionAggregationMs) ms")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "keyboard",
                            iconColor: .orange,
                            title: "User Idle Threshold",
                            caption: "Duration of user inactivity required before automatic focus switch is allowed."
                        ) {
                            HStack(spacing: FlowbackSpacing.sm) {
                                Slider(value: $config.activeInteractionThresholdSeconds, in: 1.0...30.0, step: 0.5)
                                    .frame(width: 140)
                                    .accessibilityLabel("Active User Interaction Threshold")
                                    .accessibilityValue(String(format: "%.1f seconds", config.activeInteractionThresholdSeconds))
                                    .accessibilityIdentifier("settings-active-threshold-slider")

                                Text(String(format: "%.1f s", config.activeInteractionThresholdSeconds))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }

                // Section 4: System Integration Card
                FlowbackSettingsCard(
                    title: "System Integration",
                    subtitle: "Manage background daemon startup and login item status."
                ) {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.sm) {
                        FlowbackSettingsRow(
                            icon: "bolt.badge.automatic",
                            iconColor: .green,
                            title: "Launch at Login",
                            caption: "Start Flowback automatically in background accessory mode when logging in."
                        ) {
                            Toggle("", isOn: $config.launchAtLogin)
                                .labelsHidden()
                                .onChange(of: config.launchAtLogin) { _, newVal in
                                    do {
                                        try PermissionManager.shared.setLaunchAtLogin(enabled: newVal)
                                        viewModel.errorMessage = nil
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                        config.launchAtLogin = !newVal
                                    }
                                }
                                .accessibilityIdentifier("settings-launch-at-login-toggle")
                        }

                        if let err = viewModel.errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Footer: Persistent Save Confirmation & Action
                HStack(spacing: FlowbackSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Preferences apply and save automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Save Now") {
                        onSave(config)
                        viewModel.hasSavedRecently = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("settings-manual-save-button")
                }
                .padding(.horizontal, FlowbackSpacing.xs)
                .padding(.top, FlowbackSpacing.xs)
            }
            .padding(FlowbackSpacing.xxl)
        }
        .onChange(of: config) { _, newConfig in
            onSave(newConfig)
            viewModel.hasSavedRecently = true
        }
    }
}
