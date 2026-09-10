import Foundation
import FlowbackCore

/// IPC Request structure sent over the Unix domain socket
public struct IPCRequest: Codable, Sendable {
    public let command: String
    public let argument: String?
    public let payload: Data?
    
    public init(command: String, argument: String? = nil, payload: Data? = nil) {
        self.command = command
        self.argument = argument
        self.payload = payload
    }
}

/// IPC Response returned by the Flowback daemon
public struct IPCResponse: Codable, Sendable {
    public let success: Bool
    public let message: String
    public let data: Data?
    
    public init(success: Bool, message: String, data: Data? = nil) {
        self.success = success
        self.message = message
        self.data = data
    }
}
