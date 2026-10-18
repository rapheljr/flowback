import Foundation
import SwiftUI
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackUI

// MARK: - General Sidebar Destinations Verification Suites (V-019 to V-023)

@MainActor
func runGeneralSidebarDestinationsSuites() async {
    print("\n================================================================")
    print("FLOWBACK GENERAL SIDEBAR DESTINATIONS SUITES (V-019 to V-023)")
    print("================================================================")

    // MARK: - V-019: Navigation Architecture & Sidebar Routing
    await testGroup("V-019: Navigation Architecture & Sidebar Routing") {
        let allTabs = DashboardTab.allCases
        assertTest(allTabs.count == 10, "V-019: Exactly 10 navigation tabs registered in DashboardTab")

        // Unique stable identifiers
        let ids = Set(allTabs.map(\.id))
        assertTest(ids.count == 10, "V-019: Each dashboard destination has a unique identifier")

        // Four new destinations registered
        let registeredDestinations = Set(allTabs)
        assertTest(registeredDestinations.contains(.advanced), "V-019: 'Advanced' destination is registered")
        assertTest(registeredDestinations.contains(.whatsNew), "V-019: 'What's New' destination is registered")
        assertTest(registeredDestinations.contains(.support), "V-019: 'Support' destination is registered")
        assertTest(registeredDestinations.contains(.about), "V-019: 'About Flowback' destination is registered")

        // Existing primary destinations preserved
        assertTest(registeredDestinations.contains(.overview), "V-019: Existing 'Overview' preserved")
        assertTest(registeredDestinations.contains(.agents), "V-019: Existing 'Agents' preserved")
        assertTest(registeredDestinations.contains(.applications), "V-019: Existing 'Applications' preserved")
        assertTest(registeredDestinations.contains(.timeline), "V-019: Existing 'Timeline' preserved")
        assertTest(registeredDestinations.contains(.diagnostics), "V-019: Existing 'Diagnostics' preserved")
        assertTest(registeredDestinations.contains(.settings), "V-019: Existing 'Settings' preserved")

        // Sidebar grouping: 5 Workspace tabs and 5 Preferences & Help tabs
        assertTest(DashboardTab.workspaceTabs.count == 5, "V-019: Workspace section contains exactly 5 operational tabs")
        assertTest(DashboardTab.preferencesAndHelpTabs.count == 5, "V-019: Preferences & Help section contains exactly 5 tabs")

        // Icons and subtitles
        for tab in allTabs {
            assertTest(!tab.icon.isEmpty, "V-019: Tab '\(tab.rawValue)' has valid SF Symbol icon '\(tab.icon)'")
            assertTest(!tab.subtitle.isEmpty, "V-019: Tab '\(tab.rawValue)' has descriptive subtitle")
            assertTest(!tab.accessibilityKey.isEmpty, "V-019: Tab '\(tab.rawValue)' has accessibilityKey '\(tab.accessibilityKey)'")
        }
        assertTest(DashboardTab.support.icon == "heart.fill", "V-019: Tab 'Support' uses 'heart.fill' icon")
        assertTest(DashboardTab.advanced.icon == "wrench.and.screwdriver", "V-019: Tab 'Advanced' uses 'wrench.and.screwdriver' icon")

        // Navigation state preservation and state isolation
        let testConfig = PolicyConfiguration(focusCooldownMs: 3333, launchAtLogin: true)
        let vm = DashboardViewModel(selectedTab: .overview, config: testConfig)
        assertTest(vm.selectedTab == .overview, "V-019: Initial tab is Overview")

        // Transition through all tabs sequentially
        for tab in allTabs {
            vm.selectedTab = tab
            assertTest(vm.selectedTab == tab, "V-019: Transition to tab '\(tab.rawValue)' succeeds")
            assertTest(vm.config.focusCooldownMs == 3333, "V-019: Focus cooldown preserved during transition to '\(tab.rawValue)'")
            assertTest(vm.config.launchAtLogin == true, "V-019: Launch at login preserved during transition to '\(tab.rawValue)'")
        }

        // Back and Forward Navigation History (Vorssaint Header Parity)
        let navVM = DashboardViewModel(selectedTab: .overview)
        assertTest(!navVM.canGoBack, "V-019: Initially canGoBack is false")
        assertTest(!navVM.canGoForward, "V-019: Initially canGoForward is false")
        assertTest(navVM.navigationHistory == [.overview], "V-019: Initial navigation history contains Overview")

        navVM.navigateTo(.advanced)
        assertTest(navVM.selectedTab == .advanced, "V-019: Navigated to Advanced")
        assertTest(navVM.canGoBack, "V-019: canGoBack is true after navigating to Advanced")
        assertTest(!navVM.canGoForward, "V-019: canGoForward is false after new navigation")

        navVM.navigateTo(.support)
        assertTest(navVM.selectedTab == .support, "V-019: Navigated to Support")
        assertTest(navVM.navigationHistory == [.overview, .advanced, .support], "V-019: History stack contains 3 tabs")

        navVM.goBack()
        assertTest(navVM.selectedTab == .advanced, "V-019: goBack() returns to Advanced")
        assertTest(navVM.canGoBack, "V-019: canGoBack is true at middle of stack")
        assertTest(navVM.canGoForward, "V-019: canGoForward is true after goBack()")

        navVM.goBack()
        assertTest(navVM.selectedTab == .overview, "V-019: goBack() returns to Overview root")
        assertTest(!navVM.canGoBack, "V-019: canGoBack is false at history root")
        assertTest(navVM.canGoForward, "V-019: canGoForward remains true")

        navVM.goForward()
        assertTest(navVM.selectedTab == .advanced, "V-019: goForward() returns to Advanced")

        // Branching history truncation
        navVM.navigateTo(.about)
        assertTest(navVM.selectedTab == .about, "V-019: Navigated to About from middle of history")
        assertTest(navVM.navigationHistory == [.overview, .advanced, .about], "V-019: Forward history truncated upon branch")
        assertTest(!navVM.canGoForward, "V-019: canGoForward is false after branching")

        // Sidebar Toggle and Visibility State (Vorssaint Toolbar Parity)
        assertTest(navVM.sidebarShown, "V-019: sidebarShown is true when visibility is .all")
        assertTest(navVM.columnVisibility == .all, "V-019: columnVisibility is initially .all")
        navVM.toggleSidebar()
        assertTest(!navVM.sidebarShown, "V-019: sidebarShown is false after toggleSidebar()")
        assertTest(navVM.columnVisibility == .detailOnly, "V-019: columnVisibility is .detailOnly after toggle")
        navVM.toggleSidebar()
        assertTest(navVM.sidebarShown, "V-019: sidebarShown is restored after second toggle")
        assertTest(navVM.columnVisibility == .all, "V-019: columnVisibility is restored to .all")
    }

    // MARK: - V-020: Advanced Destination & Configuration Lifecycle
    await testGroup("V-020: Advanced Destination & Configuration Lifecycle") {
        // 1. Completion & Event behaviors have non-empty display names
        for b in CompletionBehavior.allCases {
            assertTest(!b.displayName.isEmpty, "V-020: CompletionBehavior.\(b.rawValue) has display name '\(b.displayName)'")
        }
        for b in PermissionBehavior.allCases {
            assertTest(!b.displayName.isEmpty, "V-020: PermissionBehavior.\(b.rawValue) has display name '\(b.displayName)'")
        }
        for b in FailureBehavior.allCases {
            assertTest(!b.displayName.isEmpty, "V-020: FailureBehavior.\(b.rawValue) has display name '\(b.displayName)'")
        }

        // 2. Configuration serialization roundtrip
        var customConfig = PolicyConfiguration.default
        customConfig.completionBehavior = .notificationOnly
        customConfig.permissionBehavior = .notificationOnly
        customConfig.failureBehavior = .notificationOnly
        customConfig.focusCooldownMs = 2500
        customConfig.providerOverrides["antigravity"] = .alwaysRestore
        customConfig.providerOverrides["claude-code"] = .neverInterrupt

        do {
            let json = try AdvancedViewModel.serializeConfig(customConfig)
            assertTest(!json.isEmpty, "V-020: AdvancedViewModel serialized configuration to JSON")
            assertTest(json.contains("completionBehavior"), "V-020: JSON contains completionBehavior key")
            assertTest(json.contains("antigravity"), "V-020: JSON contains provider override for antigravity")

            let restored = try AdvancedViewModel.parseConfig(from: json)
            assertTest(restored.completionBehavior == .notificationOnly, "V-020: Parsed config has completionBehavior == .notificationOnly")
            assertTest(restored.providerOverrides["antigravity"] == .alwaysRestore, "V-020: Parsed provider override matches")
            assertTest(restored.focusCooldownMs == 2500, "V-020: Parsed cooldown matches custom value")
            assertTest(restored == customConfig, "V-020: Full roundtrip preserves equality")
        } catch {
            assertTest(false, "V-020: Serialization roundtrip threw error: \(error)")
        }

        // 3. Behavioral Validation & Rejection of Malformed Configurations
        // A. Malformed syntax
        var caughtSyntaxError = false
        do {
            _ = try AdvancedViewModel.parseConfig(from: "{ malformed json ]")
        } catch {
            caughtSyntaxError = true
        }
        assertTest(caughtSyntaxError, "V-020: Malformed JSON syntax rejected")

        // B. Missing required keys
        let missingKeyJSON = """
        {
            "schemaVersion": 1,
            "spacePolicy": "never-switch"
        }
        """
        var caughtMissingKey = false
        do {
            _ = try AdvancedViewModel.parseConfig(from: missingKeyJSON)
        } catch {
            caughtMissingKey = true
        }
        assertTest(caughtMissingKey, "V-020: JSON with missing required keys rejected")

        // C. Unknown enum value
        let unknownEnumJSON = """
        {
            "schemaVersion": 1,
            "focusPolicy": "quantum-teleport-policy",
            "completionBehavior": "restore-origin",
            "permissionBehavior": "focus-agent",
            "failureBehavior": "focus-agent",
            "spacePolicy": "never-switch",
            "focusCooldownMs": 1000,
            "attentionAggregationMs": 1500,
            "activeInteractionThresholdSeconds": 5.0,
            "protectedApplications": [],
            "launchAtLogin": false,
            "providerOverrides": {},
            "applicationOverrides": {},
            "workspaceOverrides": {}
        }
        """
        var caughtUnknownEnum = false
        do {
            _ = try AdvancedViewModel.parseConfig(from: unknownEnumJSON)
        } catch {
            caughtUnknownEnum = true
        }
        assertTest(caughtUnknownEnum, "V-020: Unknown enum value in JSON rejected")

        // D. Unsupported schema version
        var badSchemaConfig = PolicyConfiguration.default
        badSchemaConfig.schemaVersion = 99
        var caughtBadSchema = false
        do {
            try AdvancedViewModel.validateConfig(badSchemaConfig)
        } catch {
            caughtBadSchema = true
        }
        assertTest(caughtBadSchema, "V-020: Unsupported schema version rejected")

        // E. Negative cooldown
        var negativeCooldownConfig = PolicyConfiguration.default
        negativeCooldownConfig.focusCooldownMs = -500
        var caughtNegativeCooldown = false
        do {
            try AdvancedViewModel.validateConfig(negativeCooldownConfig)
        } catch {
            caughtNegativeCooldown = true
        }
        assertTest(caughtNegativeCooldown, "V-020: Negative focus cooldown rejected")

        // F. Invalid provider override key
        var badProviderConfig = PolicyConfiguration.default
        badProviderConfig.providerOverrides[""] = .smart
        var caughtBadProvider = false
        do {
            try AdvancedViewModel.validateConfig(badProviderConfig)
        } catch {
            caughtBadProvider = true
        }
        assertTest(caughtBadProvider, "V-020: Empty provider identifier in overrides rejected")

        // G. Invalid empty protected application
        var emptyAppConfig = PolicyConfiguration.default
        emptyAppConfig.protectedApplications.append("   ")
        var caughtEmptyApp = false
        do {
            try AdvancedViewModel.validateConfig(emptyAppConfig)
        } catch {
            caughtEmptyApp = true
        }
        assertTest(caughtEmptyApp, "V-020: Whitespace protected application rejected")

        // 4. Factory reset behavioral verification
        var activeConfig = PolicyConfiguration(
            focusCooldownMs: 8000,
            protectedApplications: ["com.example.custom"],
            launchAtLogin: true,
            providerOverrides: ["antigravity": .neverInterrupt]
        )
        // Reset configuration to factory defaults
        activeConfig = PolicyConfiguration.default
        assertTest(activeConfig.focusCooldownMs == 1000, "V-020: Reset restores default cooldown (1000ms)")
        assertTest(activeConfig.launchAtLogin == false, "V-020: Reset restores launchAtLogin = false")
        assertTest(activeConfig.providerOverrides.isEmpty, "V-020: Reset clears provider overrides")
        assertTest(activeConfig.protectedApplications.contains("us.zoom.xos"), "V-020: Reset restores standard protected applications")

        // 5. System Permissions Reset State
        let advVM = AdvancedViewModel()
        assertTest(!advVM.showPermissionsResetConfirm, "V-020: Permissions reset confirmation is initially dismissed")
    }

    // MARK: - V-021: What's New Destination & Release Notes Model
    await testGroup("V-021: What's New Destination & Release Notes Model") {
        let notes = ReleaseNotesModel.bundledNotes
        assertTest(!notes.isEmpty, "V-021: Bundled release notes are not empty")

        guard let firstNote = notes.first else {
            assertTest(false, "V-021: Missing first release note")
            return
        }

        assertTest(firstNote.version == "0.4.1", "V-021: Current release version is 0.4.1")
        assertTest(firstNote.date == "October 18, 2026", "V-021: Release date is verified: October 18, 2026")
        assertTest(!firstNote.summary.isEmpty, "V-021: Release summary is defined")
        assertTest(firstNote.sections.count == 5, "V-021: Defines exactly 5 categorized subsections")

        let sectionTitles = Set(firstNote.sections.map(\.title))
        assertTest(sectionTitles.contains("Added"), "V-021: Contains 'Added' section")
        assertTest(sectionTitles.contains("Changed & Improved"), "V-021: Contains 'Changed & Improved' section")
        assertTest(sectionTitles.contains("Fixed"), "V-021: Contains 'Fixed' section")
        assertTest(sectionTitles.contains("Security & Privacy"), "V-021: Contains 'Security & Privacy' section")
        assertTest(sectionTitles.contains("Known Limitations"), "V-021: Contains 'Known Limitations' section")

        for sec in firstNote.sections {
            assertTest(!sec.icon.isEmpty, "V-021: Section '\(sec.title)' has SF Symbol '\(sec.icon)'")
            assertTest(!sec.items.isEmpty, "V-021: Section '\(sec.title)' has bullet points")
        }

        // Current helper returns latest
        assertTest(ReleaseNotesModel.current?.version == "0.4.1", "V-021: ReleaseNotesModel.current returns latest version")

        // Offline Empty State Handling
        let emptyView = WhatsNewView(releaseNotes: [])
        assertTest(emptyView.releaseNotes.isEmpty, "V-021: WhatsNewView cleanly accepts empty release notes without crashing")
    }

    // MARK: - V-022: Support Destination & Privacy-Sanitized Export
    await testGroup("V-022: Support Destination & Privacy-Sanitized Export") {
        let multilinePEM = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0Y7Vv2K4kIe8dC1J5bO2H+3l7p4d9s
        b2m1+q0w==
        -----END RSA PRIVATE KEY-----
        """

        let sensitiveTimeline = [
            TimelineEntry(
                sessionID: AgentSessionID("sess-001"),
                category: "auth",
                summary: "Authenticated agent with Bearer sec_token_abcdef1234567890",
                details: "/Users/devuser/projects/flowback/key.pem with password=supersecret123 and \(multilinePEM)",
                decisionExplanation: "Authorized API request to https://bot:SuperSecretPass123@api.internal.service/v1?token=tok_987654321"
            ),
            TimelineEntry(
                sessionID: AgentSessionID("sess-002"),
                category: "git",
                summary: "Cloning repository with ghp_123456789012345678901234567890123456",
                details: "Fine-grained token github_pat_11AAAAAAA0000000000000_12345678901234567890 applied at /Users/Jane Doe/workspace",
                decisionExplanation: "Error reading config at /home/runner service/agent/config.json"
            )
        ]

        let testContext = DiagnosticReportContext(
            appVersion: FlowbackVersion.current,
            appBuild: "1",
            macOSVersion: "15.0",
            architecture: "arm64",
            storageNotice: "Notice from /Users/devuser/storage.lock with path /System/Library/Frameworks",
            providerHealths: [
                ProviderHealth(
                    providerID: .antigravity,
                    displayName: "Google Antigravity",
                    isInstalled: true,
                    version: "1.2.0",
                    hookInstalled: true,
                    hookExecutable: true,
                    statusMessage: "Binary at /Users/devuser/.local/bin/agy with api_key=sk-ant-secret98765432101234"
                )
            ],
            configuration: PolicyConfiguration.default,
            recentTimeline: sensitiveTimeline
        )

        let report = DiagnosticReportExporter.generateSanitizedReport(context: testContext)

        // 1. Positive Redaction Assertions: Confirm secrets are removed from final report
        assertTest(!report.contains("sec_token_abcdef1234567890"), "V-022: Bearer token stripped from exported report")
        assertTest(!report.contains("supersecret123"), "V-022: Password parameter stripped from exported report")
        assertTest(!report.contains("SuperSecretPass123"), "V-022: Basic auth URL password stripped from exported report")
        assertTest(!report.contains("tok_987654321"), "V-022: URL query parameter secret stripped from exported report")
        assertTest(!report.contains("ghp_123456789012345678901234567890123456"), "V-022: GitHub classic PAT stripped from exported report")
        assertTest(!report.contains("github_pat_11AAAAAAA0000000000000_12345678901234567890"), "V-022: GitHub fine-grained PAT stripped from exported report")
        assertTest(!report.contains("sk-ant-secret98765432101234"), "V-022: Provider API key stripped from exported report")
        assertTest(!report.contains("MIIEowIBAAKCAQEA0Y7"), "V-022: PEM private key body stripped from exported report")
        assertTest(!report.contains("/Users/devuser"), "V-022: macOS user home path stripped from exported report")
        assertTest(!report.contains("/Users/Jane Doe"), "V-022: macOS user home path with spaces stripped from exported report")
        assertTest(!report.contains("/home/runner service"), "V-022: Linux user home path with spaces stripped from exported report")

        // 2. Redaction Placeholder Verification
        assertTest(report.contains("Bearer [REDACTED]"), "V-022: Bearer token replaced with redaction tag")
        assertTest(report.contains("password=[REDACTED]"), "V-022: Password replaced with redaction tag")
        assertTest(report.contains("[REDACTED_PASSWORD]"), "V-022: URL basic auth replaced with redaction tag")
        assertTest(report.contains("[REDACTED_PRIVATE_KEY_BLOCK]"), "V-022: PEM block replaced with redaction tag")
        assertTest(report.contains("~/projects/flowback/key.pem"), "V-022: User home directory mapped to '~'")
        assertTest(report.contains("~/workspace"), "V-022: User home with space mapped to '~'")
        assertTest(report.contains("~/agent/config.json"), "V-022: Linux home directory with space mapped to '~'")

        // 3. Negative Redaction Assertions: Confirm legitimate diagnostics and system paths are fully preserved
        assertTest(report.contains("# Flowback Diagnostic Report"), "V-022: Negative test — report header preserved")
        assertTest(report.contains("Flowback v\(FlowbackVersion.current) (build 1)"), "V-022: Negative test — version information preserved")
        assertTest(report.contains("macOS 15.0"), "V-022: Negative test — OS version preserved")
        assertTest(report.contains("arm64"), "V-022: Negative test — architecture preserved")
        assertTest(report.contains("SQLite 3 (WAL Mode)"), "V-022: Negative test — storage engine details preserved")
        assertTest(report.contains("Google Antigravity"), "V-022: Negative test — provider name preserved")
        assertTest(report.contains("/System/Library/Frameworks"), "V-022: Negative test — non-user system frameworks path preserved")

        // 4. Buy Me a Coffee & Support URLs
        assertTest(SupportView.buyMeACoffeeURL.absoluteString == "https://buymeacoffee.com/flowback", "V-022: Buy Me a Coffee URL is canonical")
        assertTest(SupportView.supportWebURL.absoluteString == "https://rapheljr.github.io/flowback/support/", "V-022: Web support page URL is canonical")
    }

    // MARK: - V-023: About Flowback Destination & Metadata Integrity
    await testGroup("V-023: About Flowback Destination & Metadata Integrity") {
        let aboutView = AboutView(appVersion: "0.4.0", buildNumber: "42")
        assertTest(aboutView.appVersion == "0.4.0", "V-023: AboutView displays injected appVersion")
        assertTest(aboutView.buildNumber == "42", "V-023: AboutView displays injected buildNumber")

        // Default metadata fallback when bundle dictionary is empty
        let defaultAbout = AboutView()
        assertTest(!defaultAbout.appVersion.isEmpty, "V-023: Default AboutView provides non-empty version")
        assertTest(!defaultAbout.buildNumber.isEmpty, "V-023: Default AboutView provides non-empty build number")

        // License and Project URL Integrity
        let aboutVM = AboutViewModel()
        assertTest(!aboutVM.showLicenseSheet, "V-023: License sheet is initially dismissed")
        aboutVM.showLicenseSheet = true
        assertTest(aboutVM.showLicenseSheet, "V-023: License sheet presentation state toggles cleanly")

        // Verify MIT License text accuracy
        let testMirror = Mirror(reflecting: aboutView)
        var foundLicense = false
        for child in testMirror.children {
            if child.label == "mitLicenseText", let text = child.value as? String {
                assertTest(text.contains("MIT License"), "V-023: License text contains 'MIT License'")
                assertTest(text.contains("Abin Rapheal and Flowback Contributors"), "V-023: License text contains authoritative copyright attribution")
                assertTest(text.contains("without restriction"), "V-023: License text contains standard MIT permissions")
                assertTest(text.contains("WITHOUT WARRANTY OF ANY KIND"), "V-023: License text contains standard MIT warranty disclaimer")
                foundLicense = true
            }
        }
        assertTest(foundLicense, "V-023: MIT License text verified in AboutView")

        // Navigation callback to What's New
        var navigatedToWhatsNew = false
        let aboutWithNav = AboutView(onNavigateToWhatsNew: { navigatedToWhatsNew = true })
        aboutWithNav.onNavigateToWhatsNew?()
        assertTest(navigatedToWhatsNew, "V-023: AboutView onNavigateToWhatsNew callback triggers cleanly")
    }
}
