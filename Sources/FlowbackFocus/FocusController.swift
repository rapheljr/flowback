import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "FocusController")

/// Stable representation of an in-flight navigation request
public struct NavigationRequestToken: Sendable, Equatable {
    public let id: UUID
    public let generation: UInt64
    public let sessionID: AgentSessionID
    public let initiatedAt: Date

    public init(id: UUID = UUID(), generation: UInt64, sessionID: AgentSessionID, initiatedAt: Date = Date()) {
        self.id = id
        self.generation = generation
        self.sessionID = sessionID
        self.initiatedAt = initiatedAt
    }
}

public actor FocusController {
    private let appController: ApplicationControlling
    private let windowController: WindowControlling
    private let intentEngine: UserIntentEngine
    private let arbiter: AttentionArbiter
    private let adapterRegistry: ApplicationAdapterRegistry
    private let timeline: TimelineTracker
    private let urlOpener: @Sendable (URL) -> Bool
    private let defaultTimeout: TimeInterval
    private let permissionChecker: @Sendable () -> Bool

    private struct ActiveCancellation: Sendable {
        let generation: UInt64
        let handler: @Sendable () -> Void
    }

    private var currentGeneration: UInt64 = 0
    private var activeRequest: NavigationRequestToken?
    private var isCancelled: Bool = false
    private var isShutDown: Bool = false
    private var activeCancellation: ActiveCancellation?

    private func invokeActiveCancellation() {
        activeCancellation?.handler()
        activeCancellation = nil
    }

    public init(
        appController: ApplicationControlling = ApplicationController.shared,
        windowController: WindowControlling = WindowController.shared,
        intentEngine: UserIntentEngine = UserIntentEngine(),
        arbiter: AttentionArbiter = AttentionArbiter(),
        adapterRegistry: ApplicationAdapterRegistry = .shared,
        timeline: TimelineTracker = .shared,
        urlOpener: (@Sendable (URL) -> Bool)? = nil,
        defaultTimeout: TimeInterval = 5.0,
        permissionChecker: (@Sendable () -> Bool)? = nil
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
        self.defaultTimeout = defaultTimeout
        self.permissionChecker = permissionChecker ?? {
            PermissionManager.shared.isAccessibilityGranted()
        }
    }

    /// Returns the current monotonic generation counter
    public func activeGeneration() -> UInt64 {
        currentGeneration
    }

    /// Returns the currently active in-flight navigation token, if any
    public func activeRequestToken() -> NavigationRequestToken? {
        activeRequest
    }

    /// Evaluates if a given navigation generation has been superseded by a newer request or cancelled
    public func isSuperseded(generation: UInt64) -> Bool {
        generation < currentGeneration || isCancelled || isShutDown
    }

    /// Explicitly cancels any currently in-flight navigation request
    public func cancelCurrentNavigation() {
        invokeActiveCancellation()
        currentGeneration += 1
        isCancelled = true
        activeRequest = nil
        logger.info("Current navigation cancelled; incremented generation to \(self.currentGeneration)")
    }

    /// Shuts down the coordinator, cancelling all active work and rejecting subsequent requests
    public func shutdown() {
        isShutDown = true
        cancelCurrentNavigation()
        logger.info("FocusController shut down")
    }

    /// Evaluates user intent and executes focus switch or returns notification requirement
    public func handleSessionCompletion(
        session: AgentSession,
        config: PolicyConfiguration,
        focusLock: FocusLockState,
        isSessionActive: Bool = true
    ) async -> FocusDecision {

        let decision = intentEngine.evaluate(
            session: session,
            config: config,
            focusLock: focusLock,
            frontmostApp: appController.frontmostApplication(),
            isSessionActive: isSessionActive
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
            if isShutDown || isCancelled {
                return .notifyOnly(reason: "Fallback application activation cancelled: FocusController is not active")
            }
            invokeActiveCancellation()

            currentGeneration += 1
            let thisGeneration = currentGeneration
            let token = NavigationRequestToken(
                generation: thisGeneration,
                sessionID: session.id
            )
            activeRequest = token

            if isSuperseded(generation: thisGeneration) {
                return .notifyOnly(reason: "Fallback application activation superseded before start")
            }

            if let app = appController.runningApplications(withBundleIdentifier: bundleID).first {
                if isSuperseded(generation: thisGeneration) {
                    return .notifyOnly(reason: "Fallback application activation superseded before launch")
                }
                let activated = await appController.activateApplication(app)
                if isSuperseded(generation: thisGeneration) {
                    return .notifyOnly(reason: "Fallback application activation superseded after launch")
                }
                if activated {
                    await arbiter.recordFocusRestoration()
                    return decision
                }
            }
            return .notifyOnly(reason: reason)

        case .notifyOnly, .deferAction, .suppress:
            return decision
        }
    }
}

// MARK: - Session & Context Restoration

extension FocusController {
    /// Comprehensive, provider-aware conversation restoration implementing Section 14 & Phase 7 priority
    public func restoreSession(_ session: AgentSession, timeout: TimeInterval? = nil) async -> RestorationResult {
        let convTitle = session.conversationTitle ?? session.displayTitle
        let convID = session.conversationID ?? session.providerSessionID ?? session.id.rawValue

        if isShutDown {
            return RestorationResult(
                outcome: .operationCancelled,
                sessionID: session.id,
                providerID: session.providerID,
                conversationID: convID,
                conversationTitle: convTitle,
                targetDescription: session.projectName,
                message: "Restoration aborted: FocusController is shut down"
            )
        }

        invokeActiveCancellation()
        currentGeneration += 1
        let thisGeneration = currentGeneration
        let requestID = UUID()
        let token = NavigationRequestToken(
            id: requestID,
            generation: thisGeneration,
            sessionID: session.id,
            initiatedAt: Date()
        )
        activeRequest = token
        isCancelled = false

        let effectiveTimeout = timeout ?? self.defaultTimeout

        if isSuperseded(generation: thisGeneration) {
            return makeCancelledResult(
                session: session,
                convID: convID,
                convTitle: convTitle,
                target: session.projectName,
                message: "Restoration cancelled before execution began"
            )
        }

        // Priority 1 & 4: Provider destination URL / Pull Request / Remote Dashboard
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

            if isSuperseded(generation: thisGeneration) {
                return makeCancelledResult(
                    session: session,
                    convID: convID,
                    convTitle: convTitle,
                    target: targetURL.absoluteString,
                    message: "Restoration superseded before opening destination URL"
                )
            }

            logger.info("Opening provider web destination: \(targetURL.absoluteString)")
            let opened = urlOpener(targetURL)

            if isSuperseded(generation: thisGeneration) {
                return makeCancelledResult(
                    session: session,
                    convID: convID,
                    convTitle: convTitle,
                    target: targetURL.absoluteString,
                    message: "Destination URL was opened, but request was superseded by a newer navigation request"
                )
            }

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

        // Permission check: if windowIdentifier is set, accessibility permission is mandatory to raise it
        if origin.windowIdentifier != nil && !permissionChecker() {
            logger.warning("Accessibility permission denied; cannot perform window-level restoration for session \(session.id)")
            return RestorationResult(
                outcome: .permissionDenied,
                sessionID: session.id,
                providerID: session.providerID,
                conversationID: convID,
                conversationTitle: convTitle,
                targetDescription: origin.displayLabel,
                message: "Accessibility permissions denied. Cannot perform window-level restoration."
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

        if isSuperseded(generation: thisGeneration) {
            return makeCancelledResult(
                session: session,
                convID: convID,
                convTitle: convTitle,
                target: origin.displayLabel,
                message: "Restoration superseded before activating window"
            )
        }

        // Priority 2: CLI / Terminal resume command for Terminal-based agents
        if let resumeHint = ResumeCommandRegistry.shared.resumeCommand(for: session) {
            let adapter = adapterRegistry.findAdapter(for: origin.bundleIdentifier) ?? GenericApplicationAdapter()
            let appCtrl = self.appController
            let winCtrl = self.windowController
            let timeoutResult = await executeWithTimeout(timeout: effectiveTimeout, generation: thisGeneration) {
                await adapter.restoreContext(
                    context: origin,
                    appController: appCtrl,
                    windowController: winCtrl
                )
            }

            if isSuperseded(generation: thisGeneration) {
                return makeCancelledResult(
                    session: session,
                    convID: convID,
                    convTitle: convTitle,
                    target: origin.displayLabel,
                    message: "Terminal window restoration was superseded by a newer navigation request"
                )
            }

            switch timeoutResult {
            case .cancelled:
                return makeCancelledResult(
                    session: session,
                    convID: convID,
                    convTitle: convTitle,
                    target: origin.displayLabel,
                    message: "Terminal window restoration was cancelled"
                )
            case .timedOut:
                return RestorationResult(
                    outcome: .operationTimedOut,
                    sessionID: session.id,
                    providerID: session.providerID,
                    conversationID: convID,
                    conversationTitle: convTitle,
                    targetDescription: origin.displayLabel,
                    message: "Restoration timed out waiting for terminal adapter response"
                )
            case .success(let restoredSuccess):
                if isSuperseded(generation: thisGeneration) {
                    return makeCancelledResult(
                        session: session,
                        convID: convID,
                        convTitle: convTitle,
                        target: origin.displayLabel,
                        message: "Terminal window was activated, but the operation was superseded by a newer navigation request"
                    )
                }

                if restoredSuccess {
                    return RestorationResult(
                        outcome: .resumeHintPresented,
                        sessionID: session.id,
                        providerID: session.providerID,
                        conversationID: convID,
                        conversationTitle: convTitle,
                        targetDescription: origin.displayLabel,
                        message: "Activated workspace terminal window with resume hint: (\(resumeHint))"
                    )
                } else {
                    return RestorationResult(
                        outcome: .restorationFailed,
                        sessionID: session.id,
                        providerID: session.providerID,
                        conversationID: convID,
                        conversationTitle: convTitle,
                        targetDescription: origin.displayLabel,
                        message: "Failed to raise target terminal window for \(origin.displayLabel)"
                    )
                }
            }
        }

        let adapter = adapterRegistry.findAdapter(for: origin.bundleIdentifier) ?? GenericApplicationAdapter()
        logger.info("Restoring origin for \(origin.bundleIdentifier) via \(adapter.adapterName)")

        let appCtrl = self.appController
        let winCtrl = self.windowController
        let timeoutResult = await executeWithTimeout(timeout: effectiveTimeout, generation: thisGeneration) {
            await adapter.restoreContext(
                context: origin,
                appController: appCtrl,
                windowController: winCtrl
            )
        }

        if isSuperseded(generation: thisGeneration) {
            return makeCancelledResult(
                session: session,
                convID: convID,
                convTitle: convTitle,
                target: origin.displayLabel,
                message: "Target application was activated, but the operation was superseded by a newer navigation request"
            )
        }

        switch timeoutResult {
        case .cancelled:
            return makeCancelledResult(
                session: session,
                convID: convID,
                convTitle: convTitle,
                target: origin.displayLabel,
                message: "Restoration was cancelled"
            )
        case .timedOut:
            return RestorationResult(
                outcome: .operationTimedOut,
                sessionID: session.id,
                providerID: session.providerID,
                conversationID: convID,
                conversationTitle: convTitle,
                targetDescription: origin.displayLabel,
                message: "Restoration timed out waiting for application adapter response"
            )
        case .success(let restoredSuccess):
            if isSuperseded(generation: thisGeneration) {
                return makeCancelledResult(
                    session: session,
                    convID: convID,
                    convTitle: convTitle,
                    target: origin.displayLabel,
                    message: "Target application was activated, but the operation was superseded by a newer navigation request"
                )
            }

            if restoredSuccess {
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
    }

    /// Restores focus to a specific origin context using the appropriate adapter
    public func restoreContext(_ context: OriginContext, timeout: TimeInterval? = nil) async -> Bool {
        if isShutDown { return false }

        // Cancel previous active navigation
        invokeActiveCancellation()

        currentGeneration += 1
        let thisGeneration = currentGeneration
        let token = NavigationRequestToken(
            generation: thisGeneration,
            sessionID: AgentSessionID(context.workspaceIdentifier ?? UUID().uuidString)
        )
        activeRequest = token
        isCancelled = false

        if isSuperseded(generation: thisGeneration) { return false }

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
            if isSuperseded(generation: thisGeneration) { return false }
            logger.info("Opening remote web destination: \(url.absoluteString)")
            let opened = urlOpener(url)
            return !isSuperseded(generation: thisGeneration) && opened
        }

        // If bundle is Safari without a valid web URL, reject activation
        if context.bundleIdentifier == "com.apple.Safari" {
            logger.warning("Rejecting Safari activation fallback without valid remote web URL destination")
            return false
        }

        let adapter = adapterRegistry.findAdapter(for: context.bundleIdentifier) ?? GenericApplicationAdapter()
        logger.info("Restoring context for \(context.bundleIdentifier) using \(adapter.adapterName)")

        let appCtrl = self.appController
        let winCtrl = self.windowController
        let effectiveTimeout = timeout ?? self.defaultTimeout

        let timeoutResult = await executeWithTimeout(timeout: effectiveTimeout, generation: thisGeneration) {
            await adapter.restoreContext(
                context: context,
                appController: appCtrl,
                windowController: winCtrl
            )
        }

        if isSuperseded(generation: thisGeneration) {
            return false
        }

        guard case .success(let restored) = timeoutResult else {
            return false
        }

        return restored
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
        if result.outcome.isSuccessful {
            await arbiter.recordFocusRestoration()
        }
        return result.outcome.isSuccessful
    }

    // MARK: - Private Helpers

    private func makeCancelledResult(
        session: AgentSession,
        convID: String,
        convTitle: String?,
        target: String,
        message: String
    ) -> RestorationResult {
        RestorationResult(
            outcome: .operationCancelled,
            sessionID: session.id,
            providerID: session.providerID,
            conversationID: convID,
            conversationTitle: convTitle,
            targetDescription: target,
            message: message
        )
    }

    private func executeWithTimeout<T: Sendable>(
        timeout: TimeInterval,
        generation: UInt64,
        operation: @escaping @Sendable () async -> T
    ) async -> TimeoutResult<T> {
        guard timeout > 0 else {
            return .timedOut
        }
        if Task.isCancelled || isSuperseded(generation: generation) {
            return .cancelled
        }

        let coordinator = TimeoutCoordinator<T>()

        self.activeCancellation = ActiveCancellation(generation: generation) { [weak coordinator] in
            coordinator?.cancel()
        }

        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                coordinator.startWaiting(continuation: continuation)

                let worker = Task {
                    let val = await operation()
                    coordinator.complete(with: .success(val))
                }

                let timer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    coordinator.complete(with: .timedOut)
                }

                coordinator.setChildTasks(worker: worker, timeout: timer)
            }
        } onCancel: {
            coordinator.cancel()
        }

        if self.activeCancellation?.generation == generation {
            self.activeCancellation = nil
        }
        return result
    }
}

public enum TimeoutResult<T: Sendable>: Sendable {
    case success(T)
    case timedOut
    case cancelled
}

extension TimeoutResult: Equatable where T: Equatable {}

public final class TimeoutCoordinator<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()

    private enum State {
        case initial
        case waiting(CheckedContinuation<TimeoutResult<T>, Never>)
        case completed(TimeoutResult<T>)
    }

    private var state: State = .initial
    private var workerTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    public init() {}

    public var hasRetainedChildTasks: Bool {
        lock.withLock {
            workerTask != nil || timeoutTask != nil
        }
    }

    public func setChildTasks(worker: Task<Void, Never>, timeout: Task<Void, Never>) {
        var shouldCancel = false
        lock.withLock {
            if case .completed = state {
                shouldCancel = true
            } else {
                self.workerTask = worker
                self.timeoutTask = timeout
            }
        }
        if shouldCancel {
            worker.cancel()
            timeout.cancel()
        }
    }

    public func startWaiting(continuation: CheckedContinuation<TimeoutResult<T>, Never>) {
        var immediateResult: TimeoutResult<T>?
        lock.withLock {
            switch state {
            case .initial:
                state = .waiting(continuation)
            case .completed(let result):
                immediateResult = result
            case .waiting:
                break
            }
        }
        if let result = immediateResult {
            continuation.resume(returning: result)
        }
    }

    public func complete(with result: TimeoutResult<T>) {
        var toResume: CheckedContinuation<TimeoutResult<T>, Never>?
        var tasksToCancel: (Task<Void, Never>?, Task<Void, Never>?) = (nil, nil)

        lock.withLock {
            switch state {
            case .waiting(let continuation):
                state = .completed(result)
                toResume = continuation
                tasksToCancel = (workerTask, timeoutTask)
                self.workerTask = nil
                self.timeoutTask = nil
            case .initial:
                state = .completed(result)
                tasksToCancel = (workerTask, timeoutTask)
                self.workerTask = nil
                self.timeoutTask = nil
            case .completed:
                // Terminal transition already occurred; drop subsequent completion
                break
            }
        }

        tasksToCancel.0?.cancel()
        tasksToCancel.1?.cancel()
        toResume?.resume(returning: result)
    }

    public func cancel() {
        complete(with: .cancelled)
    }
}
