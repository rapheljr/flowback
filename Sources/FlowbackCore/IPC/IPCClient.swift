import Foundation
#if canImport(Darwin)
import Darwin
#endif

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
    public let timeoutSeconds: TimeInterval

    public init(
        socketPath: String = ("~/.flowback/flowback.sock" as NSString).expandingTildeInPath,
        timeoutSeconds: TimeInterval = 10.0
    ) {
        self.socketPath = socketPath
        self.timeoutSeconds = timeoutSeconds
    }

    public func send(command: String, argument: String? = nil, payload: Data? = nil, authToken: String? = nil) throws -> IPCClientResult {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(
            tv_sec: Int(timeoutSeconds),
            tv_usec: Int32((timeoutSeconds.truncatingRemainder(dividingBy: 1.0)) * 1_000_000)
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

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

        // Auto-load local session auth token if not explicitly provided
        let effectiveToken = authToken ?? {
            let dir = (socketPath as NSString).deletingLastPathComponent
            let isSystemSharedDir = (dir == "/tmp" || dir == "/private/tmp" || dir == "/var/tmp" || dir.isEmpty || dir == "/")
            let tokenPath = isSystemSharedDir ? (socketPath + ".token") : (dir + "/.session_token")
            return try? String(contentsOfFile: tokenPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        // Encode and send IPCRequest
        let req = IPCRequest(command: command, argument: argument, payload: payload, authToken: effectiveToken)
        let reqData = try JSONEncoder().encode(req)

        try reqData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var totalWritten = 0
            let totalBytes = reqData.count
            while totalWritten < totalBytes {
                let written = write(fd, base + totalWritten, totalBytes - totalWritten)
                if written < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    throw POSIXError(.init(rawValue: err) ?? .EIO)
                } else if written == 0 {
                    throw POSIXError(.EPIPE)
                }
                totalWritten += written
            }
        }

        // Read response
        var respData = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        let decoder = JSONDecoder()
        var decodedResponse: IPCResponse?

        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 {
                if bytesRead < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    if err == EAGAIN || err == EWOULDBLOCK || err == ETIMEDOUT {
                        return IPCClientResult(success: false, message: "Request timed out waiting for Flowback daemon", data: nil)
                    }
                    throw POSIXError(.init(rawValue: err) ?? .EIO)
                }
                break
            }
            respData.append(buffer, count: bytesRead)

            if let resp = try? decoder.decode(IPCResponse.self, from: respData) {
                decodedResponse = resp
                break
            }
        }

        if decodedResponse == nil {
            decodedResponse = try? decoder.decode(IPCResponse.self, from: respData)
        }

        guard let resp = decodedResponse else {
            return IPCClientResult(success: false, message: "No valid response from Flowback daemon", data: nil)
        }
        return IPCClientResult(success: resp.success, message: resp.message, data: resp.data)
    }
}
