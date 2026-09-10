import Foundation
import FlowbackCore

/// Payload received from Antigravity Stop hook
public struct AntigravityStopPayload: Codable, Sendable {
    public let conversationId: String
    public let workspacePaths: [String]?
    public let transcriptPath: String?
    public let artifactDirectoryPath: String?
    public let modelName: String?
    public let executionNum: Int?
    public let terminationReason: String?
    public let error: String?
    public let fullyIdle: Bool?
    
    public init(
        conversationId: String,
        workspacePaths: [String]? = nil,
        transcriptPath: String? = nil,
        artifactDirectoryPath: String? = nil,
        modelName: String? = nil,
        executionNum: Int? = nil,
        terminationReason: String? = nil,
        error: String? = nil,
        fullyIdle: Bool? = nil
    ) {
        self.conversationId = conversationId
        self.workspacePaths = workspacePaths
        self.transcriptPath = transcriptPath
        self.artifactDirectoryPath = artifactDirectoryPath
        self.modelName = modelName
        self.executionNum = executionNum
        self.terminationReason = terminationReason
        self.error = error
        self.fullyIdle = fullyIdle
    }
}

/// Standard response output to Antigravity hook stdout
public struct AntigravityHookResponse: Codable, Sendable {
    public let decision: String
    public let reason: String?
    
    public init(decision: String = "allow", reason: String? = nil) {
        self.decision = decision
        self.reason = reason
    }
}
