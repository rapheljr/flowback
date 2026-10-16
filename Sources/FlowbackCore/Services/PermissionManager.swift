import Foundation
import ApplicationServices
import UserNotifications
import ServiceManagement

/// State of permissions required by Flowback
public struct PermissionStatus: Codable, Sendable {
    public var accessibilityGranted: Bool
    public var notificationsGranted: Bool
    public var launchAtLoginEnabled: Bool
    public var isAppBundle: Bool
    
    public init(
        accessibilityGranted: Bool = false,
        notificationsGranted: Bool = false,
        launchAtLoginEnabled: Bool = false,
        isAppBundle: Bool = (Bundle.main.bundleIdentifier != nil)
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.notificationsGranted = notificationsGranted
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.isAppBundle = isAppBundle
    }
}

/// Service managing macOS system permissions for Accessibility, Notifications, and Login Items
public final class PermissionManager: Sendable {
    public static let shared = PermissionManager()
    
    public init() {}
    
    /// Evaluates if the current running process is inside an application bundle with a valid bundle identifier
    public var isAppBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }
    
    /// Evaluates if Accessibility permissions are currently granted
    public func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
    
    /// Requests Accessibility permissions, opening System Settings if needed
    @discardableResult
    public func requestAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Checks Notification authorization state
    public func checkNotificationStatus() async -> Bool {
        guard isAppBundle else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    
    /// Requests Notification authorization
    public func requestNotifications() async -> Bool {
        guard isAppBundle else { return false }
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
    
    /// Checks if Launch at Login is enabled via ServiceManagement
    public func isLaunchAtLoginEnabled() -> Bool {
        guard isAppBundle else { return false }
        return SMAppService.mainApp.status == .enabled
    }
    
    /// Configures Launch at Login state
    public func setLaunchAtLogin(enabled: Bool) throws {
        guard isAppBundle else { return }
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
    
    /// Aggregates all current permission states
    public func currentStatus() async -> PermissionStatus {
        let ax = isAccessibilityGranted()
        let notif = await checkNotificationStatus()
        let login = isLaunchAtLoginEnabled()
        let inBundle = isAppBundle
        return PermissionStatus(
            accessibilityGranted: ax,
            notificationsGranted: notif,
            launchAtLoginEnabled: login,
            isAppBundle: inBundle
        )
    }
}
