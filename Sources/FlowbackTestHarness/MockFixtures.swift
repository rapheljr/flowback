import Foundation
import AppKit
import FlowbackCore
import FlowbackFocus
import FlowbackProviders

public final class MockApplicationController: ApplicationControlling, @unchecked Sendable {
    public var frontmostAppMock: NSRunningApplication? = NSRunningApplication.current
    public var runningAppsMock: [NSRunningApplication] = [NSRunningApplication.current]
    public var activatedApps: [NSRunningApplication] = []
    
    public init() {}
    
    public func frontmostApplication() -> NSRunningApplication? {
        frontmostAppMock
    }
    
    public func runningApplication(forProcessIdentifier pid: Int32) -> NSRunningApplication? {
        runningAppsMock.first { $0.processIdentifier == pid } ?? runningAppsMock.first
    }
    
    public func runningApplications(withBundleIdentifier bundleID: String) -> [NSRunningApplication] {
        let matched = runningAppsMock.filter { $0.bundleIdentifier == bundleID }
        return matched.isEmpty ? runningAppsMock : matched
    }
    
    public func activate(application: NSRunningApplication) -> Bool {
        activatedApps.append(application)
        return true
    }
}

public final class MockWindowController: WindowControlling, @unchecked Sendable {
    public var windowsMock: [WindowInfo] = []
    public var raisedWindowIDs: [UInt32] = []
    public var isFullscreenMock: Bool = false
    
    public init() {}
    
    public func listWindows(forProcessIdentifier pid: Int32) -> [WindowInfo] {
        windowsMock.filter { $0.processIdentifier == pid }
    }
    
    public func findWindow(matching titleSubstring: String, pid: Int32) -> WindowInfo? {
        windowsMock.first { $0.processIdentifier == pid && $0.title.localizedCaseInsensitiveContains(titleSubstring) }
    }
    
    public func raiseWindow(windowID: UInt32, pid: Int32) -> Bool {
        raisedWindowIDs.append(windowID)
        return true
    }
    
    public func isFrontmostWindowFullscreen() -> Bool {
        isFullscreenMock
    }
}

public final class MockIdleTracker: IdleTracking, @unchecked Sendable {
    public var idleSecondsMock: Double = 0.0
    
    public init(idleSeconds: Double = 0.0) {
        self.idleSecondsMock = idleSeconds
    }
    
    public func systemIdleSeconds() -> Double {
        idleSecondsMock
    }
    
    public func isUserActive(within seconds: Double) -> Bool {
        idleSecondsMock <= seconds
    }
}

public final class MockSpaceController: SpaceControlling, @unchecked Sendable {
    public var activeWindowIDs: Set<UInt32> = []
    public var allowSpaceSwitchingMock: Bool = false
    public var defaultOnActiveSpace: Bool = true
    
    public init(defaultOnActiveSpace: Bool = true) {
        self.defaultOnActiveSpace = defaultOnActiveSpace
    }
    
    public func shouldSwitchSpace(for policy: SpacePolicy, windowOnCurrentSpace: Bool) -> Bool {
        if windowOnCurrentSpace { return true }
        switch policy {
        case .neverSwitchSpaces, .activateApplicationOnly: return false
        case .activateApplicationAndWindow, .allowSpaceSwitching: return true
        }
    }
    
    public func isWindowOnActiveSpace(windowID: UInt32) -> Bool {
        if !activeWindowIDs.isEmpty {
            return activeWindowIDs.contains(windowID)
        }
        return defaultOnActiveSpace
    }
}

public final class MockAgentProvider: AgentProvider, Sendable {
    public let providerID: AgentProviderID
    public let displayName: String
    public let isSupported = true
    
    public init(providerID: AgentProviderID = .antigravity, displayName: String = "Mock Provider") {
        self.providerID = providerID
        self.displayName = displayName
    }
    
    public func checkHealth() async -> ProviderHealth {
        ProviderHealth(providerID: providerID, displayName: displayName, isInstalled: true, hookInstalled: true, hookExecutable: true)
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        return try? decoder.decode(AgentEvent.self, from: data)
    }
    
    public func installIntegration() async throws {}
    public func uninstallIntegration() async throws {}
}
