import Foundation
import ApplicationServices
import UserNotifications
import ServiceManagement
#if canImport(AppKit)
import AppKit
#endif

/// Granular status of macOS ServiceManagement launch-at-login registration
public enum LaunchAtLoginStatus: String, Codable, Sendable {
    case enabled = "enabled"
    case disabled = "disabled"
    case requiresApproval = "requires_approval"
    case notFound = "not_found"
    case unsupported = "unsupported"
    
    public var displayName: String {
        switch self {
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .requiresApproval: return "Approval Required (System Settings)"
        case .notFound: return "Application Not Found"
        case .unsupported: return "Not Available in Standalone Mode"
        }
    }
}

/// State of permissions required by Flowback
public struct PermissionStatus: Codable, Sendable {
    public var accessibilityGranted: Bool
    public var notificationsGranted: Bool
    public var launchAtLoginEnabled: Bool
    public var isAppBundle: Bool
    public var launchAtLoginStatus: LaunchAtLoginStatus
    
    public init(
        accessibilityGranted: Bool = false,
        notificationsGranted: Bool = false,
        launchAtLoginEnabled: Bool = false,
        isAppBundle: Bool = (Bundle.main.bundleIdentifier != nil),
        launchAtLoginStatus: LaunchAtLoginStatus? = nil
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.notificationsGranted = notificationsGranted
        self.isAppBundle = isAppBundle
        let resolved = launchAtLoginStatus ?? (launchAtLoginEnabled ? .enabled : (isAppBundle ? .disabled : .unsupported))
        self.launchAtLoginStatus = resolved
        self.launchAtLoginEnabled = (resolved == .enabled)
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
    
    public static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    public static let notificationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
    public static let modernNotificationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
    
    /// Requests Accessibility permissions, opening System Settings prompt if needed
    @discardableResult
    public func requestAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Deep-links directly to macOS System Settings -> Privacy & Security -> Accessibility
    @discardableResult
    public func openAccessibilitySettings() -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.open(Self.accessibilitySettingsURL)
        #else
        return false
        #endif
    }
    
    /// Deep-links directly to macOS System Settings -> Notifications
    @discardableResult
    public func openNotificationSettings() -> Bool {
        #if canImport(AppKit)
        if #available(macOS 13.0, *) {
            if NSWorkspace.shared.open(Self.modernNotificationSettingsURL) {
                return true
            }
        }
        return NSWorkspace.shared.open(Self.notificationSettingsURL)
        #else
        return false
        #endif
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
    
    /// Maps SMAppService status into testable LaunchAtLoginStatus
    public static func mapSMStatus(_ status: SMAppService.Status, isAppBundle: Bool) -> LaunchAtLoginStatus {
        guard isAppBundle else { return .unsupported }
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return .notFound
        @unknown default:
            return .disabled
        }
    }
    
    /// Returns granular Launch at Login status via ServiceManagement
    public func launchAtLoginStatus() -> LaunchAtLoginStatus {
        guard isAppBundle else { return .unsupported }
        return Self.mapSMStatus(SMAppService.mainApp.status, isAppBundle: isAppBundle)
    }
    
    /// Checks if Launch at Login is enabled via ServiceManagement
    public func isLaunchAtLoginEnabled() -> Bool {
        launchAtLoginStatus() == .enabled
    }
    
    /// Configures Launch at Login state with informative error handling
    public func setLaunchAtLogin(enabled: Bool) throws {
        guard isAppBundle else {
            throw NSError(
                domain: "com.flowback.app",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Launch at Login is only available when running inside a packaged macOS application bundle."]
            )
        }
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
        let status = launchAtLoginStatus()
        let inBundle = isAppBundle
        return PermissionStatus(
            accessibilityGranted: ax,
            notificationsGranted: notif,
            launchAtLoginEnabled: status == .enabled,
            isAppBundle: inBundle,
            launchAtLoginStatus: status
        )
    }
}
