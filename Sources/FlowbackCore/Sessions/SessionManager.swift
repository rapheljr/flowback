import Foundation
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "SessionManager")

public protocol SessionStorageDelegate: AnyObject, Sendable {
    func saveSession(_ session: AgentSession) async throws
    func fetchSession(id: AgentSessionID) async throws -> AgentSession?
    func fetchActiveSessions() async throws -> [AgentSession]
    func fetchRecentSessions(limit: Int) async throws -> [AgentSession]
}

/// Coordinates agent session lifecycle, state transitions, and timeline tracking
public actor SessionManager {
    public let maxCompletedSessionsInMemory: Int
    private var sessions: [AgentSessionID: AgentSession] = [:]
    private let stateMachine = AgentStateMachine()
    private let timeline: TimelineTracker
    private weak var storageDelegate: SessionStorageDelegate?
    private let eventBus: EventBus?

    public init(
        timeline: TimelineTracker = .shared,
        storageDelegate: SessionStorageDelegate? = nil,
        eventBus: EventBus? = nil,
        maxCompletedSessionsInMemory: Int = 100
    ) {
        self.timeline = timeline
        self.storageDelegate = storageDelegate
        self.eventBus = eventBus
        self.maxCompletedSessionsInMemory = maxCompletedSessionsInMemory
    }

    public func setStorageDelegate(_ delegate: SessionStorageDelegate) {
        self.storageDelegate = delegate
    }

    // MARK: - Session Retrieval

    public func getSession(id: AgentSessionID) async -> AgentSession? {
        if let cached = sessions[id] {
            return cached
        }
        if let stored = try? await storageDelegate?.fetchSession(id: id) {
            sessions[id] = stored
            enforceRetentionPolicy()
            return stored
        }
        return nil
    }

    private func enforceRetentionPolicy() {
        let terminal = sessions.values.filter { $0.state.isTerminal }
        if terminal.count > maxCompletedSessionsInMemory {
            let sortedOldest = terminal.sorted {
                ($0.completedAt ?? $0.updatedAt) < ($1.completedAt ?? $1.updatedAt)
            }
            let excess = terminal.count - maxCompletedSessionsInMemory
            for i in 0..<min(excess, sortedOldest.count) {
                sessions.removeValue(forKey: sortedOldest[i].id)
            }
        }
    }

    public var inMemoryCompletedSessionCount: Int {
        sessions.values.filter { $0.state.isTerminal }.count
    }

    public var inMemoryTotalSessionCount: Int {
        sessions.count
    }

    public func getActiveSessions() -> [AgentSession] {
        sessions.values.filter { $0.state.isActive }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func getAllSessions() -> [AgentSession] {
        sessions.values.sorted { $0.startedAt > $1.startedAt }
    }

    public func getRecentSessions(limit: Int = 10) -> [AgentSession] {
        let all = Array(sessions.values.sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) })
        return Array(all.prefix(limit))
    }

    /// Returns all sessions associated with a specific workspace or project
    public func getSessions(inWorkspace workspace: String) -> [AgentSession] {
        let clean = workspace.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard !clean.isEmpty else { return [] }
        return sessions.values.filter { s in
            guard let ws = s.workspace else { return false }
            let sClean = ws.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            return sClean == clean || sClean.hasSuffix("/" + clean) || clean.hasSuffix("/" + sClean)
        }.sorted { $0.startedAt > $1.startedAt }
    }

    /// Returns all sessions sharing the same project name
    public func getSessions(matchingProject projectName: String) -> [AgentSession] {
        let clean = projectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return [] }
        return sessions.values.filter { $0.projectName.lowercased() == clean }
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Proactive Discovery Merging

    @discardableResult
    public func mergeDiscoveredSessions(_ discovered: [AgentSession]) async -> [AgentEvent] {
        let now = Date()
        var generatedEvents: [AgentEvent] = []

        for s in discovered {
            if let existing = sessions[s.id] {
                let wasInterruptedByRestart = existing.state == .cancelled &&
                    existing.errorDescription == "Interrupted by system restart or application relaunch"
                let isReactivating = (existing.state.isTerminal && s.state.isActive)

                // 1. Stale protection: reject discovery results older than existing session update
                // Exemptions:
                // a) Recovery from restart reconciliation (agent is still alive)
                // b) Genuine multi-turn reactivation where new activity occurred
                let isStale = s.updatedAt < existing.updatedAt.addingTimeInterval(-2.0)
                if isStale {
                    if wasInterruptedByRestart && s.state.isActive {
                        // Recover session that was prematurely marked cancelled on restart
                        logger.info("Recovering active session \(s.id) after system restart")
                    } else if isReactivating && (existing.completedAt == nil || s.updatedAt >= existing.completedAt!.addingTimeInterval(-2.0)) {
                        // Multi-turn reactivation
                    } else {
                        logger.debug("Dropped stale discovered session \(s.id) (timestamp \(s.updatedAt) < existing \(existing.updatedAt))")
                        continue
                    }
                }

                // 2. Meaningful state change detection
                if s.state != existing.state {
                    // Check if state transition is legally valid according to finite state machine or multi-turn reactivation
                    let canTransition = stateMachine.canTransition(from: existing.state, to: s.state) || isReactivating || wasInterruptedByRestart
                    if canTransition {
                        let eventType: AgentEventType
                        switch s.state {
                        case .completed: eventType = .agentCompleted
                        case .failed: eventType = .agentFailed
                        case .cancelled: eventType = .agentCancelled
                        case .waiting: eventType = .agentWaiting
                        case .permissionRequired: eventType = .agentPermissionRequired
                        case .running: eventType = .agentRunning
                        case .starting: eventType = .agentStarted
                        default: eventType = .agentRunning
                        }

                        var updated = existing
                        updated.state = s.state
                        updated.updatedAt = s.updatedAt > existing.updatedAt ? s.updatedAt : now
                        if s.state.isTerminal {
                            updated.completedAt = updated.updatedAt
                        } else {
                            updated.completedAt = nil
                            updated.errorDescription = nil
                        }
                        if updated.workspace == nil { updated.workspace = s.workspace }
                        if updated.originContext == nil { updated.originContext = s.originContext }
                        if let err = s.errorDescription { updated.errorDescription = err }

                        // Merge conversation metadata without clobbering existing valid titles
                        if let title = s.conversationTitle, !title.isEmpty { updated.conversationTitle = title }
                        if let summary = s.taskSummary, !summary.isEmpty { updated.taskSummary = summary }
                        if let url = s.conversationURL { updated.conversationURL = url }
                        if let cId = s.conversationID { updated.conversationID = cId }
                        if let eId = s.executionID { updated.executionID = eId }
                        if let pId = s.parentSessionID { updated.parentSessionID = pId }
                        if s.focusCapability != .windowOnly { updated.focusCapability = s.focusCapability }
                        if s.isRemote { updated.isRemote = true }

                        sessions[s.id] = updated

                        await timeline.record(
                            sessionID: s.id,
                            category: "Discovery",
                            summary: isReactivating
                                ? "Discovered session reactivation: \(existing.state.rawValue) -> \(s.state.rawValue)"
                                : "Discovered state transition: \(existing.state.rawValue) -> \(s.state.rawValue)",
                            details: updated.displayTitle
                        )

                        if let storage = storageDelegate {
                            try? await storage.saveSession(updated)
                        }

                        let event = AgentEvent(
                            timestamp: updated.updatedAt,
                            providerID: s.providerID,
                            sessionID: s.id,
                            type: eventType,
                            workspace: updated.workspace,
                            origin: updated.originContext,
                            metadata: s.metadata,
                            conversationID: updated.conversationID,
                            conversationTitle: updated.conversationTitle,
                            taskSummary: updated.taskSummary,
                            executionID: updated.executionID,
                            parentSessionID: updated.parentSessionID,
                            conversationURL: updated.conversationURL,
                            focusCapability: updated.focusCapability,
                            isRemote: updated.isRemote
                        )
                        generatedEvents.append(event)

                        if let bus = eventBus {
                            await bus.publish(agentEvent: event)
                        }
                    } else {
                        logger.warning("Ignoring invalid discovered state transition from \(existing.state.rawValue) to \(s.state.rawValue) for session \(s.id)")
                    }
                } else {
                    // State unchanged: enrich missing context/workspace/title if available without duplicate notifications
                    var updated = existing
                    var didEnrich = false
                    if updated.workspace == nil, let ws = s.workspace {
                        updated.workspace = ws
                        didEnrich = true
                    }
                    if updated.originContext == nil, let origin = s.originContext {
                        updated.originContext = origin
                        didEnrich = true
                    }
                    if (updated.conversationTitle == nil || updated.conversationTitle!.isEmpty),
                       let title = s.conversationTitle, !title.isEmpty {
                        updated.conversationTitle = title
                        didEnrich = true
                    }
                    if (updated.taskSummary == nil || updated.taskSummary!.isEmpty),
                       let summary = s.taskSummary, !summary.isEmpty {
                        updated.taskSummary = summary
                        didEnrich = true
                    }
                    if updated.conversationURL == nil, let url = s.conversationURL {
                        updated.conversationURL = url
                        didEnrich = true
                    }
                    if updated.conversationID == nil, let cId = s.conversationID {
                        updated.conversationID = cId
                        didEnrich = true
                    }
                    if updated.executionID == nil, let eId = s.executionID {
                        updated.executionID = eId
                        didEnrich = true
                    }
                    if updated.parentSessionID == nil, let pId = s.parentSessionID {
                        updated.parentSessionID = pId
                        didEnrich = true
                    }
                    if s.focusCapability != .windowOnly && updated.focusCapability == .windowOnly {
                        updated.focusCapability = s.focusCapability
                        didEnrich = true
                    }
                    if s.isRemote && !updated.isRemote {
                        updated.isRemote = true
                        didEnrich = true
                    }
                    if didEnrich {
                        sessions[s.id] = updated
                        if let storage = storageDelegate {
                            try? await storage.saveSession(updated)
                        }
                    }
                }
            } else {
                // New session discovered directly from provider
                sessions[s.id] = s
                await timeline.record(
                    sessionID: s.id,
                    category: "Discovery",
                    summary: "Active session discovered: \(s.displayTitle) (\(s.providerDisplayName))",
                    details: s.workspace ?? "Unknown workspace"
                )
                if let storage = storageDelegate {
                    try? await storage.saveSession(s)
                }

                // If it is newly discovered and active, emit an event
                if s.state.isActive {
                    let event = AgentEvent(
                        timestamp: s.startedAt,
                        providerID: s.providerID,
                        sessionID: s.id,
                        type: (s.state == .starting) ? .agentStarted : (s.state == .waiting ? .agentWaiting : .agentRunning),
                        workspace: s.workspace,
                        origin: s.originContext,
                        metadata: s.metadata,
                        conversationID: s.conversationID,
                        conversationTitle: s.conversationTitle,
                        taskSummary: s.taskSummary,
                        executionID: s.executionID,
                        parentSessionID: s.parentSessionID,
                        conversationURL: s.conversationURL,
                        focusCapability: s.focusCapability,
                        isRemote: s.isRemote
                    )
                    generatedEvents.append(event)
                    if let bus = eventBus {
                        await bus.publish(agentEvent: event)
                    }
                }
            }
        }

        return generatedEvents
    }

    // MARK: - Event Ingestion & State Transitions

    public func handleEvent(_ event: AgentEvent) async -> AgentSession {
        // Look up in memory, and if missing, check storageDelegate to resurrect evicted or cold session
        var existing = sessions[event.sessionID]
        if existing == nil, let delegate = storageDelegate {
            do {
                if let stored = try await delegate.fetchSession(id: event.sessionID) {
                    if let inFlightCurrent = sessions[event.sessionID] {
                        existing = inFlightCurrent
                    } else {
                        sessions[event.sessionID] = stored
                        existing = stored
                    }
                }
            } catch {
                logger.error("Failed to resurrect session \(event.sessionID.rawValue) from storage: \(error.localizedDescription)")
            }
        }

        // Stale & Out-of-order protection: reject events older than current session update
        // Exempt reactivating a terminal session with a live active event (e.g. user submitted new prompt in multi-turn conversation)
        let isReactivating = (existing?.state.isTerminal == true) && (event.type.mappedState?.isActive == true)
        if !isReactivating, let current = existing, event.timestamp < current.updatedAt.addingTimeInterval(-2.0) {
            let staleMsg = "Dropped stale/out-of-order event \(event.type.rawValue) for session " +
                "\(event.sessionID.rawValue): timestamp is older than last update"
            logger.warning("\(staleMsg)")
            await timeline.record(
                sessionID: current.id,
                category: "Order",
                summary: "Dropped stale event: \(event.type.rawValue)",
                details: "Event timestamp \(event.timestamp) is older than session updated at \(current.updatedAt)"
            )
            return current
        }

        var session: AgentSession
        if var current = existing {
            // Enrich with origin/workspace if current lacked it but event has it
            if current.originContext == nil, let origin = event.origin {
                current.originContext = origin
            }
            if current.workspace == nil, let ws = event.workspace {
                current.workspace = ws
            }
            if current.conversationID == nil, let cId = event.conversationID {
                current.conversationID = cId
            }
            if current.conversationURL == nil, let url = event.conversationURL {
                current.conversationURL = url
            }
            if current.focusCapability == .windowOnly, let cap = event.focusCapability, cap != .windowOnly {
                current.focusCapability = cap
            }
            session = current
        } else {
            session = AgentSession(
                id: event.sessionID,
                providerID: event.providerID,
                providerSessionID: event.conversationID ?? event.metadata["conversationId"] ?? event.metadata["sessionId"],
                state: .starting,
                workspace: event.workspace,
                originContext: event.origin,
                startedAt: event.timestamp,
                updatedAt: event.timestamp,
                conversationID: event.conversationID,
                conversationTitle: event.conversationTitle,
                taskSummary: event.taskSummary,
                executionID: event.executionID,
                parentSessionID: event.parentSessionID,
                conversationURL: event.conversationURL,
                focusCapability: event.focusCapability,
                isRemote: event.isRemote
            )
        }

        // Title update event without changing session identity or state
        if event.type == .conversationTitleUpdated {
            if let newTitle = event.conversationTitle, !newTitle.isEmpty {
                session.conversationTitle = newTitle
                session.updatedAt = event.timestamp
                await timeline.record(
                    sessionID: session.id,
                    category: "Title",
                    summary: "Conversation title updated",
                    details: newTitle
                )
                sessions[session.id] = session
                if let storage = storageDelegate {
                    try? await storage.saveSession(session)
                }
            }
            return session
        }

        // Update conversation metadata if provided
        if let title = event.conversationTitle, !title.isEmpty {
            if session.conversationTitle != title {
                session.conversationTitle = title
                await timeline.record(
                    sessionID: session.id,
                    category: "Title",
                    summary: "Conversation title updated",
                    details: title
                )
            }
        }
        if let summary = event.taskSummary, !summary.isEmpty {
            session.taskSummary = summary
        }
        if let cId = event.conversationID, !cId.isEmpty {
            session.conversationID = cId
        }
        if let eId = event.executionID, !eId.isEmpty {
            session.executionID = eId
        }
        if let pId = event.parentSessionID {
            session.parentSessionID = pId
        }
        if let url = event.conversationURL {
            session.conversationURL = url
        }
        if let cap = event.focusCapability {
            session.focusCapability = cap
        }
        if let remote = event.isRemote {
            session.isRemote = remote
        }

        // Update origin if provided and currently missing
        if session.originContext == nil, let origin = event.origin {
            session.originContext = origin
            await timeline.record(
                sessionID: session.id,
                category: "Origin",
                summary: "Origin context captured",
                details: origin.displayLabel
            )
        }

        // Update workspace if provided
        if let ws = event.workspace, !ws.isEmpty {
            session.workspace = ws
        }

        // Target state mapping
        if let targetState = event.type.mappedState {
            if session.state.isTerminal && targetState.isActive {
                // Multi-turn prompt resumption / reactivation from terminal state
                let oldState = session.state
                session.state = targetState
                session.completedAt = nil
                session.errorDescription = event.metadata["error"]
                session.updatedAt = event.timestamp

                await timeline.record(
                    sessionID: session.id,
                    category: "State",
                    summary: "Session reactivated: \(oldState.rawValue) -> \(targetState.rawValue)",
                    details: event.type.rawValue
                )
            } else {
                do {
                    let newState = try stateMachine.transition(from: session.state, to: targetState)
                    let oldState = session.state
                    session.state = newState
                    session.updatedAt = event.timestamp

                    if newState.isTerminal {
                        session.completedAt = event.timestamp
                    }

                    if let err = event.metadata["error"], !err.isEmpty {
                        session.errorDescription = err
                    }

                    await timeline.record(
                        sessionID: session.id,
                        category: "State",
                        summary: "State changed: \(oldState.rawValue) -> \(newState.rawValue)",
                        details: event.type.rawValue
                    )

                } catch {
                    logger.warning("State transition failed for session \(session.id): \(error.localizedDescription)")
                }
            }
        }

        // Record event in timeline
        await timeline.record(
            sessionID: session.id,
            category: "Event",
            summary: "Received \(event.type.rawValue)",
            details: event.metadata.description
        )

        sessions[session.id] = session
        enforceRetentionPolicy()

        if let storage = storageDelegate {
            do {
                try await storage.saveSession(session)
            } catch {
                logger.error("Failed to persist session \(session.id): \(error.localizedDescription)")
            }
        }

        return session
    }

    // MARK: - Startup & Recovery

    public func restorePersistedSessions(_ persistedSessions: [AgentSession]) {
        for s in persistedSessions {
            sessions[s.id] = s
        }
    }

    /// Reconciles sessions after crash or app launch, marking abandoned sessions
    public func reconcileOrphanedSessions() async {
        let now = Date()
        for (id, mutSession) in sessions {
            var session = mutSession
            // Remote cloud agents run on external infrastructure independently of the local Mac.
            // They must not be marked cancelled on local restart or wake; their state is reconciled via provider discovery.
            if session.providerID == .cursorBackground || session.isRemote {
                continue
            }

            if session.state.isActive {
                // If it was left active before app restarted, mark cancelled/interrupted
                session.state = .cancelled
                session.completedAt = now
                session.updatedAt = now
                session.errorDescription = "Interrupted by system restart or application relaunch"
                sessions[id] = session

                await timeline.record(
                    sessionID: id,
                    category: "Recovery",
                    summary: "Local session marked cancelled during startup reconciliation"
                )

                if let storage = storageDelegate {
                    try? await storage.saveSession(session)
                }
            }
        }
    }
}
