import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "UserIntentEngine")

/// Canonical focus outcome matching the product orchestration contract
public enum FocusOutcome: String, Codable, Sendable {
    case restore
    case notify
    case `defer`
    case ignore
}

/// Structured diagnostic reason code explaining the focus decision
public enum FocusReasonCode: String, Codable, Sendable {
    case focusLockActive = "focus_lock_active"
    case policyNeverInterrupt = "policy_never_interrupt"
    case policyNotificationOnly = "policy_notification_only"
    case protectedApplicationActive = "protected_app_active"
    case fullscreenPresentation = "fullscreen_presentation"
    case userActivelyTyping = "user_actively_typing"
    case userAlreadyAtOrigin = "user_already_at_origin"
    case crossSpaceDisallowed = "cross_space_disallowed"
    case cooldownActive = "cooldown_active"
    case originProcessTerminated = "origin_process_terminated"
    case originContextMissing = "origin_context_missing"
    case restorationEvaluatedSafe = "restoration_evaluated_safe"
    case restorationSucceeded = "restoration_succeeded"
    case restorationFailedFallback = "restoration_failed_fallback"
    case eventStaleOrOutOfOrder = "event_stale_or_out_of_order"
    case eventNotActionable = "event_not_actionable"
    case manualUserTrigger = "manual_user_trigger"
}

/// Deterministic result of a focus evaluation
public enum FocusDecision: Equatable, Sendable {
    case restoreOrigin(context: OriginContext, reason: String)
    case fallbackApplication(bundleID: String, reason: String)
    case notifyOnly(reason: String)
    case deferAction(reasonCode: FocusReasonCode, explanation: String)
    case suppress(reason: String)
    
    public var outcome: FocusOutcome {
        switch self {
        case .restoreOrigin, .fallbackApplication:
            return .restore
        case .notifyOnly:
            return .notify
        case .deferAction:
            return .defer
        case .suppress:
            return .ignore
        }
    }
    
    public var shouldActivateApp: Bool {
        switch self {
        case .restoreOrigin, .fallbackApplication:
            return true
        case .notifyOnly, .deferAction, .suppress:
            return false
        }
    }
    
    public var explanation: String {
        switch self {
        case .restoreOrigin(_, let reason): return reason
        case .fallbackApplication(_, let reason): return reason
        case .notifyOnly(let reason): return reason
        case .deferAction(_, let explanation): return explanation
        case .suppress(let reason): return reason
        }
    }
}

/// Evaluates user activity, frontmost context, and policies to make deterministic focus decisions
public struct UserIntentEngine: Sendable {
    private let idleTracker: IdleTracking
    private let windowController: WindowControlling
    private let spaceController: SpaceControlling
    private let appController: ApplicationControlling
    
    public init(
        idleTracker: IdleTracking = IdleTracker.shared,
        windowController: WindowControlling = WindowController.shared,
        spaceController: SpaceControlling = SpaceController.shared,
        appController: ApplicationControlling = ApplicationController.shared
    ) {
        self.idleTracker = idleTracker
        self.windowController = windowController
        self.spaceController = spaceController
        self.appController = appController
    }
    
    /// Evaluates the session and system state, returning the deterministic focus decision
    public func evaluate(
        session: AgentSession,
        config: PolicyConfiguration,
        focusLock: FocusLockState,
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> FocusDecision {
        
        // 1. Focus Lock active
        if focusLock.isCurrentlyLocked {
            let reason = focusLock.remainingSeconds.map {
                "Focus Lock is active (expires in \(Int($0))s). Suppressing focus switch."
            } ?? "Focus Lock is active indefinitely. Suppressing focus switch."
            logger.info("\(reason)")
            return .notifyOnly(reason: reason)
        }
        
        // 2. Policy Resolution
        let effectivePolicy = config.resolvePolicy(
            provider: session.providerID,
            appBundleID: session.originContext?.bundleIdentifier,
            workspace: session.workspace
        )
        
        if effectivePolicy == .neverInterrupt {
            return .suppress(reason: "Policy for \(session.providerID.rawValue) is set to Never Interrupt.")
        }
        
        if effectivePolicy == .notificationOnly {
            return .notifyOnly(reason: "Policy is set to Notification Only.")
        }
        
        // 3. Protected Application check
        if let frontApp = frontmostApp, let frontBundle = frontApp.bundleIdentifier {
            let isProtected = config.protectedApplications.contains(where: {
                frontBundle.localizedCaseInsensitiveContains($0)
            })
            if isProtected {
                let reason = "Protected application '\(frontApp.localizedName ?? frontBundle)' is frontmost. Not interrupting."
                logger.info("\(reason)")
                return .notifyOnly(reason: reason)
            }
        }
        
        // 4. Fullscreen check
        if windowController.isFrontmostWindowFullscreen() && effectivePolicy != .alwaysRestore {
            let reason = "Frontmost application is in Fullscreen presentation mode. Showing notification instead."
            logger.info("\(reason)")
            return .notifyOnly(reason: reason)
        }
        
        // 5. Origin context validation
        guard let origin = session.originContext else {
            return .notifyOnly(reason: "No origin context captured for session.")
        }
        
        // 6. Application liveness check: verify originating application is still running
        let originAppRunning = (appController.runningApplication(forProcessIdentifier: origin.processIdentifier) != nil) ||
            (!appController.runningApplications(withBundleIdentifier: origin.bundleIdentifier).isEmpty)
        if !originAppRunning {
            let reason = "Originating application '\(origin.bundleName)' (PID: \(origin.processIdentifier)) is no longer running."
            logger.info("\(reason)")
            return .notifyOnly(reason: reason)
        }
        
        let userLeftOrigin = (frontmostApp?.bundleIdentifier != origin.bundleIdentifier)
        
        // 7. User Intent / Active Interaction check
        if userLeftOrigin && effectivePolicy != .alwaysRestore {
            let isActivelyUsing = idleTracker.isUserActive(within: config.activeInteractionThresholdSeconds)
            if isActivelyUsing {
                let frontName = frontmostApp?.localizedName ?? "another application"
                let reason = "User is actively interacting with \(frontName) (idle time < \(config.activeInteractionThresholdSeconds)s). Avoiding focus disruption."
                logger.info("\(reason)")
                return .notifyOnly(reason: reason)
            }
        }
        
        // 8. Policy: Restore if user left origin
        if effectivePolicy == .restoreIfUserLeftOrigin && !userLeftOrigin {
            return .notifyOnly(reason: "User is already in origin application.")
        }
        
        // 9. Space policy check
        if let winID = origin.windowIdentifier {
            let onActiveSpace = spaceController.isWindowOnActiveSpace(windowID: winID)
            if !spaceController.shouldSwitchSpace(for: config.spacePolicy, windowOnCurrentSpace: onActiveSpace) {
                let reason = "Origin window is on a different macOS Space. Space policy prohibits auto-switching."
                logger.info("\(reason)")
                return .notifyOnly(reason: reason)
            }
        }
        
        // 10. Origin restoration
        return .restoreOrigin(
            context: origin,
            reason: "Agent completed and user is idle. Restoring \(origin.displayLabel)."
        )
    }
}
