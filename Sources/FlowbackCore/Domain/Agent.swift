import Foundation

/// Identifier for an Agent Provider (e.g. "antigravity", "claude-code", "codex")
public struct AgentProviderID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        let normalized = rawValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "gemini-cli" || normalized == "gemini" || normalized == "agy" {
            self.rawValue = "antigravity-cli"
        } else {
            self.rawValue = normalized
        }
    }
    
    private enum CodingKeys: CodingKey {
        case rawValue
    }
    
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let raw = try? container.decode(String.self, forKey: .rawValue) {
            self.init(raw)
            return
        }
        let single = try decoder.singleValueContainer()
        let raw = try single.decode(String.self)
        self.init(raw)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
    
    public var description: String { rawValue }
    
    public static let antigravity = AgentProviderID("antigravity")
    public static let antigravityCLI = AgentProviderID("antigravity-cli")
    public static let geminiCLI = antigravityCLI
    public static let claudeCode = AgentProviderID("claude-code")
    public static let codex = AgentProviderID("codex")
    public static let aider = AgentProviderID("aider")
    public static let openCode = AgentProviderID("opencode")
    public static let windsurf = AgentProviderID("windsurf")
    public static let cursorBackground = AgentProviderID("cursor-background")
    public static let genericHook = AgentProviderID("generic-hook")
    public static let copilot = AgentProviderID("copilot")
}

/// Unique identifier for an agent session
public struct AgentSessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

/// Identifier for a specific task or prompt execution within a session
public struct AgentTaskID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }
}

/// Normalized lifecycle state across all agent providers
public enum AgentState: String, Codable, Sendable, CaseIterable {
    case unknown
    case starting
    case running
    case waiting
    case permissionRequired
    case paused
    case completed
    case failed
    case cancelled
    
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
    
    public var isActive: Bool {
        switch self {
        case .starting, .running, .waiting, .permissionRequired, .paused:
            return true
        default:
            return false
        }
    }
    
    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .starting: return "Starting"
        case .running: return "Running"
        case .waiting: return "Waiting"
        case .permissionRequired: return "Permission Required"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}
