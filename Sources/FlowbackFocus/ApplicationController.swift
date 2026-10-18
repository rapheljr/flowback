import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "ApplicationController")

public protocol ApplicationControlling: Sendable {
    func frontmostApplication() -> NSRunningApplication?
    func runningApplication(forProcessIdentifier pid: Int32) -> NSRunningApplication?
    func runningApplications(withBundleIdentifier bundleID: String) -> [NSRunningApplication]
    func activate(application: NSRunningApplication) -> Bool
    func activateApplication(_ application: NSRunningApplication) async -> Bool
}

public extension ApplicationControlling {
    func activateApplication(_ application: NSRunningApplication) async -> Bool {
        activate(application: application)
    }
}

/// Manages discovery and activation of macOS applications using NSWorkspace
public final class ApplicationController: ApplicationControlling, @unchecked Sendable {
    public static let shared = ApplicationController()

    public typealias WorkspaceOpener = @Sendable (URL, NSWorkspace.OpenConfiguration) -> Bool
    public typealias AsyncWorkspaceOpener = @Sendable (URL, NSWorkspace.OpenConfiguration) async throws -> Bool
    public typealias DirectActivator = @Sendable (NSRunningApplication) -> Bool
    public typealias BundleURLResolver = @Sendable (NSRunningApplication) -> URL?

    private let workspaceOpener: WorkspaceOpener?
    private let asyncWorkspaceOpener: AsyncWorkspaceOpener?
    private let directActivator: DirectActivator?
    private let bundleURLResolver: BundleURLResolver?

    public init(
        workspaceOpener: WorkspaceOpener? = nil,
        asyncWorkspaceOpener: AsyncWorkspaceOpener? = nil,
        directActivator: DirectActivator? = nil,
        bundleURLResolver: BundleURLResolver? = nil
    ) {
        self.workspaceOpener = workspaceOpener
        self.asyncWorkspaceOpener = asyncWorkspaceOpener
        self.directActivator = directActivator
        self.bundleURLResolver = bundleURLResolver
    }

    private static let defaultWorkspaceOpener: WorkspaceOpener = { url, config in
        if Thread.isMainThread {
            logger.warning("defaultWorkspaceOpener invoked synchronously on Main Thread; avoiding blocking semaphore wait")
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            return false
        }
        let sema = DispatchSemaphore(value: 0)
        let box = AtomicBoolBox()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error = error {
                logger.error("LaunchServices fallback activation failed: \(error.localizedDescription)")
                box.value = false
            } else {
                box.value = (app != nil)
            }
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 2.0)
        return box.value
    }
    
    public func frontmostApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }
    
    public func runningApplication(forProcessIdentifier pid: Int32) -> NSRunningApplication? {
        if let direct = NSRunningApplication(processIdentifier: pid_t(pid)) {
            return direct
        }
        return ResponsibleProcessResolver.resolveOwningApplication(for: pid_t(pid))
    }
    
    public func runningApplications(withBundleIdentifier bundleID: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }
    
    public func activate(application: NSRunningApplication) -> Bool {
        guard !application.isTerminated else {
            logger.warning("Cannot activate terminated application \(application.bundleIdentifier ?? "unknown") (PID: \(application.processIdentifier))")
            return false
        }
        guard !Task.isCancelled else {
            return false
        }
        logger.info("Activating application \(application.bundleIdentifier ?? "unknown") (PID: \(application.processIdentifier))")
        if application.isHidden {
            application.unhide()
        }

        var directSuccess = false
        if let customDirect = self.directActivator {
            directSuccess = customDirect(application)
        } else {
            if #available(macOS 14.0, *) {
                // When Flowback runs as a background accessory app, it holds no frontmost activation token.
                // Self-activating briefly and yielding activation to the target application ensures
                // cooperative activate(from:options:) is accepted by the macOS 14+ window server.
                let yieldBlock = {
                    MainActor.assumeIsolated {
                        if NSApplication.shared.activationPolicy() == .accessory {
                            NSApplication.shared.activate()
                            NSApplication.shared.yieldActivation(to: application)
                        }
                    }
                }
                if Thread.isMainThread {
                    yieldBlock()
                } else {
                    DispatchQueue.main.sync(execute: yieldBlock)
                }
                directSuccess = application.activate(from: NSRunningApplication.current, options: [])
                if !directSuccess {
                    directSuccess = application.activate(options: [])
                }
            } else {
                directSuccess = application.activate(options: [.activateIgnoringOtherApps])
            }
        }

        if directSuccess {
            return true
        }

        // Direct NSRunningApplication activation returned false.
        // Fallback: LaunchServices NSWorkspace.openApplication if bundleURL is present.
        let resolvedURL: URL?
        if let resolver = self.bundleURLResolver {
            resolvedURL = resolver(application)
        } else {
            resolvedURL = application.bundleURL ?? (application.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
        }
        guard let bundleURL = resolvedURL else {
            logger.warning("Direct activation failed and no bundleURL available for \(application.bundleIdentifier ?? "unknown")")
            return false
        }

        logger.info("Direct activation returned false for \(application.bundleIdentifier ?? "unknown"); attempting LaunchServices fallback")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = false
        config.activates = true

        if let syncOpener = self.workspaceOpener {
            return syncOpener(bundleURL, config)
        }

        return Self.defaultWorkspaceOpener(bundleURL, config)
    }

    public func activateApplication(_ application: NSRunningApplication) async -> Bool {
        guard !application.isTerminated else {
            logger.warning("Cannot activate terminated application \(application.bundleIdentifier ?? "unknown") (PID: \(application.processIdentifier))")
            return false
        }
        guard !Task.isCancelled else {
            logger.debug("activateApplication cancelled before execution")
            return false
        }
        logger.info("Activating application \(application.bundleIdentifier ?? "unknown") (PID: \(application.processIdentifier)) asynchronously")
        if application.isHidden {
            application.unhide()
        }

        var directSuccess = false
        if let customDirect = self.directActivator {
            directSuccess = customDirect(application)
        } else {
            if #available(macOS 14.0, *) {
                await MainActor.run {
                    if NSApplication.shared.activationPolicy() == .accessory {
                        NSApplication.shared.activate()
                        NSApplication.shared.yieldActivation(to: application)
                    }
                }
                guard !Task.isCancelled else { return false }
                directSuccess = application.activate(from: NSRunningApplication.current, options: [])
                if !directSuccess {
                    directSuccess = application.activate(options: [])
                }
            } else {
                directSuccess = application.activate(options: [.activateIgnoringOtherApps])
            }
        }

        if directSuccess {
            return true
        }

        guard !Task.isCancelled else { return false }

        // Direct activation failed; fallback to LaunchServices
        let resolvedURL: URL?
        if let resolver = self.bundleURLResolver {
            resolvedURL = resolver(application)
        } else {
            resolvedURL = application.bundleURL ?? (application.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
        }
        guard let bundleURL = resolvedURL else {
            logger.warning("Direct activation failed and no bundleURL available for \(application.bundleIdentifier ?? "unknown")")
            return false
        }

        logger.info("Direct activation returned false for \(application.bundleIdentifier ?? "unknown"); attempting asynchronous LaunchServices fallback")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = false
        config.activates = true

        if let customAsync = self.asyncWorkspaceOpener {
            do {
                let success = try await customAsync(bundleURL, config)
                return !Task.isCancelled && success
            } catch {
                logger.error("Custom async LaunchServices fallback failed: \(error.localizedDescription)")
                return false
            }
        } else if let customSync = self.workspaceOpener {
            let success = customSync(bundleURL, config)
            return !Task.isCancelled && success
        } else {
            do {
                let app = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
                return !Task.isCancelled && !app.isTerminated
            } catch {
                logger.error("LaunchServices fallback activation failed: \(error.localizedDescription)")
                return false
            }
        }
    }
}

private final class AtomicBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
