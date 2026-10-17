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

public struct AccessibleWindowAttributes: Sendable {
    public let title: String
    public let position: CGPoint
    public let size: CGSize

    public init(title: String, position: CGPoint, size: CGSize) {
        self.title = title
        self.position = position
        self.size = size
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

    public static func selectMatchingWindowIndex(
        target: WindowInfo,
        candidates: [AccessibleWindowAttributes]
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }

        var scored: [(index: Int, score: Int)] = []

        for (i, c) in candidates.enumerated() {
            let dx = abs(c.position.x - target.bounds.origin.x)
            let dy = abs(c.position.y - target.bounds.origin.y)
            let dw = abs(c.size.width - target.bounds.width)
            let dh = abs(c.size.height - target.bounds.height)
            let boundsMatch = (dx <= 5.0 && dy <= 5.0 && dw <= 5.0 && dh <= 5.0)

            let cleanTargetTitle = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanCandTitle = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleNotEmpty = !cleanTargetTitle.isEmpty && !cleanCandTitle.isEmpty
            let exactTitleMatch = titleNotEmpty && (cleanTargetTitle == cleanCandTitle)
            let partialTitleMatch = titleNotEmpty && (cleanTargetTitle.localizedCaseInsensitiveContains(cleanCandTitle) || cleanCandTitle.localizedCaseInsensitiveContains(cleanTargetTitle))

            var score = 0
            if boundsMatch && exactTitleMatch {
                score = 10
            } else if boundsMatch {
                score = 6
            } else if exactTitleMatch {
                score = 4
            } else if partialTitleMatch {
                score = 2
            }

            if score > 0 {
                scored.append((i, score))
            }
        }

        guard let highest = scored.max(by: { $0.score < $1.score }) else {
            return nil
        }

        // Ensure no ambiguous tie with equal highest score
        let topMatches = scored.filter { $0.score == highest.score }
        guard topMatches.count == 1 else {
            return nil
        }

        return highest.index
    }

    public func raiseWindow(windowID: UInt32, pid: Int32) -> Bool {
        guard PermissionManager.shared.isAccessibilityGranted() else {
            logger.debug("Accessibility not granted; window-level raising cannot use AXUIElement")
            return false
        }

        guard windowID > 0 else {
            logger.warning("raiseWindow invoked with windowID 0; target identity cannot be established")
            return false
        }

        let allWindows = listWindows(forProcessIdentifier: pid)
        guard let targetWindow = allWindows.first(where: { $0.windowID == windowID }) else {
            logger.warning("Target window ID \(windowID) does not exist for PID \(pid)")
            return false
        }

        let appRef = AXUIElementCreateApplication(pid_t(pid))
        var windowsRef: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)

        guard copyResult == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            logger.warning("Failed to retrieve accessibility windows for PID \(pid)")
            return false
        }

        var candidates: [AccessibleWindowAttributes] = []
        for axWin in axWindows {
            var titleRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
            let axTitle = (titleRef as? String) ?? ""

            var posRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
            var axPoint = CGPoint.zero
            if let posVal = posRef {
                AXValueGetValue(posVal as! AXValue, .cgPoint, &axPoint)
            }

            var sizeRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef)
            var axSize = CGSize.zero
            if let sizeVal = sizeRef {
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &axSize)
            }

            candidates.append(AccessibleWindowAttributes(title: axTitle, position: axPoint, size: axSize))
        }

        guard let matchIdx = Self.selectMatchingWindowIndex(target: targetWindow, candidates: candidates) else {
            logger.warning("Could not establish unambiguous accessibility window match for window ID \(windowID)")
            return false
        }

        let targetAXWindow = axWindows[matchIdx]
        let actionResult = AXUIElementPerformAction(targetAXWindow, kAXRaiseAction as CFString)
        if actionResult == .success {
            logger.info("Raised window ID \(windowID) for PID \(pid) via AXUIElement")
            return true
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
