import Foundation

/// Errors that can occur during state machine transitions
public enum StateMachineError: Error, LocalizedError, Equatable {
    case invalidTransition(from: AgentState, to: AgentState)
    case terminalStateLocked(state: AgentState)
    
    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let to):
            return "Cannot transition agent from \(from.rawValue) to \(to.rawValue)"
        case .terminalStateLocked(let state):
            return "Agent session is already in terminal state \(state.rawValue) and cannot be modified"
        }
    }
}

/// Enforces deterministic transitions between normalized agent states
public struct AgentStateMachine: Sendable {
    
    public init() {}
    
    /// Determines whether transition from current state to target state is legally valid
    public func canTransition(from: AgentState, to: AgentState) -> Bool {
        if from == to { return true }
        
        switch from {
        case .unknown:
            return true
            
        case .starting:
            switch to {
            case .running, .waiting, .permissionRequired, .completed, .failed, .cancelled:
                return true
            default:
                return false
            }
            
        case .running:
            switch to {
            case .running, .waiting, .permissionRequired, .paused, .completed, .failed, .cancelled:
                return true
            default:
                return false
            }
            
        case .waiting:
            switch to {
            case .running, .permissionRequired, .paused, .completed, .failed, .cancelled:
                return true
            default:
                return false
            }
            
        case .permissionRequired:
            switch to {
            case .running, .waiting, .paused, .completed, .failed, .cancelled:
                return true
            default:
                return false
            }
            
        case .paused:
            switch to {
            case .running, .waiting, .cancelled, .completed, .failed:
                return true
            default:
                return false
            }
            
        case .completed, .failed, .cancelled:
            // Terminal states are closed
            return false
        }
    }
    
    /// Validates transition and returns the new state, throwing if invalid
    public func transition(from: AgentState, to: AgentState) throws -> AgentState {
        if from == to { return to }
        if from.isTerminal {
            throw StateMachineError.terminalStateLocked(state: from)
        }
        guard canTransition(from: from, to: to) else {
            throw StateMachineError.invalidTransition(from: from, to: to)
        }
        return to
    }
}
