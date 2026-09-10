import Foundation
import ApplicationServices
import UserNotifications
import ServiceManagement

/// State of permissions required by Flowback
public struct PermissionStatus: Codable, Sendable {
    public var accessibilityGranted: Bool
    public var notificationsGranted: Bool
    public var launchAtLoginEnabled: Bool
    
    public init(
        accessibilityGranted: Bool = false,
        notificationsGranted: Bool = false,
        launchAtLoginEnabled: Bool = false
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.notificationsGranted = notificationsGranted
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}

/// Service managing macOS system permissions for Accessibility, Notifications, and Login Items
public final class PermissionManager: Sendable {
    public static let shared = PermissionManager()
    
    public init() {}
    
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
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    
    /// Requests Notification authorization
    public func requestNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
    
    /// Checks if Launch at Login is enabled via ServiceManagement
    public func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    /// Configures Launch at Login state
    public func setLaunchAtLogin(enabled: Bool) throws {
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
        return PermissionStatus(
            accessibilityGranted: ax,
            notificationsGranted: notif,
            launchAtLoginEnabled: login
        )
    }
}
