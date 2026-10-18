import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "ApplicationAdapter")

/// Protocol that specialized application adapters implement for deep window & workspace restoration
public protocol ApplicationAdapter: Sendable {
    var adapterName: String { get }
    func canHandle(bundleIdentifier: String) -> Bool
    func restoreContext(
        context: OriginContext,
        appController: ApplicationControlling,
        windowController: WindowControlling
    ) async -> Bool
}

/// Thread-safe registry that finds the best adapter for a given application
public final class ApplicationAdapterRegistry: @unchecked Sendable {
    public static let shared = ApplicationAdapterRegistry()
    
    private let lock = NSLock()
    private var specializedAdapters: [ApplicationAdapter] = []
    private var fallbackAdapter: ApplicationAdapter = GenericApplicationAdapter()
    
    public init() {
        registerDefaultAdapters()
    }
    
    public func register(adapter: ApplicationAdapter) {
        lock.withLock {
            if adapter is GenericApplicationAdapter {
                fallbackAdapter = adapter
                return
            }
            // If an adapter with the same name already exists, update it in-place (no duplicate accumulation)
            if let existingIndex = specializedAdapters.firstIndex(where: { $0.adapterName == adapter.adapterName }) {
                specializedAdapters[existingIndex] = adapter
            } else {
                // Preserve FIFO registration order among specialized adapters
                specializedAdapters.append(adapter)
            }
        }
    }
    
    public func findAdapter(for bundleIdentifier: String) -> ApplicationAdapter? {
        let (specialized, fallback) = lock.withLock {
            (specializedAdapters, fallbackAdapter)
        }
        if let match = specialized.first(where: { $0.canHandle(bundleIdentifier: bundleIdentifier) }) {
            return match
        }
        if fallback.canHandle(bundleIdentifier: bundleIdentifier) {
            return fallback
        }
        return nil
    }

    public var allAdapters: [ApplicationAdapter] {
        lock.withLock {
            specializedAdapters + [fallbackAdapter]
        }
    }
    
    private func registerDefaultAdapters() {
        specializedAdapters = [
            WindsurfAdapter(),
            VSCodeAdapter(),
            CursorAdapter(),
            TerminalAdapter(),
            BraveAdapter()
        ]
        fallbackAdapter = GenericApplicationAdapter()
    }
}
