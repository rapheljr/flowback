import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "UserIntentEngine")

/// Deterministic result of a focus evaluation
public enum FocusDecision: Equatable, Sendable {
    case restoreOrigin(context: OriginContext, reason: String)
    case fallbackApplication(bundleID: String, reason: String)
    case notifyOnly(reason: String)
    case suppress(reason: String)
    
    public var shouldActivateApp: Bool {
        switch self {
        case .restoreOrigin, .fallbackApplication:
            return true
        case .notifyOnly, .suppress:
            return false
        }
    }
    
    public var explanation: String {
        switch self {
        case .restoreOrigin(_, let reason): return reason
        case .fallbackApplication(_, let reason): return reason
        case .notifyOnly(let reason): return reason
        case .suppress(let reason): return reason
        }
    }
}

/// Evaluates user activity, frontmost context, and policies to make deterministic focus decisions
public struct UserIntentEngine: Sendable {
    private let idleTracker: IdleTracking
    private let windowController: WindowControlling
    private let spaceController: SpaceControlling
    
    public init(
        idleTracker: IdleTracking = IdleTracker.shared,
        windowController: WindowControlling = WindowController.shared,
        spaceController: SpaceControlling = SpaceController.shared
    ) {
        self.idleTracker = idleTracker
        self.windowController = windowController
        self.spaceController = spaceController
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
        
        let userLeftOrigin = (frontmostApp?.bundleIdentifier != origin.bundleIdentifier)
        
        // 6. User Intent / Active Interaction check
        if userLeftOrigin && effectivePolicy != .alwaysRestore {
            let isActivelyUsing = idleTracker.isUserActive(within: config.activeInteractionThresholdSeconds)
            if isActivelyUsing {
                let frontName = frontmostApp?.localizedName ?? "another application"
                let reason = "User is actively interacting with \(frontName) (idle time < \(config.activeInteractionThresholdSeconds)s). Avoiding focus disruption."
                logger.info("\(reason)")
                return .notifyOnly(reason: reason)
            }
        }
        
        // 7. Policy: Restore if user left origin
        if effectivePolicy == .restoreIfUserLeftOrigin && !userLeftOrigin {
            return .notifyOnly(reason: "User is already in origin application.")
        }
        
        // 8. Space policy check
        if let winID = origin.windowIdentifier {
            let onActiveSpace = spaceController.isWindowOnActiveSpace(windowID: winID)
            if !spaceController.shouldSwitchSpace(for: config.spacePolicy, windowOnCurrentSpace: onActiveSpace) {
                let reason = "Origin window is on a different macOS Space. Space policy prohibits auto-switching."
                logger.info("\(reason)")
                return .notifyOnly(reason: reason)
            }
        }
        
        // 9. Origin restoration
        return .restoreOrigin(
            context: origin,
            reason: "Agent completed and user is idle. Restoring \(origin.displayLabel)."
        )
    }
}
