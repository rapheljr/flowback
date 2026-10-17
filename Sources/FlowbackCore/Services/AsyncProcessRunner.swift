import Foundation
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "AsyncProcessRunner")

public struct ProcessExecutionResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    
    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ProcessExecutionError: Error, LocalizedError, Sendable, Equatable {
    case executableNotFound(String)
    case launchFailed(String)
    case timedOut(TimeInterval)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Executable not found at path: \(path)"
        case .launchFailed(let reason):
            return "Failed to launch process: \(reason)"
        case .timedOut(let seconds):
            return "Process execution timed out after \(seconds)s"
        case .cancelled:
            return "Process execution was cancelled"
        }
    }
}

/// Asynchronous, non-blocking process execution bridge with bounded streaming, timeout, and cancellation support
public struct AsyncProcessRunner: Sendable {
    public static func run(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval = 2.0,
        maxOutputBytes: Int = 1_048_576
    ) async throws -> ProcessExecutionResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw ProcessExecutionError.executableNotFound(executablePath)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        final class ExecutionState: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<ProcessExecutionResult, Error>?
            private var watchdogTask: Task<Void, Never>?
            private var isTerminated = false
            private let process: Process
            private let stdoutHandle: FileHandle
            private let stderrHandle: FileHandle
            private let stdoutFd: Int32
            private let stderrFd: Int32
            private let maxBytes: Int
            private var stdoutData = Data()
            private var stderrData = Data()

            init(process: Process, stdoutHandle: FileHandle, stderrHandle: FileHandle, maxBytes: Int) {
                self.process = process
                self.stdoutHandle = stdoutHandle
                self.stderrHandle = stderrHandle
                self.stdoutFd = stdoutHandle.fileDescriptor
                self.stderrFd = stderrHandle.fileDescriptor
                self.maxBytes = maxBytes
            }

            func setContinuation(_ cont: CheckedContinuation<ProcessExecutionResult, Error>) {
                lock.lock()
                defer { lock.unlock() }
                if isTerminated {
                    cont.resume(throwing: ProcessExecutionError.cancelled)
                } else {
                    self.continuation = cont
                }
            }

            func setWatchdogTask(_ task: Task<Void, Never>) {
                lock.lock()
                defer { lock.unlock() }
                self.watchdogTask = task
            }

            func appendStdout(_ chunk: Data) {
                lock.lock()
                defer { lock.unlock() }
                let available = max(0, maxBytes - stdoutData.count)
                if available > 0 {
                    stdoutData.append(chunk.prefix(available))
                }
            }

            func appendStderr(_ chunk: Data) {
                lock.lock()
                defer { lock.unlock() }
                let available = max(0, maxBytes - stderrData.count)
                if available > 0 {
                    stderrData.append(chunk.prefix(available))
                }
            }

            private func cleanupHandlersUnderLock() {
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                try? stdoutHandle.close()
                try? stderrHandle.close()
                watchdogTask?.cancel()
                watchdogTask = nil
            }

            private func drainRemainingUnderLock(fd: Int32, isStdout: Bool) {
                guard fd >= 0 else { return }
                let flags = fcntl(fd, F_GETFL, 0)
                if flags >= 0 {
                    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                }
                var buf = [UInt8](repeating: 0, count: 16384)
                while true {
                    let bytesRead = read(fd, &buf, buf.count)
                    if bytesRead <= 0 { break }
                    let chunk = Data(bytes: buf, count: bytesRead)
                    if isStdout {
                        let available = max(0, maxBytes - stdoutData.count)
                        if available > 0 {
                            stdoutData.append(chunk.prefix(available))
                        }
                    } else {
                        let available = max(0, maxBytes - stderrData.count)
                        if available > 0 {
                            stderrData.append(chunk.prefix(available))
                        }
                    }
                }
            }

            func finish(exitCode: Int32) {
                lock.lock()
                guard !isTerminated else {
                    lock.unlock()
                    return
                }
                isTerminated = true

                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                drainRemainingUnderLock(fd: stdoutFd, isStdout: true)
                drainRemainingUnderLock(fd: stderrFd, isStdout: false)

                cleanupHandlersUnderLock()
                let cont = continuation
                continuation = nil
                let outStr = String(data: stdoutData, encoding: .utf8) ?? ""
                let errStr = String(data: stderrData, encoding: .utf8) ?? ""
                lock.unlock()

                cont?.resume(returning: ProcessExecutionResult(
                    exitCode: exitCode,
                    stdout: outStr,
                    stderr: errStr
                ))
            }

            func resume(throwing error: Error) {
                lock.lock()
                guard !isTerminated else {
                    lock.unlock()
                    return
                }
                isTerminated = true
                cleanupHandlersUnderLock()
                let cont = continuation
                continuation = nil
                lock.unlock()

                cont?.resume(throwing: error)
            }

            func cancel() {
                lock.lock()
                guard !isTerminated else {
                    lock.unlock()
                    return
                }
                isTerminated = true
                cleanupHandlersUnderLock()
                let cont = continuation
                continuation = nil
                if process.isRunning {
                    process.terminate()
                }
                lock.unlock()

                cont?.resume(throwing: ProcessExecutionError.cancelled)
            }

            func terminateForTimeout(seconds: TimeInterval) {
                lock.lock()
                guard !isTerminated else {
                    lock.unlock()
                    return
                }
                isTerminated = true
                cleanupHandlersUnderLock()
                let cont = continuation
                continuation = nil
                if process.isRunning {
                    process.terminate()
                }
                lock.unlock()

                cont?.resume(throwing: ProcessExecutionError.timedOut(seconds))
            }
        }

        let state = ExecutionState(
            process: process,
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading,
            maxBytes: maxOutputBytes
        )
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.setContinuation(continuation)
                
                if Task.isCancelled {
                    state.cancel()
                    return
                }
                
                // Continuous streaming drainage prevents child process from blocking on full pipe buffers
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        state.appendStdout(chunk)
                    }
                }

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        state.appendStderr(chunk)
                    }
                }

                process.terminationHandler = { proc in
                    state.finish(exitCode: proc.terminationStatus)
                }
                
                do {
                    try process.run()
                } catch {
                    state.resume(throwing: ProcessExecutionError.launchFailed(error.localizedDescription))
                    return
                }
                
                // Timeout watchdog: cancelled immediately upon process completion to prevent task leaks
                let watchdog = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    } catch {
                        return
                    }
                    state.terminateForTimeout(seconds: timeoutSeconds)
                }
                state.setWatchdogTask(watchdog)
            }
        } onCancel: {
            state.cancel()
        }
    }
}
