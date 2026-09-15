import Foundation
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "UnixSocketServer")

public protocol IPCHandlerDelegate: AnyObject, Sendable {
    func handleRequest(_ request: IPCRequest) async -> IPCResponse
}

/// Lightweight Unix Domain Socket server handling CLI and hook IPC connections
public final class UnixSocketServer: @unchecked Sendable {
    public let socketPath: String
    private var serverFd: Int32 = -1
    private var isRunning: Bool = false
    private let queue = DispatchQueue(label: "com.flowback.socketserver", attributes: .concurrent)
    private weak var delegate: IPCHandlerDelegate?
    
    public init(
        socketPath: String = ("~/.flowback/flowback.sock" as NSString).expandingTildeInPath,
        delegate: IPCHandlerDelegate? = nil
    ) {
        self.socketPath = socketPath
        self.delegate = delegate
    }
    
    public func setDelegate(_ delegate: IPCHandlerDelegate) {
        self.delegate = delegate
    }
    
    public func start() throws {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        
        // Remove stale socket if present
        unlink(socketPath)
        
        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(serverFd)
            throw POSIXError(.ENAMETOOLONG)
        }
        
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress, buf.count)
            }
        }
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(serverFd, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult == 0 else {
            let err = errno
            close(serverFd)
            throw POSIXError(.init(rawValue: err) ?? .EIO)
        }
        
        // Restrict socket permissions to user only (0600)
        chmod(socketPath, 0o600)
        
        guard listen(serverFd, 128) == 0 else {
            let err = errno
            close(serverFd)
            throw POSIXError(.init(rawValue: err) ?? .EIO)
        }
        
        isRunning = true
        logger.info("Unix socket server listening at \(self.socketPath)")
        
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }
    
    public func stop() {
        isRunning = false
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        unlink(socketPath)
        logger.info("Unix socket server stopped")
    }
    
    private func acceptLoop() {
        while isRunning && serverFd >= 0 {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else {
                if !isRunning { break }
                continue
            }
            
            Task { [weak self] in
                await self?.handleClient(clientFd)
            }
        }
    }
    
    private func handleClient(_ clientFd: Int32) async {
        defer { close(clientFd) }
        
        // Set receive timeout to prevent hanging connections
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        var requestData = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        let decoder = JSONDecoder()
        var decodedRequest: IPCRequest? = nil
        
        while true {
            let bytesRead = read(clientFd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            requestData.append(buffer, count: bytesRead)
            
            if let req = try? decoder.decode(IPCRequest.self, from: requestData) {
                decodedRequest = req
                break
            }
        }
        
        if decodedRequest == nil {
            decodedRequest = try? decoder.decode(IPCRequest.self, from: requestData)
        }
        
        let response: IPCResponse
        if let request = decodedRequest, let del = self.delegate {
            response = await del.handleRequest(request)
        } else {
            response = IPCResponse(success: false, message: "Malformed IPC request")
        }
        
        if let responseData = try? JSONEncoder().encode(response) {
            responseData.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var totalWritten = 0
                let totalBytes = responseData.count
                while totalWritten < totalBytes {
                    let written = write(clientFd, base + totalWritten, totalBytes - totalWritten)
                    if written <= 0 { break }
                    totalWritten += written
                }
            }
        }
    }
}
