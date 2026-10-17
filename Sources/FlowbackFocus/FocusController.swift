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
        case .restoreOrigin(_, let reason), .restoreDestination(_, let reason):
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

            let result = await restoreSession(session)
            if result.outcome.isSuccessful {
                await arbiter.recordFocusRestoration()
                await timeline.record(
                    sessionID: session.id,
                    category: "Restoration",
                    summary: result.message,
                    explanation: reason
                )
                return decision
            } else {
                let fallbackReason = "Direct restoration failed (\(result.outcome.rawValue)); falling back to notification."
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

    /// Comprehensive, provider-aware conversation restoration implementing Section 14 & Phase 7 priority
    public func restoreSession(_ session: AgentSession) async -> RestorationResult {
        let convTitle = session.conversationTitle ?? session.displayTitle
        let convID = session.conversationID ?? session.providerSessionID ?? session.id.rawValue

        // Priority 1 & 4: Provider destination URL / Pull Request / Remote Dashboard
        // If session is a remote agent (e.g. Cursor background agent) or has a valid conversationURL
        var destinationURL: URL?
        if let url = session.conversationURL {
            destinationURL = url
        } else if let ws = session.originContext?.workspacePath,
                  (ws.hasPrefix("http://") || ws.hasPrefix("https://")),
                  let url = URL(string: ws) {
            destinationURL = url
        }

        if let targetURL = destinationURL {
            let scheme = targetURL.scheme?.lowercased() ?? ""
            guard scheme == "http" || scheme == "https" else {
                logger.warning("Rejected non-http/https URL scheme for restoration: '\(scheme)'")
                return RestorationResult(
                    outcome: .restorationFailed,
                    sessionID: session.id,
                    providerID: session.providerID,
                    conversationID: convID,
                    conversationTitle: convTitle,
                    targetDescription: targetURL.absoluteString,
                    message: "Rejected unsafe destination URL scheme: '\(scheme)'"
                )
            }

            logger.info("Opening provider web destination: \(targetURL.absoluteString)")
            let opened = urlOpener(targetURL)
            if opened {
                return RestorationResult(
                    outcome: .providerURLOpened,
                    sessionID: session.id,
                    providerID: session.providerID,
                    conversationID: convID,
                    conversationTitle: convTitle,
                    targetDescription: targetURL.absoluteString,
                    message: "Opened destination URL: \(targetURL.absoluteString)"
                )
            } else {
                return RestorationResult(
                    outcome: .restorationFailed,
                    sessionID: session.id,
                    providerID: session.providerID,
                    conversationID: convID,
                    conversationTitle: convTitle,
                    targetDescription: targetURL.absoluteString,
                    message: "Failed to open destination URL: \(targetURL.absoluteString)"
                )
            }
        }

        // Priority 2: CLI / Terminal resume command for Terminal-based agents
        if let resumeHint = ResumeCommandRegistry.shared.resumeCommand(for: session), let origin = session.originContext {
            // Try raising the exact terminal window
            let adapter = adapterRegistry.findAdapter(for: origin.bundleIdentifier) ?? GenericApplicationAdapter()
            let restored = await adapter.restoreContext(
                context: origin,
                appController: appController,
                windowController: windowController
            )
            if restored {
                return RestorationResult(
                    outcome: .resumeHintPresented,
                    sessionID: session.id,
                    providerID: session.providerID,
                    conversationID: convID,
                    conversationTitle: convTitle,
                    targetDescription: origin.displayLabel,
                    message: "Activated workspace terminal window with resume hint: (\(resumeHint))"
                )
            }
        }

        // Priority 3 & 5: Local Window & Workspace via Adapter
        guard let origin = session.originContext else {
            let outcome: RestorationOutcome = (session.focusCapability == .unavailable) ? .restorationUnsupported : .conversationUnavailable
            logger.warning("Session \(session.id) has no origin context or destination URL to restore")
            return RestorationResult(
                outcome: outcome,
                sessionID: session.id,
                providerID: session.providerID,
                conversationID: convID,
                conversationTitle: convTitle,
                targetDescription: session.projectName,
                message: "No origin context or destination target available for session \(session.id.rawValue)"
            )
        }

        // Ambiguous target safety check:
        // If windowIdentifier is missing and multiple windows match the same workspace title for this PID
        if origin.windowIdentifier == nil && origin.processIdentifier > 0, let ws = origin.workspacePath {
            let folderName = (ws as NSString).lastPathComponent
            let candidateWindows = windowController.listWindows(forProcessIdentifier: origin.processIdentifier).filter {
                $0.title.localizedCaseInsensitiveContains(folderName)
            }
            if candidateWindows.count > 1 {
                logger.warning("Ambiguous target: \(candidateWindows.count) matching windows found for workspace '\(folderName)'")
                return RestorationResult(
                    outcome: .targetAmbiguous,
                    sessionID: session.id,
                    providerID: session.providerID,
                    conversationID: convID,
                    conversationTitle: convTitle,
                    targetDescription: origin.displayLabel,
                    message: "Multiple windows (\(candidateWindows.count)) matched workspace '\(folderName)'. Restoration aborted to prevent guessing."
                )
            }
        }

        let adapter = adapterRegistry.findAdapter(for: origin.bundleIdentifier) ?? GenericApplicationAdapter()
        logger.info("Restoring origin for \(origin.bundleIdentifier) via \(adapter.adapterName)")

        let restored = await adapter.restoreContext(
            context: origin,
            appController: appController,
            windowController: windowController
        )

        if restored {
            // Determine honest outcome based on restored context:
            // Activating an application window or matching a workspace directory does not confirm internal conversation selection.
            let outcome: RestorationOutcome
            let message: String
            if origin.workspacePath != nil {
                outcome = .workspaceActivatedOnly
                message = "Activated workspace window for \(origin.displayLabel)"
            } else {
                outcome = .windowActivatedOnly
                message = "Activated application window for \(origin.displayLabel)"
            }

            return RestorationResult(
                outcome: outcome,
                sessionID: session.id,
                providerID: session.providerID,
                conversationID: convID,
                conversationTitle: convTitle,
                targetDescription: origin.displayLabel,
                message: message
            )
        } else {
            return RestorationResult(
                outcome: .restorationFailed,
                sessionID: session.id,
                providerID: session.providerID,
                conversationID: convID,
                conversationTitle: convTitle,
                targetDescription: origin.displayLabel,
                message: "Failed to raise target window for \(origin.displayLabel)"
            )
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
    @discardableResult
    public func manualFocusSession(_ session: AgentSession) async -> Bool {
        await timeline.record(
            sessionID: session.id,
            category: "Manual",
            summary: "Manual focus triggered by user for \(session.displayTitle)",
            details: session.originContext?.displayLabel ?? session.projectName
        )
        let result = await restoreSession(session)
        return result.outcome.isSuccessful
    }
}
