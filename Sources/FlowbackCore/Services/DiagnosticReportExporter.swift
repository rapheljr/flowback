import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Context data used to generate a diagnostic troubleshooting report
public struct DiagnosticReportContext: Sendable {
    public var appVersion: String
    public var appBuild: String
    public var timestamp: Date
    public var macOSVersion: String
    public var architecture: String
    public var permissionStatus: PermissionStatus
    public var isDatabaseReady: Bool
    public var isStorageDurable: Bool
    public var storageNotice: String?
    public var isIPCReady: Bool
    public var providerHealths: [ProviderHealth]
    public var configuration: PolicyConfiguration
    public var recentTimeline: [TimelineEntry]

    public init(
        appVersion: String = FlowbackVersion.current,
        appBuild: String = FlowbackVersion.currentBuild,
        timestamp: Date = Date(),
        macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: String = {
            #if arch(arm64)
            return "Apple Silicon (arm64)"
            #elseif arch(x86_64)
            return "Intel (x86_64)"
            #else
            return "Unknown"
            #endif
        }(),
        permissionStatus: PermissionStatus = PermissionStatus(),
        isDatabaseReady: Bool = true,
        isStorageDurable: Bool = true,
        storageNotice: String? = nil,
        isIPCReady: Bool = true,
        providerHealths: [ProviderHealth] = [],
        configuration: PolicyConfiguration = .default,
        recentTimeline: [TimelineEntry] = []
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.timestamp = timestamp
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.permissionStatus = permissionStatus
        self.isDatabaseReady = isDatabaseReady
        self.isStorageDurable = isStorageDurable
        self.storageNotice = storageNotice
        self.isIPCReady = isIPCReady
        self.providerHealths = providerHealths
        self.configuration = configuration
        self.recentTimeline = recentTimeline
    }
}

/// Generates sanitized, shareable diagnostic reports without leaking sensitive user tokens, paths, or keys.
public enum DiagnosticReportExporter: Sendable {

    /// Sanitizes local file paths by replacing any user home directory with '~'
    public static func sanitizePath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        var result = path
        let home = ("~" as NSString).expandingTildeInPath
        if !home.isEmpty && home != "/" && result.contains(home) {
            result = result.replacingOccurrences(of: home, with: "~")
        }
        // Catch any /Users/<username> or /home/<username> patterns embedded in free text (supporting spaces in usernames)
        let pattern = "(?:/Users|/home)/[^/\"'\n\r,;:)]+(?=/|$)"
        if let userRegex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = userRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "~")
        }
        return result
    }

    /// Combined sanitizer for free text fields applying both path sanitization and SecretSanitizer
    public static func sanitizeTextAndPaths(_ text: String) -> String {
        let pathSanitized = sanitizePath(text)
        return SecretSanitizer.sanitizeText(pathSanitized)
    }

    /// Formats a complete sanitized Markdown diagnostic report
    public static func generateSanitizedReport(context: DiagnosticReportContext) -> String {
        let formatter = ISO8601DateFormatter()
        let timestampStr = formatter.string(from: context.timestamp)

        var lines: [String] = []
        lines.append("# Flowback Diagnostic Report")
        lines.append("> Generated on \(timestampStr). This report contains sanitized system and configuration states for troubleshooting. " +
                     "No secrets, credentials, or private keys are included.")
        lines.append("")

        // 1. Application & System Info
        lines.append("## 1. Environment & Architecture")
        lines.append("- **Application Version:** Flowback v\(context.appVersion) (build \(context.appBuild))")
        lines.append("- **Operating System:** macOS \(context.macOSVersion)")
        lines.append("- **Hardware Architecture:** \(context.architecture)")
        lines.append("- **Local Storage Engine:** SQLite 3 (WAL Mode)")
        let dbStatus = context.isDatabaseReady
            ? (context.isStorageDurable ? "Durable WAL mode (~/.flowback/flowback.sqlite)" : "Transient In-Memory Fallback")
            : "Offline / Uninitialized"
        lines.append("- **Database Status:** \(dbStatus)")
        if let notice = context.storageNotice {
            lines.append("  - *Storage Notice:* \(sanitizeTextAndPaths(notice))")
        }
        lines.append("- **IPC Domain Socket:** \(context.isIPCReady ? "Listening (~/.flowback/flowback.sock)" : "Offline / Unbound")")
        lines.append("")

        // 2. Subsystem Permissions
        lines.append("## 2. macOS Permissions & Entitlements")
        let axStatus = context.permissionStatus.accessibilityGranted ? "Granted (Exact window focus enabled)" : "Not Granted (Application-level fallback)"
        lines.append("- **Accessibility Authorization (`AXUIElement`):** \(axStatus)")
        let notifStatus = context.permissionStatus.notificationsGranted ? "Authorized (Alerts & banners enabled)" : "Not Authorized (Disabled)"
        lines.append("- **User Notifications Authorization:** \(notifStatus)")
        lines.append("- **Launch at Login Status:** \(context.permissionStatus.launchAtLoginStatus.displayName)")
        lines.append("")

        // 3. Agent Providers
        lines.append("## 3. Registered Agent Providers")
        if context.providerHealths.isEmpty {
            lines.append("*No providers registered.*")
        } else {
            for prov in context.providerHealths {
                let status = prov.isHealthy ? "Operational" : (prov.isInstalled ? "Attention Needed" : "Not Detected")
                let ver = prov.version.map { " v\($0)" } ?? ""
                let sanitizedMsg = sanitizeTextAndPaths(prov.statusMessage)
                lines.append("- **\(prov.displayName)**\(ver): `[\(status)]` — \(sanitizedMsg)")
            }
        }
        lines.append("")

        // 4. Policy Configuration
        lines.append("## 4. Active Policy Configuration")
        lines.append("- **Schema Version:** \(context.configuration.schemaVersion)")
        lines.append("- **Focus Policy:** \(context.configuration.focusPolicy.displayName)")
        lines.append("- **Space Policy:** \(context.configuration.spacePolicy.displayName)")
        lines.append("- **Completion Behavior:** \(context.configuration.completionBehavior.displayName)")
        lines.append("- **Permission Behavior:** \(context.configuration.permissionBehavior.displayName)")
        lines.append("- **Failure Behavior:** \(context.configuration.failureBehavior.displayName)")
        lines.append("- **Focus Cooldown:** \(context.configuration.focusCooldownMs) ms")
        lines.append("- **Attention Aggregation:** \(context.configuration.attentionAggregationMs) ms")
        lines.append("- **Active Interaction Threshold:** \(String(format: "%.1f", context.configuration.activeInteractionThresholdSeconds)) s")
        lines.append("- **Launch at Login:** \(context.configuration.launchAtLogin)")
        lines.append("- **Protected Applications (\(context.configuration.protectedApplications.count)):**")
        for app in context.configuration.protectedApplications.sorted() {
            lines.append("  - `\(sanitizeTextAndPaths(app))`")
        }
        if !context.configuration.providerOverrides.isEmpty {
            lines.append("- **Provider Overrides:**")
            for (prov, policy) in context.configuration.providerOverrides.sorted(by: { $0.key < $1.key }) {
                lines.append("  - `\(sanitizeTextAndPaths(prov))`: \(policy.displayName)")
            }
        }
        lines.append("")

        // 5. Recent Orchestration Events (Sanitized)
        lines.append("## 5. Recent Orchestration Decisions")
        if context.recentTimeline.isEmpty {
            lines.append("*No recent events in active timeline.*")
        } else {
            for entry in context.recentTimeline.prefix(15) {
                let cat = entry.category.uppercased()
                let summary = sanitizeTextAndPaths(entry.summary)
                let detailsText = entry.details.map { ": " + sanitizeTextAndPaths($0) } ?? ""
                let explanation = entry.decisionExplanation.map { " (\(sanitizeTextAndPaths($0)))" } ?? ""
                lines.append("- `[\(cat)]` **\(summary)**\(detailsText)\(explanation)")
            }
        }
        lines.append("")

        lines.append("---")
        lines.append("*End of Flowback Diagnostic Report*")

        return lines.joined(separator: "\n")
    }

    #if canImport(AppKit)
    /// Runs a native macOS save panel on the main actor to save the report to disk
    @MainActor
    public static func runSavePanel(reportContent: String) -> (saved: Bool, path: String?, error: String?) {
        let panel = NSSavePanel()
        panel.title = "Save Flowback Diagnostic Report"
        panel.message = "Choose a destination for the sanitized diagnostic report."
        panel.nameFieldStringValue = "flowback-diagnostics-\(Int(Date().timeIntervalSince1970)).md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let targetURL = panel.url else {
            return (false, nil, nil)
        }

        do {
            try reportContent.write(to: targetURL, atomically: true, encoding: .utf8)
            return (true, targetURL.path, nil)
        } catch {
            return (false, targetURL.path, error.localizedDescription)
        }
    }
    #endif
}
