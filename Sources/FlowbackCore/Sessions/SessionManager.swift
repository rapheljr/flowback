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
    
    public init(timeline: TimelineTracker = .shared, storageDelegate: SessionStorageDelegate? = nil) {
        self.timeline = timeline
        self.storageDelegate = storageDelegate
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
    
    public func mergeDiscoveredSessions(_ discovered: [AgentSession]) async {
        let now = Date()
        for s in discovered {
            if let existing = sessions[s.id] {
                // If discovered session is active, ensure our in-memory session reflects active state
                if s.state.isActive && !existing.state.isActive && existing.state != .completed {
                    var updated = existing
                    updated.state = s.state
                    updated.updatedAt = now
                    if updated.workspace == nil { updated.workspace = s.workspace }
                    if updated.originContext == nil { updated.originContext = s.originContext }
                    sessions[s.id] = updated
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
            }
        }
    }
    
    // MARK: - Event Ingestion & State Transitions
    
    public func handleEvent(_ event: AgentEvent) async -> AgentSession {
        // Stale & Out-of-order protection: reject events older than current session update
        if let existing = sessions[event.sessionID], event.timestamp < existing.updatedAt.addingTimeInterval(-2.0) {
            logger.warning("Dropped stale/out-of-order event \(event.type.rawValue) for session \(event.sessionID.rawValue): timestamp is older than last update")
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
                    summary: "Session marked cancelled during startup reconciliation"
                )
                
                if let storage = storageDelegate {
                    try? await storage.saveSession(session)
                }
            }
        }
    }
}
