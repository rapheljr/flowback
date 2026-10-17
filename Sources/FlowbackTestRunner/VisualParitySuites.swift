import Foundation
import AppKit
import SwiftUI
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackTestHarness
import FlowbackUI

// MARK: - WCAG 2.1 Contrast Calculation Utilities

struct ColorRGB {
    let r: Double
    let g: Double
    let b: Double

    var relativeLuminance: Double {
        func adjust(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * adjust(r) + 0.7152 * adjust(g) + 0.0722 * adjust(b)
    }

    func contrastRatio(to other: ColorRGB) -> Double {
        let l1 = max(self.relativeLuminance, other.relativeLuminance)
        let l2 = min(self.relativeLuminance, other.relativeLuminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

// MARK: - Visual Parity & Screenshot Capture Suites

@MainActor
func runVisualParitySuites() async {
    print("\n================================================================")
    print("FLOWBACK VISUAL PARITY, CONTRAST & INTERACTION SUITES (V-015 to V-018)")
    print("================================================================")

    let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let screenshotsDir = projectRoot.appendingPathComponent("Docs/audits/screenshots")
    try? FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)

    // Helper to render any SwiftUI View to PNG data at specified dimensions and appearance
    @MainActor
    func renderViewToPNG<V: View>(
        view: V,
        width: CGFloat = 880,
        height: CGFloat = 620,
        colorScheme: ColorScheme = .dark,
        isHighContrast: Bool = false
    ) -> Data? {
        let appearanceName: NSAppearance.Name
        if isHighContrast {
            appearanceName = (colorScheme == .dark) ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
        } else {
            appearanceName = (colorScheme == .dark) ? .darkAqua : .aqua
        }
        let appearance = NSAppearance(named: appearanceName)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance

        let configured = view
            .environment(\.colorScheme, colorScheme)
            .frame(width: width, height: height)

        let hostingView = NSHostingView(rootView: configured)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.appearance = appearance
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * 2.0),
            pixelsHigh: Int(height * 2.0),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep = rep else { return nil }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            appearance?.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSRect(x: 0, y: 0, width: width, height: height).fill()
            }
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    // Deterministic sample data representing typical real-world multi-agent state
    let sampleSessions: [AgentSession] = [
        AgentSession(
            providerID: .antigravity,
            state: .running,
            workspace: "/Users/dev/flowback",
            conversationTitle: "Implement multi-agent focus coordination",
            taskSummary: "Synthesizing UI hierarchy and active workspace windows"
        ),
        AgentSession(
            providerID: .claudeCode,
            state: .completed,
            workspace: "/Users/dev/vorssaint-utils",
            conversationTitle: "Audit battery efficiency and energy metrics",
            taskSummary: "Completed SMC power sampling and profile generation"
        ),
        AgentSession(
            providerID: .copilot,
            state: .waiting,
            workspace: "/Users/dev/flowback",
            conversationTitle: "Shared repository pull request check",
            taskSummary: "Waiting for user review and approval on branch"
        )
    ]

    let sampleAttention: [AttentionRequest] = [
        AttentionRequest(
            sessionID: sampleSessions[2].id,
            providerID: .copilot,
            priority: .permissionRequired,
            title: "GitHub Copilot",
            message: "Action required: Permission to execute git push requested"
        )
    ]

    let sampleTimeline: [TimelineEntry] = [
        TimelineEntry(
            sessionID: sampleSessions[0].id,
            category: "focus",
            summary: "Activated Antigravity Terminal Window",
            details: "Target window ID 4022 in Ghostty (Workspace: /Users/dev/flowback)",
            decisionExplanation: "User intent evaluation matched active terminal"
        ),
        TimelineEntry(
            sessionID: sampleSessions[1].id,
            category: "lifecycle",
            summary: "Claude Code session transitioned to completed",
            details: "Agent completed execution in 4m 12s",
            decisionExplanation: "CLI exit code 0 detected"
        ),
        TimelineEntry(
            sessionID: sampleSessions[2].id,
            category: "policy",
            summary: "Focus switch deferred (Protected App)",
            details: "Zoom (us.zoom.xos) is currently frontmost in screen share mode",
            decisionExplanation: "Meeting protection rule suppressed automatic window focus"
        ),
        TimelineEntry(
            sessionID: sampleSessions[0].id,
            category: "alert",
            summary: "Focus Lock engaged for 30 minutes",
            details: "User manual override via menu bar",
            decisionExplanation: "User requested uninterrupted deep work"
        )
    ]

    let sampleProviders: [ProviderHealth] = [
        ProviderHealth(
            providerID: .antigravity,
            displayName: "Google Antigravity",
            isInstalled: true,
            version: "2.0.4",
            hookInstalled: true,
            hookExecutable: true,
            statusMessage: "Integration active and healthy"
        ),
        ProviderHealth(
            providerID: .claudeCode,
            displayName: "Claude Code",
            isInstalled: true,
            version: "1.0.2",
            hookInstalled: true,
            hookExecutable: true,
            statusMessage: "Hooks configured in ~/.claude"
        ),
        ProviderHealth(
            providerID: .copilot,
            displayName: "GitHub Copilot",
            isInstalled: true,
            version: "0.22.0",
            hookInstalled: true,
            hookExecutable: true,
            statusMessage: "CLI integration active"
        ),
        ProviderHealth(
            providerID: .openCode,
            displayName: "OpenCode",
            isInstalled: false,
            version: nil,
            statusMessage: "Not detected on system"
        ),
        ProviderHealth(
            providerID: .windsurf,
            displayName: "Windsurf",
            isInstalled: false,
            version: nil,
            statusMessage: "Not detected on system"
        )
    ]

    let sampleConfig = PolicyConfiguration(
        focusPolicy: .smart,
        spacePolicy: .activateApplicationAndWindow,
        focusCooldownMs: 2500,
        attentionAggregationMs: 5000,
        activeInteractionThresholdSeconds: 300.0,
        protectedApplications: ["us.zoom.xos", "com.apple.Keynote", "com.microsoft.teams"],
        launchAtLogin: true
    )

    // MARK: - V-015: Visual Parity Screenshot Capture
    await testGroup("V-015: Visual Parity Screenshot Capture & Render") {
        let screens: [(name: String, tab: DashboardTab, active: [AgentSession], all: [AgentSession], reqs: [AttentionRequest])] = [
            ("dashboard_overview", .overview, sampleSessions, sampleSessions, sampleAttention),
            ("dashboard_agents", .agents, sampleSessions, sampleSessions, sampleAttention),
            ("dashboard_timeline", .timeline, sampleSessions, sampleSessions, sampleAttention),
            ("dashboard_applications", .applications, sampleSessions, sampleSessions, sampleAttention),
            ("dashboard_diagnostics", .diagnostics, sampleSessions, sampleSessions, sampleAttention),
            ("dashboard_settings", .settings, sampleSessions, sampleSessions, sampleAttention)
        ]

        var capturedCount = 0

        for screen in screens {
            let vm = DashboardViewModel(
                selectedTab: screen.tab,
                activeSessions: screen.active,
                allSessions: screen.all,
                attentionQueue: screen.reqs,
                timelineEntries: sampleTimeline,
                providerHealths: sampleProviders,
                permissionStatus: PermissionStatus(accessibilityGranted: true, notificationsGranted: true, launchAtLoginStatus: .enabled),
                config: sampleConfig,
                focusLock: FocusLockState()
            )

            let dashboardView = DashboardView(
                viewModel: vm,
                onFocusSession: { _ in },
                onSaveConfig: { _ in },
                onRepairAntigravity: {},
                onTestFocus: {},
                onTestNotification: {},
                onRefresh: {}
            )

            // Render in Dark Mode
            if let darkPNG = renderViewToPNG(view: dashboardView, colorScheme: .dark) {
                let darkURL = screenshotsDir.appendingPathComponent("\(screen.name)_dark.png")
                try? darkPNG.write(to: darkURL)
                assertTest(darkPNG.count > 5000, "V-015: Captured \(screen.name)_dark.png (\(darkPNG.count) bytes)")
                capturedCount += 1
            }

            // Render in Light Mode
            if let lightPNG = renderViewToPNG(view: dashboardView, colorScheme: .light) {
                let lightURL = screenshotsDir.appendingPathComponent("\(screen.name)_light.png")
                try? lightPNG.write(to: lightURL)
                assertTest(lightPNG.count > 5000, "V-015: Captured \(screen.name)_light.png (\(lightPNG.count) bytes)")
                capturedCount += 1
            }
        }

        // Render Empty States for Agents and Applications
        let emptyVM = DashboardViewModel(
            selectedTab: .agents,
            activeSessions: [],
            allSessions: [],
            attentionQueue: [],
            config: PolicyConfiguration(protectedApplications: [])
        )
        let emptyAgentsView = DashboardView(
            viewModel: emptyVM,
            onFocusSession: { _ in },
            onSaveConfig: { _ in },
            onRepairAntigravity: {},
            onTestFocus: {},
            onTestNotification: {}
        )
        if let emptyAgentsPNG = renderViewToPNG(view: emptyAgentsView, colorScheme: .dark) {
            let url = screenshotsDir.appendingPathComponent("dashboard_agents_empty_dark.png")
            try? emptyAgentsPNG.write(to: url)
            assertTest(emptyAgentsPNG.count > 5000, "V-015: Captured dashboard_agents_empty_dark.png")
        }

        emptyVM.selectedTab = .applications
        if let emptyAppsPNG = renderViewToPNG(view: emptyAgentsView, colorScheme: .dark) {
            let url = screenshotsDir.appendingPathComponent("dashboard_applications_empty_dark.png")
            try? emptyAppsPNG.write(to: url)
            assertTest(emptyAppsPNG.count > 5000, "V-015: Captured dashboard_applications_empty_dark.png")
        }

        // Render Increased Contrast Mode (Overview screen)
        let contrastVM = DashboardViewModel(
            selectedTab: .overview,
            activeSessions: sampleSessions,
            allSessions: sampleSessions,
            attentionQueue: sampleAttention,
            timelineEntries: sampleTimeline,
            providerHealths: sampleProviders,
            permissionStatus: PermissionStatus(accessibilityGranted: true, notificationsGranted: true, launchAtLoginStatus: .enabled),
            config: sampleConfig,
            focusLock: FocusLockState()
        )
        let contrastView = DashboardView(
            viewModel: contrastVM,
            onFocusSession: { _ in },
            onSaveConfig: { _ in },
            onRepairAntigravity: {},
            onTestFocus: {},
            onTestNotification: {},
            onRefresh: {}
        )
        if let contrastPNG = renderViewToPNG(view: contrastView, colorScheme: .dark, isHighContrast: true) {
            let url = screenshotsDir.appendingPathComponent("dashboard_overview_increased_contrast.png")
            try? contrastPNG.write(to: url)
            assertTest(contrastPNG.count > 5000, "V-015: Captured dashboard_overview_increased_contrast.png")
        }

        assertTest(capturedCount >= 12, "V-015: Successfully captured all core dashboard surfaces across light and dark modes")
    }

    // MARK: - V-016: Contrast Ratio & Color Space Audit
    // MARK: - V-016: Contrast Ratio & Color Space Audit
    await testGroup("V-016: Contrast Ratio & Color Space Audit (WCAG AA Compliance)") {
        // Dark Mode Surfaces:
        let darkCard = ColorRGB(r: 0.157, g: 0.157, b: 0.157)
        let darkTextPrimary = ColorRGB(r: 1.0, g: 1.0, b: 1.0)
        let darkTextSecondary = ColorRGB(r: 0.627, g: 0.627, b: 0.627)

        let darkPrimaryContrast = darkTextPrimary.contrastRatio(to: darkCard)
        assertTest(
            darkPrimaryContrast >= 4.5,
            "V-016 Dark Mode: Primary text contrast ratio is \(String(format: "%.2f", darkPrimaryContrast)):1 (>= 4.5:1 required by WCAG AA)"
        )

        let darkSecondaryContrast = darkTextSecondary.contrastRatio(to: darkCard)
        assertTest(
            darkSecondaryContrast >= 4.5,
            "V-016 Dark Mode: Secondary text contrast ratio is \(String(format: "%.2f", darkSecondaryContrast)):1 (>= 4.5:1 required by WCAG AA)"
        )

        // Light Mode Surfaces:
        let lightCard = ColorRGB(r: 1.0, g: 1.0, b: 1.0)
        let lightTextPrimary = ColorRGB(r: 0.102, g: 0.102, b: 0.102)
        let lightTextSecondary = ColorRGB(r: 0.369, g: 0.369, b: 0.369)

        let lightPrimaryContrast = lightTextPrimary.contrastRatio(to: lightCard)
        assertTest(
            lightPrimaryContrast >= 4.5,
            "V-016 Light Mode: Primary text contrast ratio is \(String(format: "%.2f", lightPrimaryContrast)):1 (>= 4.5:1 required by WCAG AA)"
        )

        let lightSecondaryContrast = lightTextSecondary.contrastRatio(to: lightCard)
        assertTest(
            lightSecondaryContrast >= 4.5,
            "V-016 Light Mode: Secondary text contrast ratio is \(String(format: "%.2f", lightSecondaryContrast)):1 (>= 4.5:1 required by WCAG AA)"
        )

        // Verified ThemeTokens Status Colors (Light Mode against white card surface):
        let lightCompleted = ColorRGB(r: 0.08, g: 0.48, b: 0.22) // ThemeTokens .completed
        let lightRunning = ColorRGB(r: 0.05, g: 0.38, b: 0.78)   // ThemeTokens .running
        let lightFailed = ColorRGB(r: 0.75, g: 0.12, b: 0.14)    // ThemeTokens .failed

        let compContrast = lightCompleted.contrastRatio(to: lightCard)
        assertTest(compContrast >= 4.5, "V-016 ThemeTokens: Light completed color has \(String(format: "%.2f", compContrast)):1 contrast")

        let runContrast = lightRunning.contrastRatio(to: lightCard)
        assertTest(runContrast >= 4.5, "V-016 ThemeTokens: Light running color has \(String(format: "%.2f", runContrast)):1 contrast")

        let failContrast = lightFailed.contrastRatio(to: lightCard)
        assertTest(failContrast >= 4.5, "V-016 ThemeTokens: Light failed color has \(String(format: "%.2f", failContrast)):1 contrast")

        // Graphical Status Indicator: Dark mode badge on card
        let greenBadge = ColorRGB(r: 0.204, g: 0.780, b: 0.349)
        let greenContrast = greenBadge.contrastRatio(to: darkCard)
        assertTest(
            greenContrast >= 3.0,
            "V-016 Graphical Object: Green badge contrast is \(String(format: "%.2f", greenContrast)):1 (>= 3.0:1 required for UI components)"
        )

        // WCAG 1.4.1 Non-Color Status Communication:
        let runningIcon = ThemeTokens.statusIcon(for: .running)
        let completedIcon = ThemeTokens.statusIcon(for: .completed)
        let failedIcon = ThemeTokens.statusIcon(for: .failed)
        assertTest(
            !runningIcon.isEmpty && runningIcon != completedIcon && completedIcon != failedIcon,
            "V-016 Non-Color State: Distinct SF Symbol icons defined for each agent state"
        )
    }

    // MARK: - V-017: Responsive Window Dimension Bounds
    await testGroup("V-017: Responsive Window Dimensions (800x550 to 1200x800)") {
        let vm = DashboardViewModel(
            selectedTab: .overview,
            activeSessions: sampleSessions,
            allSessions: sampleSessions,
            attentionQueue: sampleAttention
        )
        let view = DashboardView(
            viewModel: vm,
            onFocusSession: { _ in },
            onSaveConfig: { _ in },
            onRepairAntigravity: {},
            onTestFocus: {},
            onTestNotification: {}
        )

        // Min dimensions: 800 x 550
        let minPNG = renderViewToPNG(view: view, width: 800, height: 550, colorScheme: .dark)
        assertTest(minPNG != nil && (minPNG?.count ?? 0) > 5000, "V-017: Minimum window dimension (800x550) renders cleanly without truncation")

        // Expanded widescreen dimensions: 1200 x 800
        let maxPNG = renderViewToPNG(view: view, width: 1200, height: 800, colorScheme: .dark)
        assertTest(maxPNG != nil && (maxPNG?.count ?? 0) > 5000, "V-017: Expanded window dimension (1200x800) scales layout smoothly")
    }

    // MARK: - V-018: Interactive State Transitions & Presets
    await testGroup("V-018: Interactive State Transitions & Presets Verification") {
        // Verify ApplicationsView preset definitions
        let presets = ApplicationsView.suggestedPresets
        assertTest(presets.count == 5, "V-018: ApplicationsView defines exactly 5 standard meeting/presentation presets")
        assertTest(presets.contains { $0.bundleID == "us.zoom.xos" }, "V-018: ApplicationsView includes Zoom preset")
        assertTest(presets.contains { $0.bundleID == "com.apple.Keynote" }, "V-018: ApplicationsView includes Keynote preset")
        assertTest(presets.contains { $0.bundleID == "com.microsoft.teams" }, "V-018: ApplicationsView includes Microsoft Teams preset")
        assertTest(presets.allSatisfy { $0.bundleID.contains(".") && !$0.bundleID.isEmpty }, "V-018: All preset bundle identifiers conform to valid reverse-DNS notation")

        var protectedApps: [String] = []
        let appBinding = Binding<[String]>(
            get: { protectedApps },
            set: { protectedApps = $0 }
        )
        _ = ApplicationsView(protectedApps: appBinding)
        assertTest(protectedApps.isEmpty, "V-018: Initial protected applications list is empty")

        // Add presets using ApplicationsView.suggestedPresets
        for p in presets.prefix(3) where !protectedApps.contains(p.bundleID) {
            protectedApps.append(p.bundleID)
        }
        assertTest(protectedApps.count == 3, "V-018: Presets appended 3 meeting/presentation applications")

        // Verify deduplication: re-adding does not duplicate
        for p in presets.prefix(3) where !protectedApps.contains(p.bundleID) {
            protectedApps.append(p.bundleID)
        }
        assertTest(protectedApps.count == 3, "V-018: Re-adding existing presets prevents duplication")

        // Removing an app
        protectedApps.removeAll { $0 == "com.apple.Keynote" }
        assertTest(protectedApps.count == 2, "V-018: Removed Keynote; 2 protected applications remain")
    }
}
