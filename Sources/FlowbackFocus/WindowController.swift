import Foundation
import AppKit
import ApplicationServices
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "WindowController")

public struct WindowInfo: Identifiable, Sendable {
    public var id: UInt32 { windowID }
    public let windowID: UInt32
    public let processIdentifier: Int32
    public let ownerName: String
    public let title: String
    public let bounds: CGRect
    public let isOnScreen: Bool
    
    public init(
        windowID: UInt32,
        processIdentifier: Int32,
        ownerName: String,
        title: String,
        bounds: CGRect,
        isOnScreen: Bool
    ) {
        self.windowID = windowID
        self.processIdentifier = processIdentifier
        self.ownerName = ownerName
        self.title = title
        self.bounds = bounds
        self.isOnScreen = isOnScreen
    }
}

public protocol WindowControlling: Sendable {
    func listWindows(forProcessIdentifier pid: Int32) -> [WindowInfo]
    func findWindow(matching titleSubstring: String, pid: Int32) -> WindowInfo?
    func raiseWindow(windowID: UInt32, pid: Int32) -> Bool
    func isFrontmostWindowFullscreen() -> Bool
}

/// Controls macOS window enumeration, matching, and raising via CoreGraphics and Accessibility
public final class WindowController: WindowControlling, @unchecked Sendable {
    public static let shared = WindowController()
    
    public init() {}
    
    public func listWindows(forProcessIdentifier pid: Int32) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        var windows: [WindowInfo] = []
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid else {
                continue
            }
            let windowID = (info[kCGWindowNumber as String] as? UInt32) ?? 0
            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? ""
            let title = (info[kCGWindowName as String] as? String) ?? ""
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? true
            
            var bounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                bounds = rect
            }
            
            // Filter out 0-size helper windows or menu items
            if bounds.width > 50 && bounds.height > 50 {
                windows.append(WindowInfo(
                    windowID: windowID,
                    processIdentifier: pid,
                    ownerName: ownerName,
                    title: title,
                    bounds: bounds,
                    isOnScreen: isOnScreen
                ))
            }
        }
        return windows
    }
    
    public func findWindow(matching titleSubstring: String, pid: Int32) -> WindowInfo? {
        let windows = listWindows(forProcessIdentifier: pid)
        return windows.first { $0.title.localizedCaseInsensitiveContains(titleSubstring) }
    }
    
    public func raiseWindow(windowID: UInt32, pid: Int32) -> Bool {
        guard PermissionManager.shared.isAccessibilityGranted() else {
            logger.debug("Accessibility not granted; window-level raising cannot use AXUIElement")
            return false
        }
        
        let appRef = AXUIElementCreateApplication(pid_t(pid))
        var windowsRef: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard copyResult == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return false
        }
        
        for axWindow in axWindows {
            // Find window by matching title or raise the first main window
            var titleRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            
            // Raise the window
            let actionResult = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            if actionResult == .success {
                logger.info("Raised window for PID \(pid) via AXUIElement")
                return true
            }
        }
        return false
    }
    
    public func isFrontmostWindowFullscreen() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = frontApp.processIdentifier
        let windows = listWindows(forProcessIdentifier: pid)
        guard let mainScreen = NSScreen.main else { return false }
        let screenFrame = mainScreen.frame
        
        for win in windows {
            if win.bounds.width >= screenFrame.width && win.bounds.height >= screenFrame.height {
                return true
            }
        }
        return false
    }
}
