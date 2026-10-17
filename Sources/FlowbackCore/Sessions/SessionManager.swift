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
    private var sessions: [AgentSessionID: AgentSession] = [:]
    private let stateMachine = AgentStateMachine()
    private let timeline: TimelineTracker
    private weak var storageDelegate: SessionStorageDelegate?
    private let eventBus: EventBus?

    public init(
        timeline: TimelineTracker = .shared,
        storageDelegate: SessionStorageDelegate? = nil,
        eventBus: EventBus? = nil
    ) {
        self.timeline = timeline
        self.storageDelegate = storageDelegate
        self.eventBus = eventBus
    }

    public func setStorageDelegate(_ delegate: SessionStorageDelegate) {
        self.storageDelegate = delegate
    }

    // MARK: - Session Retrieval

    public func getSession(id: AgentSessionID) -> AgentSession? {
        sessions[id]
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
                        sessions[s.id] = updated

                        await timeline.record(
                            sessionID: s.id,
                            category: "Discovery",
                            summary: isReactivating
                                ? "Discovered session reactivation: \(existing.state.rawValue) -> \(s.state.rawValue)"
                                : "Discovered state transition: \(existing.state.rawValue) -> \(s.state.rawValue)",
                            details: s.projectName
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
                            metadata: s.metadata
                        )
                        generatedEvents.append(event)

                        if let bus = eventBus {
                            await bus.publish(agentEvent: event)
                        }
                    } else {
                        logger.warning("Ignoring invalid discovered state transition from \(existing.state.rawValue) to \(s.state.rawValue) for session \(s.id)")
                    }
                } else {
                    // State unchanged: enrich missing context/workspace if available without duplicate notifications
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
                    if didEnrich {
                        sessions[s.id] = updated
                    }
                }
            } else {
                // New session discovered directly from provider
                sessions[s.id] = s
                await timeline.record(
                    sessionID: s.id,
                    category: "Discovery",
                    summary: "Active session discovered: \(s.projectName) (\(s.providerID.rawValue))",
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
                        metadata: s.metadata
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
        // Stale & Out-of-order protection: reject events older than current session update
        // Exempt reactivating a terminal session with a live active event (e.g. user submitted new prompt in multi-turn conversation)
        let isReactivating = (sessions[event.sessionID]?.state.isTerminal == true) && (event.type.mappedState?.isActive == true)
        if !isReactivating, let existing = sessions[event.sessionID], event.timestamp < existing.updatedAt.addingTimeInterval(-2.0) {
            let staleMsg = "Dropped stale/out-of-order event \(event.type.rawValue) for session " +
                "\(event.sessionID.rawValue): timestamp is older than last update"
            logger.warning("\(staleMsg)")
            await timeline.record(
                sessionID: existing.id,
                category: "Order",
                summary: "Dropped stale event: \(event.type.rawValue)",
                details: "Event timestamp \(event.timestamp) is older than session updated at \(existing.updatedAt)"
            )
            return existing
        }

        var session = sessions[event.sessionID] ?? AgentSession(
            id: event.sessionID,
            providerID: event.providerID,
            providerSessionID: event.metadata["conversationId"] ?? event.metadata["sessionId"],
            state: .starting,
            workspace: event.workspace,
            originContext: event.origin,
            startedAt: event.timestamp,
            updatedAt: event.timestamp
        )

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
            if session.providerID == .cursorBackground {
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
