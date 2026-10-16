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
    
    /// Maximum allowed IPC payload size (2 megabytes) to prevent unbounded memory growth / DoS
    public static let maxPayloadSize = 2 * 1024 * 1024
    
    public init(
        socketPath: String = ("~/.flowback/flowback.sock" as NSString).expandingTildeInPath,
        delegate: IPCHandlerDelegate? = nil
    ) {
        self.socketPath = socketPath
        self.delegate = delegate
        signal(SIGPIPE, SIG_IGN)
    }
    
    public func setDelegate(_ delegate: IPCHandlerDelegate) {
        self.delegate = delegate
    }
    
    /// Checks whether an existing Flowback daemon is actively listening on a socket path
    public static func isDaemonListening(
        socketPath: String = ("~/.flowback/flowback.sock" as NSString).expandingTildeInPath
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        
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
        return connectResult == 0
    }
    
    public func start() throws {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        
        // Safe socket lifecycle: check if an active daemon is already listening on this socket
        if FileManager.default.fileExists(atPath: socketPath) {
            if Self.isDaemonListening(socketPath: socketPath) {
                logger.error("Another Flowback daemon instance is already active and listening at \(self.socketPath)")
                throw POSIXError(.EADDRINUSE)
            }
            // Socket file exists but no process is listening — clean up stale socket
            logger.info("Removing stale socket file at \(self.socketPath)")
            unlink(socketPath)
        }
        
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
        
        // Restrict socket permissions strictly to current user (0600)
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
        
        // Prevent SIGPIPE on write to broken socket
        var nosigpipe: Int32 = 1
        setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        
        // 1. Peer Authentication / Trust Boundary Check
        var peerUid: uid_t = 0
        var peerGid: gid_t = 0
        if getpeereid(clientFd, &peerUid, &peerGid) == 0 {
            let currentUid = getuid()
            if peerUid != currentUid && currentUid != 0 {
                logger.error("Security alert: connection rejected from unauthorized UID \(peerUid) (current user is \(currentUid))")
                let forbidden = IPCResponse(success: false, message: "Access denied: unauthorized peer UID")
                if let forbiddenData = try? JSONEncoder().encode(forbidden) {
                    forbiddenData.withUnsafeBytes { raw in
                        if let base = raw.baseAddress {
                            _ = write(clientFd, base, forbiddenData.count)
                        }
                    }
                }
                return
            }
        }
        
        // 2. Set socket read/write timeouts (5 seconds)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        // 3. Read request data with strict payload bounds
        var requestData = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        let decoder = JSONDecoder()
        var decodedRequest: IPCRequest?
        
        while true {
            let bytesRead = read(clientFd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            requestData.append(buffer, count: bytesRead)
            
            // Enforce upper limit to avoid memory exhaustion
            if requestData.count > Self.maxPayloadSize {
                logger.warning("Rejecting oversized IPC request (\(requestData.count) bytes > \(Self.maxPayloadSize) bytes)")
                let response = IPCResponse(success: false, message: "Payload exceeds maximum allowed size (2MB)")
                if let responseData = try? JSONEncoder().encode(response) {
                    responseData.withUnsafeBytes { raw in
                        if let base = raw.baseAddress {
                            _ = write(clientFd, base, responseData.count)
                        }
                    }
                }
                return
            }
            
            if let req = try? decoder.decode(IPCRequest.self, from: requestData) {
                decodedRequest = req
                break
            }
        }
        
        if decodedRequest == nil {
            decodedRequest = try? decoder.decode(IPCRequest.self, from: requestData)
        }
        
        // Liveness probe check: client disconnected immediately without sending payload
        guard !requestData.isEmpty else {
            return
        }
        
        // 4. Delegate execution
        let response: IPCResponse
        if let request = decodedRequest, let del = self.delegate {
            response = await del.handleRequest(request)
        } else {
            response = IPCResponse(success: false, message: "Malformed IPC request")
        }
        
        // 5. Write response
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
