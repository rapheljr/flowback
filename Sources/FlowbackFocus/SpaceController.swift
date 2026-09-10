import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "SpaceController")

public protocol SpaceControlling: Sendable {
    func shouldSwitchSpace(for policy: SpacePolicy, windowOnCurrentSpace: Bool) -> Bool
    func isWindowOnActiveSpace(windowID: UInt32) -> Bool
}

/// Enforces macOS Space policy to avoid jarring cross-desktop switching
public final class SpaceController: SpaceControlling, Sendable {
    public static let shared = SpaceController()
    
    public init() {}
    
    public func shouldSwitchSpace(for policy: SpacePolicy, windowOnCurrentSpace: Bool) -> Bool {
        if windowOnCurrentSpace {
            return true
        }
        switch policy {
        case .neverSwitchSpaces:
            return false
        case .activateApplicationOnly:
            return false
        case .activateApplicationAndWindow:
            return true
        case .allowSpaceSwitching:
            return true
        }
    }
    
    public func isWindowOnActiveSpace(windowID: UInt32) -> Bool {
        // Query on-screen windows on the current space
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        return list.contains { ($0[kCGWindowNumber as String] as? UInt32) == windowID }
    }
}
