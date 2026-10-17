import Foundation
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "UIEventCoalescer")

/// A manual sleep scheduler allowing deterministic time advancement and cancellation in tests
public final class ManualSleepScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    public init() {}

    public func sleep(seconds: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.lock.lock()
                    if Task.isCancelled {
                        self.lock.unlock()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.continuations[id] = continuation
                    self.lock.unlock()
                }
            },
            onCancel: {
                self.lock.lock()
                let cont = self.continuations.removeValue(forKey: id)
                self.lock.unlock()
                cont?.resume(throwing: CancellationError())
            }
        )
    }

    public func advance() {
        lock.lock()
        let conns = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for c in conns {
            c.resume()
        }
    }

    public func cancelAll() {
        lock.lock()
        let conns = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for c in conns {
            c.resume(throwing: CancellationError())
        }
    }

    public var pendingSleepCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    public func waitUntilSleeping(count: Int = 1) async {
        while pendingSleepCount < count {
            await Task.yield()
        }
    }
}

/// Lifecycle-safe UI event coalescer that bounds UI synchronizations to a single pending refresh per time window
@MainActor
public final class UIEventCoalescer: @unchecked Sendable {
    public typealias Action = @MainActor () async -> Void
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    public let interval: TimeInterval
    private let action: Action
    private let sleeper: Sleeper

    private var pendingTask: Task<Void, Never>?
    private var isExecuting: Bool = false
    private var hasPendingRequest: Bool = false
    private var isStopped: Bool = false

    // Telemetry and testing metrics
    public private(set) var scheduleCount: Int = 0
    public private(set) var executionCount: Int = 0
    public private(set) var coalescedEventCount: Int = 0

    public var isPending: Bool {
        pendingTask != nil || hasPendingRequest
    }

    public var isCurrentlyExecuting: Bool {
        isExecuting
    }

    public init(
        interval: TimeInterval = 0.05,
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        action: @escaping Action
    ) {
        self.interval = interval
        self.sleeper = sleeper
        self.action = action
    }

    /// Schedules a UI refresh. If a refresh is already pending or executing, coalesces the event into the pending pass.
    public func schedule() {
        guard !isStopped else { return }
        scheduleCount += 1

        if isExecuting {
            // Action is currently running; mark dirty so it re-runs after finishing
            hasPendingRequest = true
            coalescedEventCount += 1
            return
        }

        if pendingTask != nil {
            // A timer is already counting down; coalesce this event into that window
            hasPendingRequest = true
            coalescedEventCount += 1
            return
        }

        // Neither executing nor pending timer; start single countdown
        hasPendingRequest = true
        startPendingTimer()
    }

    private func startPendingTimer() {
        guard !isStopped, pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await self.sleeper(self.interval)
            } catch {
                // Sleep was cancelled or failed; exit cleanly without action
                return
            }
            guard !Task.isCancelled, !self.isStopped else { return }
            await self.execute()
        }
    }

    private func execute() async {
        guard !isStopped else { return }
        pendingTask?.cancel()
        pendingTask = nil
        hasPendingRequest = false
        isExecuting = true
        executionCount += 1
        defer { isExecuting = false }

        await action()

        // Check if events arrived while action was executing
        if hasPendingRequest && !isStopped {
            startPendingTimer()
        }
    }

    /// Flushes any pending scheduled refresh immediately without waiting for the timer, and awaits any active in-flight execution
    public func flush() async {
        guard !isStopped else { return }
        if let task = pendingTask {
            task.cancel()
            pendingTask = nil
            hasPendingRequest = true
        }
        while (hasPendingRequest || isExecuting) && !isStopped {
            if !isExecuting {
                await execute()
            } else {
                await Task.yield()
            }
        }
    }

    /// Stops the coalescer, cancelling any pending task and ignoring future schedules
    public func stop() {
        isStopped = true
        hasPendingRequest = false
        pendingTask?.cancel()
        pendingTask = nil
    }

    /// Resets the coalescer back to clean starting state
    public func reset() {
        stop()
        isStopped = false
        hasPendingRequest = false
        isExecuting = false
        scheduleCount = 0
        executionCount = 0
        coalescedEventCount = 0
    }
}
