import Foundation
import AppKit
import FlowbackCore

@MainActor
public protocol MenuBarActionDelegate: AnyObject, Sendable {
    func didSelectFocus(sessionID: AgentSessionID)
    func didToggleFocusLock(minutes: Int?)
    func didRequestOpenDashboard()
    func didRequestOpenSettings()
    func didRequestOpenDiagnostics()
    func didRequestRefresh()
    func didRequestQuit()
}

/// Controls the macOS menu bar status item and its interactive dropdown menu
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem?
    private weak var delegate: MenuBarActionDelegate?

    private var activeSessions: [AgentSession] = []
    private var recentSessions: [AgentSession] = []
    private var attentionQueue: [AttentionRequest] = []
    private var focusLock: FocusLockState = FocusLockState()

    // Frozen snapshot state to guarantee slot stability and shortcut predictability while menu is open
    private(set) public var isMenuOpen: Bool = false
    private(set) public var frozenActiveSessions: [AgentSession]?
    private(set) public var frozenRecentSessions: [AgentSession]?
    private(set) public var frozenAttentionQueue: [AttentionRequest]?

    public static let defaultAutosaveName = "FlowbackStatusItem"
    public private(set) var autosaveName: String?

    public init(delegate: MenuBarActionDelegate? = nil) {
        self.delegate = delegate
        super.init()
    }

    public func setDelegate(_ delegate: MenuBarActionDelegate) {
        self.delegate = delegate
    }

    public func setup() {
        guard statusItem == nil else { return }
        autosaveName = Self.defaultAutosaveName
        guard PermissionManager.shared.isAppBundle && NSApp != nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = Self.defaultAutosaveName
        updateStatusItemAppearance()

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    public func teardown() {
        if let item = statusItem {
            item.menu = nil
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        autosaveName = nil
    }

    public func updateState(
        activeSessions: [AgentSession],
        recentSessions: [AgentSession],
        attentionQueue: [AttentionRequest],
        focusLock: FocusLockState
    ) {
        self.activeSessions = activeSessions
        self.recentSessions = recentSessions
        self.attentionQueue = attentionQueue
        self.focusLock = focusLock

        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItemAppearance()
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        if focusLock.isCurrentlyLocked {
            let img = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Flowback Focus Locked")
            img?.isTemplate = true
            button.image = img
            button.title = ""
            let remText = focusLock.remainingSeconds.map { " (\(max(1, Int($0 / 60)))m remaining)" } ?? ""
            button.toolTip = "Flowback — Focus Lock Active\(remText)"
        } else if !attentionQueue.isEmpty {
            let img = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Flowback Attention Required")
            img?.isTemplate = true
            button.image = img
            button.title = " \(attentionQueue.count)"
            button.toolTip = "Flowback — \(attentionQueue.count) agent(s) need attention"
        } else if !activeSessions.isEmpty {
            let img = flowbackStatusImage(accessibilityDescription: "Flowback Active")
            button.image = img
            button.title = " \(activeSessions.count)"
            button.toolTip = "Flowback — \(activeSessions.count) active agent(s)"
        } else {
            let img = flowbackStatusImage(accessibilityDescription: "Flowback Ready")
            button.image = img
            button.title = ""
            button.toolTip = "Flowback — AI Focus & Context Manager"
        }
    }

    private func flowbackStatusImage(accessibilityDescription: String) -> NSImage? {
        // 1. Prefer native macOS vector PDF template
        if let pdfUrl = Bundle.main.url(forResource: "menubar-icon", withExtension: "pdf"),
           let img = NSImage(contentsOf: pdfUrl) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            img.accessibilityDescription = accessibilityDescription
            return img
        }
        // 2. Vector SVG template
        if let svgUrl = Bundle.main.url(forResource: "menubar-icon", withExtension: "svg"),
           let img = NSImage(contentsOf: svgUrl) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            img.accessibilityDescription = accessibilityDescription
            return img
        }
        // 3. Bundled Retina PNG raster template
        if let pngUrl = Bundle.main.url(forResource: "menubar-icon", withExtension: "png"),
           let img = NSImage(contentsOf: pngUrl) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            img.accessibilityDescription = accessibilityDescription
            return img
        }
        // 4. Fallback to system SF Symbol
        let fallback = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: accessibilityDescription)
        fallback?.isTemplate = true
        return fallback
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        frozenActiveSessions = activeSessions
        frozenRecentSessions = recentSessions
        frozenAttentionQueue = attentionQueue
    }

    public func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        frozenActiveSessions = nil
        frozenRecentSessions = nil
        frozenAttentionQueue = nil
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Use frozen snapshot if menu is open to prevent shifting slots under user inspection
        let displayedActive = (isMenuOpen ? frozenActiveSessions : nil) ?? activeSessions
        let displayedRecent = (isMenuOpen ? frozenRecentSessions : nil) ?? recentSessions
        let displayedAttention = (isMenuOpen ? frozenAttentionQueue : nil) ?? attentionQueue

        // Native macOS 14 Section Header
        menu.addItem(NSMenuItem.sectionHeader(title: "Flowback — Focus Orchestrator"))

        // Active summary
        let activeCount = displayedActive.count
        let activeText = activeCount == 1 ? "1 active agent" : "\(activeCount) active agents"
        let activeItem = NSMenuItem(title: activeText, action: nil, keyEquivalent: "")
        let dotImg = NSImage(systemSymbolName: activeCount > 0 ? "circle.fill" : "circle", accessibilityDescription: nil)
        dotImg?.isTemplate = true
        activeItem.image = dotImg
        activeItem.isEnabled = false
        menu.addItem(activeItem)

        menu.addItem(NSMenuItem.separator())

        // Active Conversations Section if any are running
        if !displayedActive.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: "Active Conversations"))
            var activeProjectCounts: [String: Int] = [:]
            for s in displayedActive {
                activeProjectCounts[s.projectName, default: 0] += 1
            }

            for session in displayedActive {
                let isShared = (activeProjectCounts[session.projectName] ?? 0) > 1
                let item = makeSessionMenuItem(session: session, isSharedProject: isShared, keyEquivalent: "")
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }

        // Recent Sessions with ⌘1..⌘9 shortcuts
        let recentMenu = NSMenu(title: "Recent Sessions")
        if displayedRecent.isEmpty {
            let empty = NSMenuItem(title: "No recent agent sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            var recentProjectCounts: [String: Int] = [:]
            for s in displayedRecent {
                recentProjectCounts[s.projectName, default: 0] += 1
            }

            for (idx, session) in displayedRecent.prefix(9).enumerated() {
                let shortcut = "\(idx + 1)"
                let isShared = (recentProjectCounts[session.projectName] ?? 0) > 1
                let item = makeSessionMenuItem(session: session, isSharedProject: isShared, keyEquivalent: shortcut)
                item.keyEquivalentModifierMask = [.command]
                recentMenu.addItem(item)
            }
        }
        let recentParent = NSMenuItem(title: "Recent Agent Sessions", action: nil, keyEquivalent: "")
        recentParent.submenu = recentMenu
        menu.addItem(recentParent)

        // Attention Queue
        if !displayedAttention.isEmpty {
            let attentionMenu = NSMenu(title: "Attention Queue")
            for req in displayedAttention {
                let item = NSMenuItem(title: "\(req.title): \(req.message)", action: #selector(didClickAttentionItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = req.sessionID.rawValue
                attentionMenu.addItem(item)
            }
            let attentionParent = NSMenuItem(title: "Attention Queue (\(displayedAttention.count))", action: nil, keyEquivalent: "")
            attentionParent.submenu = attentionMenu
            menu.addItem(attentionParent)
        }

        menu.addItem(NSMenuItem.separator())

        // Focus Lock submenu with state checkmarks and remaining time
        let lockMenu = NSMenu(title: "Focus Lock")
        let isLocked = focusLock.isCurrentlyLocked

        let lock15 = NSMenuItem(title: "Lock for 15 minutes", action: #selector(setLock15), keyEquivalent: "")
        lock15.target = self
        if isLocked && focusLock.label == "15 min" { lock15.state = .on }
        lockMenu.addItem(lock15)

        let lock30 = NSMenuItem(title: "Lock for 30 minutes", action: #selector(setLock30), keyEquivalent: "")
        lock30.target = self
        if isLocked && focusLock.label == "30 min" { lock30.state = .on }
        lockMenu.addItem(lock30)

        let lock60 = NSMenuItem(title: "Lock for 1 hour", action: #selector(setLock60), keyEquivalent: "")
        lock60.target = self
        if isLocked && focusLock.label == "60 min" { lock60.state = .on }
        lockMenu.addItem(lock60)

        if isLocked {
            lockMenu.addItem(NSMenuItem.separator())
            let disableLock = NSMenuItem(title: "Disable Focus Lock", action: #selector(disableLock), keyEquivalent: "")
            disableLock.target = self
            lockMenu.addItem(disableLock)
        }

        let lockTitle: String
        if isLocked {
            if let rem = focusLock.remainingSeconds {
                lockTitle = "Focus Lock (Active — \(max(1, Int(rem / 60)))m left)"
            } else {
                lockTitle = "Focus Lock (Active)"
            }
        } else {
            lockTitle = "Focus Lock"
        }
        let lockParent = NSMenuItem(title: lockTitle, action: nil, keyEquivalent: "")
        lockParent.submenu = lockMenu
        menu.addItem(lockParent)

        menu.addItem(NSMenuItem.separator())

        // Windows and settings with HIG ellipsis
        let refreshItem = NSMenuItem(title: "Refresh Agents & Status", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let dashItem = NSMenuItem(title: "Open Dashboard…", action: #selector(openDashboard), keyEquivalent: "d")
        dashItem.target = self
        menu.addItem(dashItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let diagItem = NSMenuItem(title: "Diagnostics & Health…", action: #selector(openDiagnostics), keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Flowback", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Helpers

    private func makeSessionMenuItem(session: AgentSession, isSharedProject: Bool, keyEquivalent: String) -> NSMenuItem {
        let displayTitle = session.displayTitle
        let truncatedTitle = displayTitle.count > 42 ? String(displayTitle.prefix(40)) + "…" : displayTitle

        var titleComponents = [truncatedTitle]
        if isSharedProject {
            titleComponents.append("[\(session.projectName)]")
        }

        let itemTitle = titleComponents.joined(separator: " ")
        let item = NSMenuItem(title: itemTitle, action: #selector(didClickRecentSession(_:)), keyEquivalent: keyEquivalent)
        item.target = self
        item.representedObject = session.id.rawValue

        // Detailed tooltip for accessibility and inspection
        let details = [
            "Title: \(session.displayTitle)",
            "Provider: \(session.providerDisplayName)",
            "Project: \(session.projectName)",
            "Status: \(session.state.rawValue.capitalized)",
            "Focus: \(session.focusCapability.displayLabel)"
        ]
        item.toolTip = details.joined(separator: "\n")

        // Submenu with contextual actions
        let sub = NSMenu(title: session.displayTitle)

        let focusItem = NSMenuItem(title: "Focus Conversation (\(session.focusCapability.displayLabel))", action: #selector(didClickRecentSession(_:)), keyEquivalent: "")
        focusItem.target = self
        focusItem.representedObject = session.id.rawValue
        sub.addItem(focusItem)

        if let ws = session.workspace, FileManager.default.fileExists(atPath: ws) {
            let wsItem = NSMenuItem(title: "Reveal in Finder: \(session.projectName)", action: #selector(didClickOpenWorkspace(_:)), keyEquivalent: "")
            wsItem.target = self
            wsItem.representedObject = ws
            sub.addItem(wsItem)
        }

        if let url = session.conversationURL {
            let urlItem = NSMenuItem(title: "Open Provider URL…", action: #selector(didClickOpenURL(_:)), keyEquivalent: "")
            urlItem.target = self
            urlItem.representedObject = url.absoluteString
            sub.addItem(urlItem)
        }

        sub.addItem(NSMenuItem.separator())
        let copyItem = NSMenuItem(title: "Copy Session ID", action: #selector(didClickCopySessionID(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = session.id.rawValue
        sub.addItem(copyItem)

        // Only attach submenus when keyEquivalent is empty (such as in Active Conversations).
        // In AppKit, attaching a submenu to an NSMenuItem with a keyEquivalent (e.g. ⌘1..⌘9)
        // converts the item to a pull-right submenu container and suppresses direct keyboard activation.
        if keyEquivalent.isEmpty {
            item.submenu = sub
        }
        return item
    }

    // MARK: - Actions

    @objc private func didClickRecentSession(_ sender: NSMenuItem) {
        if let idStr = sender.representedObject as? String {
            delegate?.didSelectFocus(sessionID: AgentSessionID(idStr))
        }
    }

    @objc private func didClickAttentionItem(_ sender: NSMenuItem) {
        if let idStr = sender.representedObject as? String {
            delegate?.didSelectFocus(sessionID: AgentSessionID(idStr))
        }
    }

    @objc private func didClickOpenWorkspace(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        }
    }

    @objc private func didClickOpenURL(_ sender: NSMenuItem) {
        if let urlStr = sender.representedObject as? String, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func didClickCopySessionID(_ sender: NSMenuItem) {
        if let idStr = sender.representedObject as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(idStr, forType: .string)
        }
    }

    @objc private func setLock15() { delegate?.didToggleFocusLock(minutes: 15) }
    @objc private func setLock30() { delegate?.didToggleFocusLock(minutes: 30) }
    @objc private func setLock60() { delegate?.didToggleFocusLock(minutes: 60) }
    @objc private func disableLock() { delegate?.didToggleFocusLock(minutes: nil) }

    @objc private func refreshStatus() { delegate?.didRequestRefresh() }
    @objc private func openDashboard() { delegate?.didRequestOpenDashboard() }
    @objc private func openSettings() { delegate?.didRequestOpenSettings() }
    @objc private func openDiagnostics() { delegate?.didRequestOpenDiagnostics() }
    @objc private func quitApp() { delegate?.didRequestQuit() }
}
