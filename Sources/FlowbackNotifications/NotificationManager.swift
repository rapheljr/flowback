import Foundation
import UserNotifications
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "NotificationManager")

@MainActor
public protocol NotificationActionDelegate: AnyObject, Sendable {
    func didRequestFocus(sessionID: AgentSessionID) async
    func didRequestReview() async
}

public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationManager()
    
    public static let categoryAttention = "FLOWBACK_ATTENTION"
    public static let actionFocus = "FLOWBACK_ACTION_FOCUS"
    public static let actionReview = "FLOWBACK_ACTION_REVIEW"
    public static let actionDismiss = "FLOWBACK_ACTION_DISMISS"
    
    private weak var actionDelegate: NotificationActionDelegate?
    
    public override init() {
        super.init()
        setupCategories()
    }
    
    public func setActionDelegate(_ delegate: NotificationActionDelegate) {
        self.actionDelegate = delegate
    }
    
    private var isNotificationSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }
    
    public func registerDelegate() {
        guard isNotificationSupported else { return }
        UNUserNotificationCenter.current().delegate = self
    }
    
    private func setupCategories() {
        guard isNotificationSupported else {
            logger.debug("Notifications skipped: process is running outside an app bundle")
            return
        }
        let focusAction = UNNotificationAction(
            identifier: Self.actionFocus,
            title: "Focus",
            options: [.foreground]
        )
        let reviewAction = UNNotificationAction(
            identifier: Self.actionReview,
            title: "Review",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: Self.actionDismiss,
            title: "Dismiss",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: Self.categoryAttention,
            actions: [focusAction, reviewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    /// Sends an actionable agent attention notification
    public func sendAttentionNotification(
        session: AgentSession,
        title: String,
        body: String
    ) async {
        guard isNotificationSupported else {
            logger.info("Notification skipped (outside app bundle): \(title) - \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = session.projectName
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryAttention
        content.userInfo = ["session_id": session.id.rawValue]
        
        let request = UNNotificationRequest(
            identifier: "flowback-\(session.id.rawValue)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Delivered attention notification for \(session.id.rawValue)")
        } catch {
            logger.error("Failed to post notification: \(error.localizedDescription)")
        }
    }
    
    /// Sends an aggregated notification when multiple agents need attention
    public func sendAggregatedNotification(title: String, body: String) async {
        guard isNotificationSupported else {
            logger.info("Aggregated notification skipped (outside app bundle): \(title) - \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryAttention
        
        let request = UNNotificationRequest(
            identifier: "flowback-aggregated-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner and play sound even when app is active
        [.banner, .sound, .list]
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let sessionIDStr = userInfo["session_id"] as? String
        
        logger.info("Notification action clicked: \(actionID)")
        
        switch actionID {
        case Self.actionFocus:
            if let id = sessionIDStr {
                await actionDelegate?.didRequestFocus(sessionID: AgentSessionID(id))
            }
        case Self.actionReview:
            await actionDelegate?.didRequestReview()
        default:
            break
        }
    }
}
