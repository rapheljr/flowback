import Foundation
import FlowbackCore

/// Payload received from any Antigravity lifecycle hook (PreInvocation, PostInvocation, Stop, PreToolUse)
public struct AntigravityHookPayload: Codable, Sendable {
    public let hook_event_name: String?
    public let conversationId: String
    public let workspacePaths: [String]?
    public let transcriptPath: String?
    public let artifactDirectoryPath: String?
    public let modelName: String?
    public let executionNum: Int?
    public let invocationNum: Int?
    public let initialNumSteps: Int?
    public let stepIdx: Int?
    public let terminationReason: String?
    public let error: String?
    public let fullyIdle: Bool?
    
    public init(
        hook_event_name: String? = nil,
        conversationId: String,
        workspacePaths: [String]? = nil,
        transcriptPath: String? = nil,
        artifactDirectoryPath: String? = nil,
        modelName: String? = nil,
        executionNum: Int? = nil,
        invocationNum: Int? = nil,
        initialNumSteps: Int? = nil,
        stepIdx: Int? = nil,
        terminationReason: String? = nil,
        error: String? = nil,
        fullyIdle: Bool? = nil
    ) {
        self.hook_event_name = hook_event_name
        self.conversationId = conversationId
        self.workspacePaths = workspacePaths
        self.transcriptPath = transcriptPath
        self.artifactDirectoryPath = artifactDirectoryPath
        self.modelName = modelName
        self.executionNum = executionNum
        self.invocationNum = invocationNum
        self.initialNumSteps = initialNumSteps
        self.stepIdx = stepIdx
        self.terminationReason = terminationReason
        self.error = error
        self.fullyIdle = fullyIdle
    }
}

/// Backward compatibility typealias for stop payload
public typealias AntigravityStopPayload = AntigravityHookPayload

/// Standard response output to Antigravity hook stdout
public struct AntigravityHookResponse: Codable, Sendable {
    public let decision: String?
    public let reason: String?
    public let injectSteps: [String]?
    
    public init(decision: String? = "allow", reason: String? = nil, injectSteps: [String]? = nil) {
        self.decision = decision
        self.reason = reason
        self.injectSteps = injectSteps
    }
}
