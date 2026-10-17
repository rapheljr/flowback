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
}

/// Manages discovery and activation of macOS applications using NSWorkspace
public final class ApplicationController: ApplicationControlling, @unchecked Sendable {
    public static let shared = ApplicationController()
    
    public init() {}
    
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
        logger.info("Activating application \(application.bundleIdentifier ?? "unknown") (PID: \(application.processIdentifier))")
        if application.isHidden {
            application.unhide()
        }
        if #available(macOS 14.0, *) {
            // When Flowback runs as a background accessory app, it holds no frontmost activation token.
            // Self-activating briefly and yielding activation to the target application ensures
            // cooperative activate(from:options:) is accepted by the macOS 14+ window server.
            let yieldBlock = {
                MainActor.assumeIsolated {
                    if NSApplication.shared.activationPolicy() == .accessory {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        NSApplication.shared.yieldActivation(to: application)
                    }
                }
            }
            if Thread.isMainThread {
                yieldBlock()
            } else {
                DispatchQueue.main.sync(execute: yieldBlock)
            }
            let success = application.activate(from: NSRunningApplication.current, options: [])
            if !success {
                return application.activate(options: [.activateIgnoringOtherApps])
            }
            return true
        } else {
            return application.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
