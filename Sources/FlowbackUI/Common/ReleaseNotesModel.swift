import Foundation

/// Structured release note section with iconography and bullet points
public struct ReleaseNoteSection: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let items: [String]

    public init(title: String, icon: String, items: [String]) {
        self.id = title.lowercased().replacingOccurrences(of: " ", with: "-")
        self.title = title
        self.icon = icon
        self.items = items
    }
}

/// A structured, immutable model of a Flowback milestone release
public struct ReleaseNote: Identifiable, Sendable {
    public let id: String
    public let version: String
    public let date: String
    public let summary: String
    public let sections: [ReleaseNoteSection]

    public init(
        id: String,
        version: String,
        date: String,
        summary: String,
        sections: [ReleaseNoteSection]
    ) {
        self.id = id
        self.version = version
        self.date = date
        self.summary = summary
        self.sections = sections
    }
}

/// Authoritative provider of Flowback bundled release notes
public enum ReleaseNotesModel: Sendable {

    /// Canonical bundled release notes, sorted in reverse chronological order (latest first)
    public static let bundledNotes: [ReleaseNote] = [
        ReleaseNote(
            id: "release-0.4.0",
            version: "0.4.0",
            date: "October 18, 2026",
            summary: "Milestone v0.4.0 — Native macOS Card Design System, Copilot Provider & General Sidebar Destinations.",
            sections: [
                ReleaseNoteSection(
                    title: "Added",
                    icon: "plus.circle.fill",
                    items: [
                        "Universal Agent Providers: Complete native background integrations for Windsurf, OpenCode, " +
                        "Cursor background agent, and GitHub Copilot.",
                        "Antigravity CLI: Native process lifecycle hooks and full operational support for 'agy'.",
                        "Conversation-Aware Identity: Event resolution mapping directly to specific conversation threads with exact workspace restoration.",
                        "UI Event Coalescer: Throttles high-frequency multi-agent event bursts (up to 1,000 events) into single bounded UI passes.",
                        "Storage Engine v2: SQLite Schema v2 introducing conversation identifiers and metadata JSON with rollback safety.",
                        "macOS Card Design System: Full Apple Human Interface Guidelines and WCAG AA contrast compliance across light and dark modes.",
                        "General Sidebar Destinations: Advanced Settings (cooldown tuning, reset defaults), What's New feed, Support, and About Flowback.",
                        "Toolbar History: Back/forward navigation stack with persistent history."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Changed & Improved",
                    icon: "slider.horizontal.3",
                    items: [
                        "Canonical Version Source: Centralized authoritative metadata in FlowbackVersion.swift and root VERSION file.",
                        "Hardened Unix Domain Socket: Directory permissions restricted to 0700 with session authentication token for shutdown.",
                        "Non-Blocking Process Execution: AsyncProcessRunner prevents deadlocks on large pipe buffer outputs (>100KB)."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Fixed",
                    icon: "checkmark.circle.fill",
                    items: [
                        "AppKit application termination race during fast service shutdown.",
                        "Transcript parser JSON newline unescaping and redundant project path prefix stripping.",
                        "AppKit menu bar shortcut collision between active conversation shortcuts and system navigation."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Security & Privacy",
                    icon: "lock.shield.fill",
                    items: [
                        "Privacy-Guaranteed Diagnostic Exporter: Deterministic scrubbing of Bearer tokens, passwords, private keys, and user home paths.",
                        "100% Local Isolation: Zero outbound network connections and zero telemetry."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Known Limitations",
                    icon: "exclamationmark.triangle",
                    items: [
                        "macOS Window Server security policies govern window raising across distinct macOS Spaces.",
                        "Running without Accessibility permissions gracefully degrades to application-level switching rather than specific window raising."
                    ]
                )
            ]
        ),
        ReleaseNote(
            id: "release-0.3.0",
            version: "0.3.0",
            date: "October 17, 2026",
            summary: "Milestone v0.3.0 — Conversation Intelligence, Storage Engine v2 & Burst UI Event Coalescing.",
            sections: [
                ReleaseNoteSection(
                    title: "Added",
                    icon: "plus.circle.fill",
                    items: [
                        "Conversation-Aware Identity: Event resolution mapping directly to specific conversation threads.",
                        "Storage Engine v2: SQLite Schema v2 with automated migration runner and rollback safety.",
                        "UI Event Coalescing: High-frequency burst coalescer throttling 1,000 multi-agent events into single UI passes."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Changed & Improved",
                    icon: "slider.horizontal.3",
                    items: [
                        "Non-blocking process execution runner preventing pipe deadlocks.",
                        "Remediated architectural findings F-01 through F-13."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Fixed",
                    icon: "checkmark.circle.fill",
                    items: [
                        "Multi-turn session reactivation and stale discovery protection.",
                        "AppKit menu shortcut conflict resolved."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Security & Privacy",
                    icon: "lock.shield.fill",
                    items: [
                        "Enforced Unix socket directory permissions (0700).",
                        "Added session authorization token for daemon shutdown."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Known Limitations",
                    icon: "exclamationmark.triangle",
                    items: [
                        "Cross-Space window raising remains governed by macOS Window Server security policies."
                    ]
                )
            ]
        ),
        ReleaseNote(
            id: "release-0.2.0",
            version: "0.2.0",
            date: "October 17, 2026",
            summary: "Milestone v0.2.0 — Multi-Agent Provider Expansion across Windsurf, OpenCode, Cursor, and official Antigravity CLI.",
            sections: [
                ReleaseNoteSection(
                    title: "Added",
                    icon: "plus.circle.fill",
                    items: [
                        "Native background agent integrations for Windsurf, OpenCode, and Cursor.",
                        "Official Google Antigravity CLI (agy) integration with automated lifecycle hooks.",
                        "Cloud agent terminal transition propagation and wake cancellation exemptions."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Changed & Improved",
                    icon: "slider.horizontal.3",
                    items: [
                        "Integration testing tiers and provider status matrix documentation."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Fixed",
                    icon: "checkmark.circle.fill",
                    items: [
                        "Cursor provider CI workspace detection.",
                        "Lifecycle, installation, and reliability defects in OpenCode and Windsurf."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Security & Privacy",
                    icon: "lock.shield.fill",
                    items: [
                        "Peer UID authentication on Unix domain socket connections."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Known Limitations",
                    icon: "exclamationmark.triangle",
                    items: [
                        "Accessibility permissions required for application-specific window targeting."
                    ]
                )
            ]
        ),
        ReleaseNote(
            id: "release-0.1.0",
            version: "0.1.0",
            date: "October 16, 2026",
            summary: "Milestone v0.1.0 — Deterministic 12-Step Focus Engine, Standalone Daemon & Security Hardening.",
            sections: [
                ReleaseNoteSection(
                    title: "Added",
                    icon: "plus.circle.fill",
                    items: [
                        "Deterministic 12-Step Focus Engine: Process liveness protection and cooldown deferral.",
                        "Standalone Executable Flags: Headless daemon (--daemon, --headless) and CLI commands.",
                        "ProviderSupportLevel tiers and dynamic home directory resolution.",
                        "SQLite retention pruning and in-memory database support for testing."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Changed & Improved",
                    icon: "slider.horizontal.3",
                    items: [
                        "Apple Human Interface Guidelines compliance and native macOS styling.",
                        "SQLiteDatabase Sendable concurrency safety."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Fixed",
                    icon: "checkmark.circle.fill",
                    items: [
                        "Resolved standalone executable crash on UNUserNotificationCenter outside app bundle.",
                        "Resolved window thrashing during simultaneous multi-agent completions."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Security & Privacy",
                    icon: "lock.shield.fill",
                    items: [
                        "Peer UID verification (getpeereid), duplicate daemon prevention (EADDRINUSE), and bounded 2MB payloads."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Known Limitations",
                    icon: "exclamationmark.triangle",
                    items: [
                        "Cross-Space activation requires user configuration."
                    ]
                )
            ]
        ),
        ReleaseNote(
            id: "release-0.0.1",
            version: "0.0.1",
            date: "September 15, 2026",
            summary: "Milestone v0.0.1 — First Working Prototype with multi-chunk socket IPC, SQLite transient memory safety, and proactive discovery.",
            sections: [
                ReleaseNoteSection(
                    title: "Added",
                    icon: "plus.circle.fill",
                    items: [
                        "First Working Prototype: End-to-end agent event detection, IPC socket routing, and focus restoration.",
                        "Proactive Agent Discovery: Scanning running process tables for Antigravity IDE instances.",
                        "Multi-Chunk IPC Streaming: Safe POSIX buffer boundary streaming and framing.",
                        "SQLite Transient Safety: Parameter binding with SQLITE_TRANSIENT.",
                        "Verification Suite: 61 deterministic unit and integration test assertions."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Changed & Improved",
                    icon: "slider.horizontal.3",
                    items: [
                        "Refactored Unix socket receiver to support arbitrary JSON payload sizes."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Fixed",
                    icon: "checkmark.circle.fill",
                    items: [
                        "Fixed socket truncation on payloads > 4KB.",
                        "Fixed memory faults during rapid SQLite string writes."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Security & Privacy",
                    icon: "lock.shield.fill",
                    items: [
                        "Local Unix domain socket communication only; zero network transmission."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Known Limitations",
                    icon: "exclamationmark.triangle",
                    items: [
                        "Initial prototype requiring packaged bundle for notification dispatch."
                    ]
                )
            ]
        )
    ]

    /// Latest available release note entry
    public static var current: ReleaseNote? {
        bundledNotes.first
    }
}
