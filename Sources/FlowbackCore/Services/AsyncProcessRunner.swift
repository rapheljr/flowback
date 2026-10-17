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

/// Asynchronous, non-blocking process execution bridge with timeout and cancellation support
public struct AsyncProcessRunner: Sendable {
    public static func run(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval = 2.0
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
            let lock = NSLock()
            var continuation: CheckedContinuation<ProcessExecutionResult, Error>?
            var isTerminated = false
            let process: Process
            
            init(process: Process) {
                self.process = process
            }
            
            func setContinuation(_ cont: CheckedContinuation<ProcessExecutionResult, Error>) {
                lock.lock()
                defer { lock.unlock() }
                self.continuation = cont
            }
            
            func resume(with result: Result<ProcessExecutionResult, Error>) {
                lock.lock()
                let cont = continuation
                continuation = nil
                lock.unlock()
                cont?.resume(with: result)
            }
            
            func cancel() {
                lock.lock()
                let cont = continuation
                continuation = nil
                if !isTerminated && process.isRunning {
                    isTerminated = true
                    process.terminate()
                }
                lock.unlock()
                cont?.resume(throwing: ProcessExecutionError.cancelled)
            }
            
            func terminate() {
                lock.lock()
                defer { lock.unlock() }
                if !isTerminated && process.isRunning {
                    isTerminated = true
                    process.terminate()
                }
            }
        }
        
        let state = ExecutionState(process: process)
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.setContinuation(continuation)
                
                if Task.isCancelled {
                    state.cancel()
                    return
                }
                
                process.terminationHandler = { proc in
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let outStr = String(data: outData, encoding: .utf8) ?? ""
                    let errStr = String(data: errData, encoding: .utf8) ?? ""
                    
                    state.resume(with: .success(ProcessExecutionResult(
                        exitCode: proc.terminationStatus,
                        stdout: outStr,
                        stderr: errStr
                    )))
                }
                
                do {
                    try process.run()
                } catch {
                    state.resume(with: .failure(ProcessExecutionError.launchFailed(error.localizedDescription)))
                    return
                }
                
                // Timeout watchdog
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    state.terminate()
                    state.resume(with: .failure(ProcessExecutionError.timedOut(timeoutSeconds)))
                }
            }
        } onCancel: {
            state.cancel()
        }
    }
}
