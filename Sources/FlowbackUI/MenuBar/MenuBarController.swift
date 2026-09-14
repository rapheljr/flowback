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
    
    public init(delegate: MenuBarActionDelegate? = nil) {
        self.delegate = delegate
        super.init()
    }
    
    public func setDelegate(_ delegate: MenuBarActionDelegate) {
        self.delegate = delegate
    }
    
    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemAppearance()
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
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
            button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Flowback (Locked)")
            button.title = ""
        } else if !attentionQueue.isEmpty {
            button.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Flowback (Attention)")
            button.title = " \(attentionQueue.count)"
        } else if !activeSessions.isEmpty {
            button.image = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: "Flowback (Active)")
            button.title = " \(activeSessions.count)"
        } else {
            button.image = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: "Flowback")
            button.title = ""
        }
    }
    
    // MARK: - NSMenuDelegate
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        // Header
        let titleItem = NSMenuItem(title: "Flowback — AI Focus Manager", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        // Active summary
        let activeCount = activeSessions.count
        let activeText = activeCount == 1 ? "● 1 agent active" : "● \(activeCount) agents active"
        let activeItem = NSMenuItem(title: activeText, action: nil, keyEquivalent: "")
        activeItem.isEnabled = false
        menu.addItem(activeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Recent Sessions with ⌘1..⌘9 shortcuts
        let recentMenu = NSMenu(title: "Recent Sessions")
        if recentSessions.isEmpty {
            let empty = NSMenuItem(title: "No recent agent sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for (idx, session) in recentSessions.prefix(9).enumerated() {
                let shortcut = "\(idx + 1)"
                let title = "\(session.providerID.rawValue) — \(session.projectName)"
                let item = NSMenuItem(title: title, action: #selector(didClickRecentSession(_:)), keyEquivalent: shortcut)
                item.keyEquivalentModifierMask = [.command]
                item.target = self
                item.representedObject = session.id.rawValue
                recentMenu.addItem(item)
            }
        }
        let recentParent = NSMenuItem(title: "Recent Agent Sessions", action: nil, keyEquivalent: "")
        recentParent.submenu = recentMenu
        menu.addItem(recentParent)
        
        // Attention Queue
        if !attentionQueue.isEmpty {
            let attentionMenu = NSMenu(title: "Attention Queue")
            for req in attentionQueue {
                let item = NSMenuItem(title: "\(req.title): \(req.message)", action: #selector(didClickAttentionItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = req.sessionID.rawValue
                attentionMenu.addItem(item)
            }
            let attentionParent = NSMenuItem(title: "Attention Queue (\(attentionQueue.count))", action: nil, keyEquivalent: "")
            attentionParent.submenu = attentionMenu
            menu.addItem(attentionParent)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Focus Lock submenu
        let lockMenu = NSMenu(title: "Focus Lock")
        let isLocked = focusLock.isCurrentlyLocked
        
        let lock15 = NSMenuItem(title: "Lock for 15 minutes", action: #selector(setLock15), keyEquivalent: "")
        lock15.target = self
        lockMenu.addItem(lock15)
        
        let lock30 = NSMenuItem(title: "Lock for 30 minutes", action: #selector(setLock30), keyEquivalent: "")
        lock30.target = self
        lockMenu.addItem(lock30)
        
        let lock60 = NSMenuItem(title: "Lock for 1 hour", action: #selector(setLock60), keyEquivalent: "")
        lock60.target = self
        lockMenu.addItem(lock60)
        
        if isLocked {
            let disableLock = NSMenuItem(title: "Disable Focus Lock", action: #selector(disableLock), keyEquivalent: "")
            disableLock.target = self
            lockMenu.addItem(disableLock)
        }
        
        let lockTitle = isLocked ? "Focus Lock (Active)" : "Focus Lock"
        let lockParent = NSMenuItem(title: lockTitle, action: nil, keyEquivalent: "")
        lockParent.submenu = lockMenu
        menu.addItem(lockParent)
        
        menu.addItem(NSMenuItem.separator())
        
        // Windows and settings
        let refreshItem = NSMenuItem(title: "Refresh Agents & Status", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let dashItem = NSMenuItem(title: "Open Dashboard...", action: #selector(openDashboard), keyEquivalent: "d")
        dashItem.target = self
        menu.addItem(dashItem)
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let diagItem = NSMenuItem(title: "Diagnostics / Doctor...", action: #selector(openDiagnostics), keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Flowback", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
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
