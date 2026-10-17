import SwiftUI
import AppKit
import FlowbackCore

public enum AdvancedConfigurationError: Error, LocalizedError, Sendable {
    case encodingFailed
    case invalidJSON
    case unsupportedSchemaVersion(Int)
    case invalidTimingValue(String)
    case invalidProviderIdentifier(String)
    case invalidApplicationIdentifier(String)
    case malformedOverride(String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode configuration to UTF-8 JSON"
        case .invalidJSON:
            return "Configuration JSON payload is malformed or invalid UTF-8"
        case .unsupportedSchemaVersion(let v):
            return "Unsupported configuration schema version: \(v). Expected version 1."
        case .invalidTimingValue(let detail):
            return "Invalid timing configuration: \(detail)"
        case .invalidProviderIdentifier(let id):
            return "Invalid provider identifier in overrides: '\(id)'"
        case .invalidApplicationIdentifier(let id):
            return "Invalid application identifier in configuration: '\(id)'"
        case .malformedOverride(let detail):
            return "Malformed policy override: \(detail)"
        }
    }
}

public final class AdvancedViewModel: ObservableObject {
    @Published public var hasSavedRecently: Bool = false
    @Published public var exportStatusMessage: String?
    @Published public var exportSucceeded: Bool?
    @Published public var importErrorMessage: String?
    @Published public var showResetConfirm: Bool = false
    @Published public var showImportConfirm: Bool = false
    @Published public var pendingImportConfig: PolicyConfiguration?

    public init() {}

    /// Exports configuration into pretty-printed JSON string
    public static func serializeConfig(_ config: PolicyConfiguration) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        guard let str = String(data: data, encoding: .utf8) else {
            throw AdvancedConfigurationError.encodingFailed
        }
        return str
    }

    /// Validates policy configuration invariants and safety bounds
    public static func validateConfig(_ config: PolicyConfiguration) throws {
        guard config.schemaVersion == 1 else {
            throw AdvancedConfigurationError.unsupportedSchemaVersion(config.schemaVersion)
        }
        guard config.focusCooldownMs >= 0 && config.focusCooldownMs <= 300_000 else {
            let msg = "focusCooldownMs must be between 0 and 300,000 ms (got \(config.focusCooldownMs))"
            throw AdvancedConfigurationError.invalidTimingValue(msg)
        }
        guard config.attentionAggregationMs >= 0 && config.attentionAggregationMs <= 300_000 else {
            let msg = "attentionAggregationMs must be between 0 and 300,000 ms (got \(config.attentionAggregationMs))"
            throw AdvancedConfigurationError.invalidTimingValue(msg)
        }
        guard config.activeInteractionThresholdSeconds >= 0.0 && config.activeInteractionThresholdSeconds <= 3600.0 else {
            let msg = "activeInteractionThresholdSeconds must be between 0 and 3600 seconds (got \(config.activeInteractionThresholdSeconds))"
            throw AdvancedConfigurationError.invalidTimingValue(msg)
        }
        if let validIdRegex = try? NSRegularExpression(pattern: "^[a-zA-Z0-9_-]{1,64}$") {
            for (provId, _) in config.providerOverrides {
                let trimmed = provId.trimmingCharacters(in: .whitespacesAndNewlines)
                let range = NSRange(location: 0, length: trimmed.utf16.count)
                guard !trimmed.isEmpty, validIdRegex.firstMatch(in: trimmed, options: [], range: range) != nil else {
                    throw AdvancedConfigurationError.invalidProviderIdentifier(provId)
                }
            }
        }
        for (appId, _) in config.applicationOverrides {
            let trimmed = appId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AdvancedConfigurationError.invalidApplicationIdentifier(appId)
            }
        }
        for (wsId, _) in config.workspaceOverrides {
            let trimmed = wsId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AdvancedConfigurationError.malformedOverride("Workspace override key cannot be empty")
            }
        }
        for app in config.protectedApplications {
            let trimmed = app.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AdvancedConfigurationError.invalidApplicationIdentifier("Protected application entry cannot be empty")
            }
        }
    }

    /// Validates and parses configuration from JSON string
    public static func parseConfig(from jsonString: String) throws -> PolicyConfiguration {
        guard let data = jsonString.data(using: .utf8) else {
            throw AdvancedConfigurationError.invalidJSON
        }
        let decoder = JSONDecoder()
        let config = try decoder.decode(PolicyConfiguration.self, from: data)
        try validateConfig(config)
        return config
    }

    /// Executes native macOS save panel to export configuration file
    @MainActor
    public func runExport(config: PolicyConfiguration) {
        exportSucceeded = nil
        exportStatusMessage = nil

        do {
            let jsonString = try Self.serializeConfig(config)
            let panel = NSSavePanel()
            panel.title = "Export Flowback Policy Configuration"
            panel.message = "Choose a location to save your Flowback preferences JSON."
            panel.nameFieldStringValue = "flowback-config.json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true

            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                try jsonString.write(to: url, atomically: true, encoding: .utf8)
                exportSucceeded = true
                exportStatusMessage = "Exported to \(url.lastPathComponent)"
            }
        } catch {
            exportSucceeded = false
            exportStatusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Executes native macOS open panel to import configuration file
    @MainActor
    public func runImport() {
        importErrorMessage = nil
        let panel = NSOpenPanel()
        panel.title = "Import Flowback Policy Configuration"
        panel.message = "Select a valid flowback-config.json file to import."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                guard let jsonStr = String(data: data, encoding: .utf8) else {
                    throw AdvancedConfigurationError.invalidJSON
                }
                let imported = try Self.parseConfig(from: jsonStr)
                pendingImportConfig = imported
                showImportConfirm = true
            } catch {
                importErrorMessage = "Invalid configuration file: \(error.localizedDescription)"
            }
        }
    }
}

public struct AdvancedView: View {
    @Binding var config: PolicyConfiguration
    public var isStorageDurable: Bool
    public var isIPCReady: Bool
    public var onSave: (PolicyConfiguration) -> Void

    @StateObject private var viewModel = AdvancedViewModel()

    private let knownProviders: [(id: String, name: String, icon: String)] = [
        ("antigravity", "Google Antigravity", "sparkles"),
        ("claude-code", "Claude Code", "terminal"),
        ("copilot", "GitHub Copilot", "chevron.left.forwardslash.chevron.right"),
        ("codex", "OpenAI Codex", "brain"),
        ("windsurf", "Windsurf", "wind"),
        ("opencode", "OpenCode", "curlybraces"),
        ("aider", "Aider", "bolt")
    ]

    public init(
        config: Binding<PolicyConfiguration>,
        isStorageDurable: Bool = true,
        isIPCReady: Bool = true,
        onSave: @escaping (PolicyConfiguration) -> Void
    ) {
        self._config = config
        self.isStorageDurable = isStorageDurable
        self.isIPCReady = isIPCReady
        self.onSave = onSave
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowbackSpacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                    Text("Advanced Preferences")
                        .font(.title2.bold())
                    Text("Lifecycle event policies, per-provider focus overrides, configuration backups, and storage controls.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Section 1: Lifecycle Event Behaviors
                FlowbackSettingsCard(
                    title: "Agent Lifecycle Behaviors",
                    subtitle: "Fine-tune how Flowback responds to completions, permission prompts, and failures."
                ) {
                    VStack(spacing: FlowbackSpacing.md) {
                        FlowbackSettingsRow(
                            icon: "checkmark.circle",
                            iconColor: .green,
                            title: "Completion Behavior",
                            caption: "Action executed when an autonomous agent completes its work successfully."
                        ) {
                            Picker("Completion Behavior", selection: $config.completionBehavior) {
                                ForEach(CompletionBehavior.allCases, id: \.self) { b in
                                    Text(b.displayName).tag(b)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 240)
                            .accessibilityIdentifier("advanced-completion-behavior-picker")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "hand.raised.fill",
                            iconColor: .orange,
                            title: "Permission Request Behavior",
                            caption: "Action executed when an agent halts waiting for user approval (e.g. bash commands)."
                        ) {
                            Picker("Permission Behavior", selection: $config.permissionBehavior) {
                                ForEach(PermissionBehavior.allCases, id: \.self) { b in
                                    Text(b.displayName).tag(b)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 240)
                            .accessibilityIdentifier("advanced-permission-behavior-picker")
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "xmark.circle.fill",
                            iconColor: .red,
                            title: "Failure Behavior",
                            caption: "Action executed when an agent encounters an error or non-zero exit code."
                        ) {
                            Picker("Failure Behavior", selection: $config.failureBehavior) {
                                ForEach(FailureBehavior.allCases, id: \.self) { b in
                                    Text(b.displayName).tag(b)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 240)
                            .accessibilityIdentifier("advanced-failure-behavior-picker")
                        }
                    }
                }

                // Section 2: Provider-Specific Policy Overrides
                FlowbackSettingsCard(
                    title: "Provider-Specific Policy Overrides",
                    subtitle: "Customize focus restoration behavior for individual coding agents (overrides global policy)."
                ) {
                    VStack(spacing: FlowbackSpacing.md) {
                        ForEach(knownProviders, id: \.id) { prov in
                            FlowbackSettingsRow(
                                icon: prov.icon,
                                iconColor: .accentColor,
                                title: prov.name,
                                caption: "Custom focus rule for \(prov.name) sessions."
                            ) {
                                Picker("Provider Rule", selection: Binding(
                                    get: { config.providerOverrides[prov.id] },
                                    set: { newPolicy in
                                        if let newPolicy = newPolicy {
                                            config.providerOverrides[prov.id] = newPolicy
                                        } else {
                                            config.providerOverrides.removeValue(forKey: prov.id)
                                        }
                                    }
                                )) {
                                    Text("Global Default (\(config.focusPolicy.displayName))").tag(FocusPolicyType?.none)
                                    ForEach(FocusPolicyType.allCases, id: \.self) { p in
                                        Text(p.displayName).tag(Optional(p))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 240)
                                .accessibilityIdentifier("advanced-provider-override-\(prov.id)")
                            }

                            if prov.id != knownProviders.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                // Section 3: Configuration Backup & Portability
                FlowbackSettingsCard(
                    title: "Configuration Backup & Portability",
                    subtitle: "Export your focus preferences to JSON or restore team-wide policy presets."
                ) {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
                        Text("Save all current policies, cooldowns, and application exclusion lists to an external JSON file, or load an existing configuration preset.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: FlowbackSpacing.md) {
                            Button {
                                viewModel.runExport(config: config)
                            } label: {
                                Label("Export JSON…", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("advanced-export-button")

                            Button {
                                viewModel.runImport()
                            } label: {
                                Label("Import JSON…", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("advanced-import-button")
                        }

                        if let msg = viewModel.exportStatusMessage {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.exportSucceeded == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(viewModel.exportSucceeded == true ? .green : .orange)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundColor(viewModel.exportSucceeded == true ? .green : .orange)
                            }
                        }

                        if let err = viewModel.importErrorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                // Section 4: Factory Reset & Defaults
                FlowbackSettingsCard(
                    title: "Reset Configuration",
                    subtitle: "Restore all Flowback rules, cooldowns, and protected apps to factory defaults."
                ) {
                    VStack(alignment: .leading, spacing: FlowbackSpacing.sm) {
                        Text("Resetting clears any custom focus cooldowns, space behaviors, provider overrides, and restores the standard protected applications list.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(role: .destructive) {
                            viewModel.showResetConfirm = true
                        } label: {
                            Label("Restore Factory Defaults", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("advanced-reset-defaults-button")
                    }
                }

                // Section 5: Architecture & Storage (Read-Only)
                FlowbackSettingsCard(
                    title: "Subsystem Architecture & Storage",
                    subtitle: "Read-only summary of local storage parameters and daemon socket bindings."
                ) {
                    VStack(spacing: FlowbackSpacing.md) {
                        FlowbackSettingsRow(
                            icon: "internaldrive",
                            iconColor: .teal,
                            title: "SQLite Persistence Engine",
                            caption: isStorageDurable
                                ? "WAL mode active at ~/.flowback/flowback.sqlite (Schema v\(config.schemaVersion))"
                                : "Degraded: Operating in transient in-memory database fallback"
                        ) {
                            Text(isStorageDurable ? "Durable" : "Transient")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((isStorageDurable ? Color.green : Color.orange).opacity(0.15))
                                .foregroundColor(isStorageDurable ? .green : .orange)
                                .cornerRadius(FlowbackRadius.badge)
                        }

                        Divider()

                        FlowbackSettingsRow(
                            icon: "network",
                            iconColor: .purple,
                            title: "IPC Domain Socket",
                            caption: isIPCReady ? "Listening at ~/.flowback/flowback.sock (0600 mode)" : "Socket offline"
                        ) {
                            Text(isIPCReady ? "Bound" : "Offline")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((isIPCReady ? Color.green : Color.red).opacity(0.15))
                                .foregroundColor(isIPCReady ? .green : .red)
                                .cornerRadius(FlowbackRadius.badge)
                        }
                    }
                }

                // Footer Save Status
                HStack(spacing: FlowbackSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Advanced changes take effect immediately and persist across launches.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, FlowbackSpacing.xs)
            }
            .padding(FlowbackSpacing.xxl)
        }
        .onChange(of: config) { _, newConfig in
            onSave(newConfig)
            viewModel.hasSavedRecently = true
        }
        .alert("Restore Factory Defaults?", isPresented: $viewModel.showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore Defaults", role: .destructive) {
                config = PolicyConfiguration.default
                onSave(config)
            }
        } message: {
            Text("Are you sure you want to restore all policy configuration to factory defaults? Your custom cooldowns, provider rules, and space settings will be reset.")
        }
        .alert("Import Configuration?", isPresented: $viewModel.showImportConfirm) {
            Button("Cancel", role: .cancel) {
                viewModel.pendingImportConfig = nil
            }
            Button("Apply Settings") {
                if let newConfig = viewModel.pendingImportConfig {
                    config = newConfig
                    onSave(newConfig)
                    viewModel.pendingImportConfig = nil
                    viewModel.exportStatusMessage = "Configuration imported and saved successfully."
                    viewModel.exportSucceeded = true
                }
            }
        } message: {
            Text("Applying this configuration will replace your current focus policies and application rules with the values from the imported file.")
        }
    }
}
