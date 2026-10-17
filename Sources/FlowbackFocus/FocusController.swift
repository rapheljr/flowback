import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "FocusController")

public actor FocusController {
    private let appController: ApplicationControlling
    private let windowController: WindowControlling
    private let intentEngine: UserIntentEngine
    private let arbiter: AttentionArbiter
    private let adapterRegistry: ApplicationAdapterRegistry
    private let timeline: TimelineTracker
    private let urlOpener: @Sendable (URL) -> Bool

    public init(
        appController: ApplicationControlling = ApplicationController.shared,
        windowController: WindowControlling = WindowController.shared,
        intentEngine: UserIntentEngine = UserIntentEngine(),
        arbiter: AttentionArbiter = AttentionArbiter(),
        adapterRegistry: ApplicationAdapterRegistry = .shared,
        timeline: TimelineTracker = .shared,
        urlOpener: (@Sendable (URL) -> Bool)? = nil
    ) {
        self.appController = appController
        self.windowController = windowController
        self.intentEngine = intentEngine
        self.arbiter = arbiter
        self.adapterRegistry = adapterRegistry
        self.timeline = timeline
        self.urlOpener = urlOpener ?? { url in
            NSWorkspace.shared.open(url)
        }
    }

    /// Evaluates user intent and executes focus switch or returns notification requirement
    public func handleSessionCompletion(
        session: AgentSession,
        config: PolicyConfiguration,
        focusLock: FocusLockState
    ) async -> FocusDecision {

        let decision = intentEngine.evaluate(
            session: session,
            config: config,
            focusLock: focusLock,
            frontmostApp: appController.frontmostApplication()
        )

        await timeline.record(
            sessionID: session.id,
            category: "Decision",
            summary: "Focus decision: \(decision)",
            explanation: decision.explanation
        )

        switch decision {
        case .restoreOrigin(let origin, let reason):
            // Check cooldown before restoring
            let canRestore = await arbiter.canRestoreFocusNow()
            if !canRestore {
                let cooldownReason = "Focus cooldown active (< \(config.focusCooldownMs)ms). Deferred focus switch."
                await timeline.record(
                    sessionID: session.id,
                    category: "Cooldown",
                    summary: cooldownReason
                )
                return .deferAction(reasonCode: .cooldownActive, explanation: cooldownReason)
            }

            let restored = await restoreContext(origin)
            if restored {
                await arbiter.recordFocusRestoration()
                await timeline.record(
                    sessionID: session.id,
                    category: "Restoration",
                    summary: "Successfully restored focus to \(origin.displayLabel)",
                    explanation: reason
                )
                return decision
            } else {
                let fallbackReason = "Direct restoration failed; falling back to notification."
                await timeline.record(
                    sessionID: session.id,
                    category: "Restoration",
                    summary: fallbackReason
                )
                return .notifyOnly(reason: fallbackReason)
            }

        case .fallbackApplication(let bundleID, let reason):
            if let app = appController.runningApplications(withBundleIdentifier: bundleID).first {
                _ = appController.activate(application: app)
                await arbiter.recordFocusRestoration()
                return decision
            }
            return .notifyOnly(reason: reason)

        case .notifyOnly, .deferAction, .suppress:
            return decision
        }
    }

    /// Restores focus to a specific origin context using the appropriate adapter
    public func restoreContext(_ context: OriginContext) async -> Bool {
        // If the destination context specifies a remote web destination (e.g. cloud agent dashboard or PR),
        // validate scheme (http/https only) and open directly via macOS workspace API.
        // Never activate Safari as a substitute for opening a destination URL.
        if let targetURLString = context.workspacePath ?? context.workspaceIdentifier,
           let url = URL(string: targetURLString),
           let scheme = url.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https" else {
                logger.warning("Rejected unsupported or unsafe destination URL scheme: \(scheme)")
                return false
            }
            logger.info("Opening remote web destination: \(url.absoluteString)")
            return urlOpener(url)
        }

        // If bundle is Safari without a valid web URL, reject activation
        if context.bundleIdentifier == "com.apple.Safari" {
            logger.warning("Rejecting Safari activation fallback without valid remote web URL destination")
            return false
        }

        let adapter = adapterRegistry.findAdapter(for: context.bundleIdentifier) ?? GenericApplicationAdapter()
        logger.info("Restoring context for \(context.bundleIdentifier) using \(adapter.adapterName)")

        return await adapter.restoreContext(
            context: context,
            appController: appController,
            windowController: windowController
        )
    }

    /// Manually restores focus to a session (e.g. from menu bar or CLI)
    public func manualFocusSession(_ session: AgentSession) async -> Bool {
        guard let origin = session.originContext else {
            logger.warning("Session \(session.id) has no origin context to restore")
            return false
        }
        await timeline.record(
            sessionID: session.id,
            category: "Manual",
            summary: "Manual focus triggered by user",
            details: origin.displayLabel
        )
        return await restoreContext(origin)
    }
}
