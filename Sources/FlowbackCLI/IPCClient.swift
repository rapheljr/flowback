import Foundation
import FlowbackCore

public struct IPCClient: Sendable {
    public let socketPath: String
    
    public init(socketPath: String = ("~/.flowback/flowback.sock" as NSString).expandingTildeInPath) {
        self.socketPath = socketPath
    }
    
    public func send(command: String, argument: String? = nil, payload: Data? = nil) throws -> (success: Bool, message: String, data: Data?) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress, buf.count)
            }
        }
        
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                connect(fd, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard connectResult == 0 else {
            let err = errno
            throw POSIXError(.init(rawValue: err) ?? .ECONNREFUSED)
        }
        
        // Encode and send IPCRequest
        let req = IPCRequestDTO(command: command, argument: argument, payload: payload)
        let reqData = try JSONEncoder().encode(req)
        
        _ = reqData.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, reqData.count)
        }
        
        // Read response
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else {
            return (false, "No response from Flowback daemon", nil)
        }
        
        let respData = Data(buffer[0..<bytesRead])
        let resp = try JSONDecoder().decode(IPCResponseDTO.self, from: respData)
        return (resp.success, resp.message, resp.data)
    }
}

private struct IPCRequestDTO: Codable {
    let command: String
    let argument: String?
    let payload: Data?
}

private struct IPCResponseDTO: Codable {
    let success: Bool
    let message: String
    let data: Data?
}
