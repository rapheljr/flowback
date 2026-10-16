import Foundation
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "LifecycleCoordinator")

/// Explicit lifecycle states governing Flowback service execution
public enum ServiceLifecycleState: String, Codable, Sendable, CaseIterable {
    case notStarted = "not_started"
    case starting = "starting"
    case ready = "ready"
    case degraded = "degraded"
    case stopping = "stopping"
    case stopped = "stopped"
    case startupFailure = "startup_failure"
    
    public var isOperational: Bool {
        self == .ready || self == .degraded
    }
    
    public var isTerminal: Bool {
        self == .stopped || self == .startupFailure
    }
}

/// Errors occurring during service lifecycle transitions
public enum LifecycleError: Error, LocalizedError, Sendable {
    case invalidTransition(from: ServiceLifecycleState, to: ServiceLifecycleState)
    case componentStartupFailed(component: String, reason: String)
    case serviceAlreadyStopping
    case serviceAlreadyRunning
    
    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let to):
            return "Invalid lifecycle transition from \(from.rawValue) to \(to.rawValue)"
        case .componentStartupFailed(let component, let reason):
            return "Startup failure in \(component): \(reason)"
        case .serviceAlreadyStopping:
            return "Service is currently stopping"
        case .serviceAlreadyRunning:
            return "Service is already starting or ready"
        }
    }
}

/// A component whose lifecycle is coordinated during service start, degradation, and shutdown
public protocol LifecycleManagedComponent: AnyObject, Sendable {
    var componentName: String { get }
    var isCritical: Bool { get }
    func startComponent() async throws
    func stopComponent() async
}

/// Default implementation making non-critical components optional
public extension LifecycleManagedComponent {
    var isCritical: Bool { true }
}

/// Deterministic lifecycle coordinator ensuring safe startup, ordered shutdown, and failure rollback
public actor LifecycleCoordinator {
    public private(set) var currentState: ServiceLifecycleState = .notStarted
    public private(set) var lastError: String?
    public private(set) var startInvocationCount: Int = 0
    public private(set) var stopInvocationCount: Int = 0
    private var startedComponents: [LifecycleManagedComponent] = []
    
    public init(initialState: ServiceLifecycleState = .notStarted) {
        self.currentState = initialState
    }
    
    /// Evaluates valid lifecycle state transitions
    public func canTransition(from: ServiceLifecycleState, to: ServiceLifecycleState) -> Bool {
        if from == to { return true }
        switch from {
        case .notStarted:
            return to == .starting
        case .starting:
            return to == .ready || to == .degraded || to == .startupFailure || to == .stopping || to == .stopped
        case .ready:
            return to == .degraded || to == .stopping || to == .stopped
        case .degraded:
            return to == .ready || to == .stopping || to == .stopped
        case .stopping:
            return to == .stopped
        case .stopped:
            return to == .starting
        case .startupFailure:
            return to == .starting || to == .stopped
        }
    }
    
    /// Transitions to a new lifecycle state if allowed by the state machine
    public func transition(to newState: ServiceLifecycleState) throws {
        guard canTransition(from: currentState, to: newState) else {
            logger.error("Rejecting illegal lifecycle transition from \(self.currentState.rawValue) to \(newState.rawValue)")
            throw LifecycleError.invalidTransition(from: currentState, to: newState)
        }
        logger.info("Lifecycle state transition: \(self.currentState.rawValue) -> \(newState.rawValue)")
        self.currentState = newState
    }
    
    /// Coordinates deterministic startup of components in order with automatic rollback on failure
    @discardableResult
    public func start(components: [LifecycleManagedComponent]) async -> ServiceLifecycleState {
        startInvocationCount += 1
        
        // Guard against duplicate start requests while running or starting
        if currentState == .starting || currentState == .ready {
            logger.warning("Lifecycle start() ignored: service is already \(self.currentState.rawValue)")
            return currentState
        }
        
        do {
            try transition(to: .starting)
        } catch {
            return currentState
        }
        
        lastError = nil
        startedComponents.removeAll()
        var hasDegradedComponent = false
        
        for component in components {
            do {
                logger.info("Starting lifecycle component: \(component.componentName)...")
                try await component.startComponent()
                startedComponents.append(component)
            } catch {
                let errorMsg = "\(component.componentName) failed: \(error.localizedDescription)"
                logger.error("\(errorMsg)")
                lastError = errorMsg
                
                if component.isCritical {
                    logger.fault("Critical component failed. Initiating startup rollback...")
                    await rollbackStartedComponents()
                    try? transition(to: .startupFailure)
                    return .startupFailure
                } else {
                    logger.warning("Optional component failed; service running degraded.")
                    hasDegradedComponent = true
                }
            }
        }
        
        let targetState: ServiceLifecycleState = hasDegradedComponent ? .degraded : .ready
        try? transition(to: targetState)
        return targetState
    }
    
    /// Idempotent single shutdown path: shuts down all registered components in reverse order
    public func stop(additionalTeardown: (@Sendable () async -> Void)? = nil) async {
        stopInvocationCount += 1
        
        // Idempotency: skip if already stopping or stopped
        if currentState == .stopping || currentState == .stopped {
            logger.info("Lifecycle stop() ignored: service is already \(self.currentState.rawValue)")
            return
        }
        
        try? transition(to: .stopping)
        logger.info("Authoritative shutdown sequence beginning...")
        
        if let customTeardown = additionalTeardown {
            await customTeardown()
        }
        
        // Teardown in reverse registration order (LIFO)
        for component in startedComponents.reversed() {
            logger.info("Stopping lifecycle component: \(component.componentName)...")
            await component.stopComponent()
        }
        startedComponents.removeAll()
        
        try? transition(to: .stopped)
        logger.info("Authoritative shutdown sequence complete.")
    }
    
    private func rollbackStartedComponents() async {
        for component in startedComponents.reversed() {
            logger.info("Rolling back component: \(component.componentName)...")
            await component.stopComponent()
        }
        startedComponents.removeAll()
    }
}
