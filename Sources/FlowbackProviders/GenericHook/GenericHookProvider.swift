import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "GenericHookProvider")

public struct GenericOriginPayload: Codable, Sendable {
    public let bundleId: String?
    public let bundleIdentifier: String?
    public let applicationPath: String?
    public let pid: Int32?
    public let processIdentifier: Int32?
    public let windowId: UInt32?
    public let windowIdentifier: UInt32?
    public let windowTitle: String?
    public let workspacePath: String?
    public let workspaceIdentifier: String?
    public let provenance: String?
    public let confidence: Double?
    public let restorationCapability: String?

    public func toOriginContext(fallbackWorkspace: String?) -> OriginContext? {
        guard let resolvedBundle = bundleIdentifier ?? bundleId, !resolvedBundle.isEmpty else {
            return nil
        }
        let resolvedPID = processIdentifier ?? pid ?? 0
        let resolvedWinID = windowIdentifier ?? windowId
        let resolvedProv = provenance.flatMap { ContextProvenance(rawValue: $0) } ?? .ipcExplicit
        let resolvedCap = restorationCapability.flatMap { RestorationCapability(rawValue: $0) } ?? .exactWindowAndWorkspace
        return OriginContext(
            bundleIdentifier: resolvedBundle,
            applicationPath: applicationPath,
            processIdentifier: resolvedPID,
            windowIdentifier: resolvedWinID,
            windowTitle: windowTitle,
            workspacePath: workspacePath ?? fallbackWorkspace,
            workspaceIdentifier: workspaceIdentifier,
            provenance: resolvedProv,
            confidence: confidence ?? 1.0,
            restorationCapability: resolvedCap
        )
    }
}

public struct GenericHookPayload: Codable, Sendable {
    public let schemaVersion: Int
    public let event: String
    public let provider: String
    public let sessionId: String
    public let taskId: String?
    public let workspace: String?
    public let timestamp: String?
    public let origin: GenericOriginPayload?
    public let conversationId: String?
    public let title: String?
    public let taskSummary: String?
    public let executionId: String?
    public let parentSessionId: String?
    public let conversationUrl: String?
    public let focusCapability: String?
    public let metadata: [String: String]?
    
    public init(
        schemaVersion: Int = 1,
        event: String,
        provider: String,
        sessionId: String,
        taskId: String? = nil,
        workspace: String? = nil,
        timestamp: String? = nil,
        origin: GenericOriginPayload? = nil,
        conversationId: String? = nil,
        title: String? = nil,
        taskSummary: String? = nil,
        executionId: String? = nil,
        parentSessionId: String? = nil,
        conversationUrl: String? = nil,
        focusCapability: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.provider = provider
        self.sessionId = sessionId
        self.taskId = taskId
        self.workspace = workspace
        self.timestamp = timestamp
        self.origin = origin
        self.conversationId = conversationId
        self.title = title
        self.taskSummary = taskSummary
        self.executionId = executionId
        self.parentSessionId = parentSessionId
        self.conversationUrl = conversationUrl
        self.focusCapability = focusCapability
        self.metadata = metadata
    }
}

public final class GenericHookProvider: AgentProvider, Sendable {
    public let providerID = AgentProviderID.genericHook
    public let displayName = "Generic Hook Receiver"
    public let isSupported = true
    public let supportLevel = ProviderSupportLevel.genericProtocol
    
    public init() {}
    
    public func checkHealth() async -> ProviderHealth {
        ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: true,
            hookInstalled: true,
            hookExecutable: true,
            statusMessage: "Universal JSON hook endpoint ready on Unix socket",
            isSupported: true,
            supportLevel: .genericProtocol
        )
    }
    
    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(GenericHookPayload.self, from: data) else {
            logger.warning("Malformed generic hook payload rejected")
            return nil
        }
        
        guard payload.schemaVersion == 1 else {
            logger.warning("Unsupported generic hook schema version \(payload.schemaVersion)")
            return nil
        }
        
        let provID = AgentProviderID(payload.provider)
        let sessID = AgentSessionID(payload.sessionId)
        let eventType = AgentEventType(rawValue: payload.event) ?? .agentCompleted
        
        let convID = payload.conversationId ?? payload.sessionId
        let convTitle = payload.title ?? payload.metadata?["title"] ?? payload.metadata?["prompt"]
        let taskSummary = payload.taskSummary ?? payload.metadata?["taskSummary"]
        let execID = payload.executionId ?? payload.taskId
        let parentID = payload.parentSessionId
        let convURL = payload.conversationUrl
        let focusCap = payload.focusCapability.flatMap { ConversationFocusCapability(rawValue: $0) } ?? .windowOnly
        let resolvedOrigin = payload.origin?.toOriginContext(fallbackWorkspace: payload.workspace)

        let parsedDate: Date
        if let ts = payload.timestamp {
            let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoStandard = ISO8601DateFormatter()
            parsedDate = isoFractional.date(from: ts) ?? isoStandard.date(from: ts) ?? Date()
        } else {
            parsedDate = Date()
        }

        return AgentEvent(
            timestamp: parsedDate,
            providerID: provID,
            sessionID: sessID,
            type: eventType,
            workspace: payload.workspace,
            origin: resolvedOrigin,
            metadata: payload.metadata ?? [:],
            conversationID: convID,
            conversationTitle: convTitle,
            taskSummary: taskSummary,
            executionID: execID,
            parentSessionID: parentID.map { AgentSessionID($0) },
            conversationURL: convURL.flatMap { URL(string: $0) },
            focusCapability: focusCap,
            isRemote: false
        )
    }
    
    public func installIntegration() async throws {}
    public func uninstallIntegration() async throws {}
}
