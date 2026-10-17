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
    private var adapters: [ApplicationAdapter] = []
    
    public init() {
        registerDefaultAdapters()
    }
    
    public func register(adapter: ApplicationAdapter) {
        lock.withLock {
            adapters.append(adapter)
        }
    }
    
    public func findAdapter(for bundleIdentifier: String) -> ApplicationAdapter? {
        let snapshot: [ApplicationAdapter] = lock.withLock {
            adapters
        }
        return snapshot.first { $0.canHandle(bundleIdentifier: bundleIdentifier) }
    }
    
    private func registerDefaultAdapters() {
        adapters.append(WindsurfAdapter())
        adapters.append(VSCodeAdapter())
        adapters.append(CursorAdapter())
        adapters.append(TerminalAdapter())
        adapters.append(BraveAdapter())
        adapters.append(GenericApplicationAdapter())
    }
}
