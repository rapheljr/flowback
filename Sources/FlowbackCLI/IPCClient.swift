import Foundation
import FlowbackCore

public struct IPCClientResult: Sendable {
    public let success: Bool
    public let message: String
    public let data: Data?
    
    public init(success: Bool, message: String, data: Data? = nil) {
        self.success = success
        self.message = message
        self.data = data
    }
}

public struct IPCClient: Sendable {
    public let socketPath: String
    
    public init(socketPath: String = ("~/.flowback/flowback.sock" as NSString).expandingTildeInPath) {
        self.socketPath = socketPath
    }
    
    public func send(command: String, argument: String? = nil, payload: Data? = nil) throws -> IPCClientResult {
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
        
        reqData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var totalWritten = 0
            let totalBytes = reqData.count
            while totalWritten < totalBytes {
                let written = write(fd, base + totalWritten, totalBytes - totalWritten)
                if written <= 0 { break }
                totalWritten += written
            }
        }
        
        // Read response
        var respData = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        let decoder = JSONDecoder()
        var decodedResponse: IPCResponseDTO?
        
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            respData.append(buffer, count: bytesRead)
            
            if let resp = try? decoder.decode(IPCResponseDTO.self, from: respData) {
                decodedResponse = resp
                break
            }
        }
        
        if decodedResponse == nil {
            decodedResponse = try? decoder.decode(IPCResponseDTO.self, from: respData)
        }
        
        guard let resp = decodedResponse else {
            return IPCClientResult(success: false, message: "No valid response from Flowback daemon", data: nil)
        }
        return IPCClientResult(success: resp.success, message: resp.message, data: resp.data)
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
