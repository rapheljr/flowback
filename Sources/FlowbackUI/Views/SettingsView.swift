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
        Form {
            // Section 1: Focus Policy
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Policy", selection: $config.focusPolicy) {
                        ForEach(FocusPolicyType.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityIdentifier("settings-policy-picker")
                    
                    Text(config.focusPolicy.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            } header: {
                Text("Focus Restoration Policy")
                    .font(.headline)
            }
            
            // Section 2: macOS Spaces Policy
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Space Policy", selection: $config.spacePolicy) {
                        ForEach(SpacePolicy.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 280)
                    .accessibilityIdentifier("settings-space-policy-picker")
                    
                    Text("Controls whether Flowback can automatically move between macOS Spaces when restoring windows.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("macOS Spaces / Desktops")
                    .font(.headline)
            }
            
            // Section 3: Timing & Cooldowns
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Focus Cooldown:")
                            .frame(width: 180, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(config.focusCooldownMs) },
                            set: { config.focusCooldownMs = Int($0) }
                        ), in: 200...5000, step: 100)
                        .accessibilityLabel("Focus Cooldown")
                        .accessibilityValue("\(config.focusCooldownMs) milliseconds")
                        .accessibilityIdentifier("settings-focus-cooldown-slider")
                        
                        Text("\(config.focusCooldownMs) ms")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 75, alignment: .trailing)
                    }
                    
                    HStack {
                        Text("Attention Aggregation:")
                            .frame(width: 180, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(config.attentionAggregationMs) },
                            set: { config.attentionAggregationMs = Int($0) }
                        ), in: 500...5000, step: 100)
                        .accessibilityLabel("Attention Aggregation Window")
                        .accessibilityValue("\(config.attentionAggregationMs) milliseconds")
                        .accessibilityIdentifier("settings-attention-aggregation-slider")
                        
                        Text("\(config.attentionAggregationMs) ms")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 75, alignment: .trailing)
                    }
                    
                    HStack {
                        Text("Active User Threshold:")
                            .frame(width: 180, alignment: .leading)
                        Slider(value: $config.activeInteractionThresholdSeconds, in: 1.0...30.0, step: 0.5)
                        .accessibilityLabel("Active User Interaction Threshold")
                        .accessibilityValue(String(format: "%.1f seconds", config.activeInteractionThresholdSeconds))
                        .accessibilityIdentifier("settings-active-threshold-slider")
                        
                        Text(String(format: "%.1f s", config.activeInteractionThresholdSeconds))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 75, alignment: .trailing)
                    }
                }
            } header: {
                Text("Timing & Cooldowns")
                    .font(.headline)
            }
            
            // Section 4: System Integration
            Section {
                Toggle("Launch Flowback at Login", isOn: $config.launchAtLogin)
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
                
                if let err = viewModel.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("System Integration")
                    .font(.headline)
            }
            
            // Status footer: Auto-persistence confirmation
            Section {
                HStack {
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
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .onChange(of: config) { _, newConfig in
            onSave(newConfig)
            viewModel.hasSavedRecently = true
        }
    }
}
