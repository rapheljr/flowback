import SwiftUI
import FlowbackCore

public struct SettingsView: View {
    @Binding var config: PolicyConfiguration
    public var onSave: (PolicyConfiguration) -> Void
    
    public init(config: Binding<PolicyConfiguration>, onSave: @escaping (PolicyConfiguration) -> Void) {
        self._config = config
        self.onSave = onSave
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings & Focus Policies")
                    .font(.title2.bold())
                
                // Policy Mode
                VStack(alignment: .leading, spacing: 10) {
                    Text("Focus Restoration Policy")
                        .font(.headline)
                    Picker("Policy", selection: $config.focusPolicy) {
                        ForEach(FocusPolicyType.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    
                    Text(config.focusPolicy.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // macOS Spaces Policy
                VStack(alignment: .leading, spacing: 10) {
                    Text("macOS Spaces / Desktops")
                        .font(.headline)
                    Picker("Space Policy", selection: $config.spacePolicy) {
                        ForEach(SpacePolicy.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 280)
                    
                    Text("Controls whether Flowback can automatically move between macOS Spaces when restoring windows.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Timing & Cooldowns
                VStack(alignment: .leading, spacing: 14) {
                    Text("Timing & Cooldowns")
                        .font(.headline)
                    
                    HStack {
                        Text("Focus Cooldown:")
                            .frame(width: 180, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(config.focusCooldownMs) },
                            set: { config.focusCooldownMs = Int($0) }
                        ), in: 200...5000, step: 100)
                        Text("\(config.focusCooldownMs) ms")
                            .frame(width: 70, alignment: .trailing)
                    }
                    
                    HStack {
                        Text("Attention Aggregation:")
                            .frame(width: 180, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(config.attentionAggregationMs) },
                            set: { config.attentionAggregationMs = Int($0) }
                        ), in: 500...5000, step: 100)
                        Text("\(config.attentionAggregationMs) ms")
                            .frame(width: 70, alignment: .trailing)
                    }
                    
                    HStack {
                        Text("Active User Threshold:")
                            .frame(width: 180, alignment: .leading)
                        Slider(value: $config.activeInteractionThresholdSeconds, in: 1.0...30.0, step: 0.5)
                        Text(String(format: "%.1f s", config.activeInteractionThresholdSeconds))
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // System Startup
                VStack(alignment: .leading, spacing: 10) {
                    Text("System Integration")
                        .font(.headline)
                    Toggle("Launch Flowback at Login", isOn: $config.launchAtLogin)
                        .onChange(of: config.launchAtLogin) { _, newVal in
                            try? PermissionManager.shared.setLaunchAtLogin(enabled: newVal)
                        }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                HStack {
                    Spacer()
                    Button("Save Preferences") {
                        onSave(config)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }
}
