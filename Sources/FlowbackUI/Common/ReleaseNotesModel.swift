import Foundation

/// Individual section within a release note entry (e.g. Added, Changed, Fixed, Security)
public struct ReleaseNoteSection: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let icon: String
    public let items: [String]

    public init(id: String = UUID().uuidString, title: String, icon: String, items: [String]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.items = items
    }
}

/// A structured release entry for What's New presentation
public struct ReleaseNote: Identifiable, Sendable, Equatable {
    public let id: String
    public let version: String
    public let date: String
    public let summary: String
    public let sections: [ReleaseNoteSection]

    public init(
        id: String = UUID().uuidString,
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
            id: "release-1.0.0",
            version: "1.0.0",
            date: "October 16, 2026",
            summary: "Initial production release of Flowback — the universal macOS AI agent context & focus manager.",
            sections: [
                ReleaseNoteSection(
                    title: "Added",
                    icon: "plus.circle.fill",
                    items: [
                        "Universal Agent Providers: Official integration for Antigravity, Claude Code, " +
                        "OpenAI Codex, Antigravity CLI (agy), and Generic JSON Hook Protocol.",
                        "Editor & Terminal Adapters: First-class window focus support for VS Code, VS Code Insiders, " +
                        "Cursor, Windsurf, Positron, Apple Terminal, iTerm2, Kitty, Alacritty, Ghostty, and Warp.",
                        "Intelligent Focus Engine: Keystroke sensing via User Intent Engine to prevent focus theft while typing (< 5-second idle threshold).",
                        "Priority Attention Arbiter: Order-of-precedence evaluation (Permission Required > Failure > Completed > Waiting > Informational).",
                        "Focus Lock Mode: Suppresses automatic focus switches for 15m, 30m, 45m, 1h, or indefinitely while keeping notifications active.",
                        "Local SQLite WAL Persistence: Fast crash-resilient storage with automatic migrations " +
                        "and background session reconciliation at ~/.flowback/flowback.sqlite.",
                        "AppKit Menu Bar UI & SwiftUI Dashboard: Real-time agent status item, ⌘1–⌘9 shortcuts, live diagnostics, and timeline history."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Changed & Improved",
                    icon: "slider.horizontal.3",
                    items: [
                        "Optimized Unix socket IPC streaming to handle multi-chunk JSON hook payloads across POSIX boundaries.",
                        "Safeguarded SQLite string parameters with SQLITE_TRANSIENT to eliminate transient memory faults under high concurrent load.",
                        "Enhanced Antigravity lifecycle hook installer with atomic updates and automatic backups in ~/.gemini/config/hooks.json."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Fixed",
                    icon: "checkmark.circle.fill",
                    items: [
                        "Resolved window thrashing when multiple autonomous agents finish work at the same time.",
                        "Fixed socket connection stall during large JSON payload transmission.",
                        "Prevented unwanted focus transitions into active fullscreen presentation applications (Zoom, Keynote)."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Security & Privacy",
                    icon: "lock.shield.fill",
                    items: [
                        "Enforced 100% local operation: Zero outbound telemetry, zero remote tracking, zero code exfiltration.",
                        "Restricted Unix socket permissions to 0600 (strictly accessible by local user process).",
                        "Deterministic secret and credential sanitizer scrubbing Bearer tokens, private keys, and passwords from logs."
                    ]
                ),
                ReleaseNoteSection(
                    title: "Known Limitations",
                    icon: "exclamationmark.triangle",
                    items: [
                        "macOS Window Server restricts cross-Space window raising; Flowback activates target apps on current Space " +
                        "unless Space switching is explicitly configured.",
                        "Running without Accessibility permissions gracefully degrades to application-level switching rather than precise window targeting."
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
