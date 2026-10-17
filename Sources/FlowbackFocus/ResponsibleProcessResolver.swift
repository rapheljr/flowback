import Foundation
import AppKit
import Darwin
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "ResponsibleProcessResolver")

/// Resolves the responsible parent application for child processes, CLI agents, and terminal subprocesses
public enum ResponsibleProcessResolver {

    /// Dynamic lookup for `responsibility_get_pid_responsible_for_pid` in libsystem
    private static let resolveResponsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    /// Returns the immediate parent process ID for a given PID using BSD process info
    public static func parentPID(of pid: pid_t) -> pid_t? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let ppid = pid_t(info.pbi_ppid)
        return ppid > 0 ? ppid : nil
    }

    /// Queries the responsible process ID reported by macOS libsystem responsibility API
    public static func responsiblePID(for pid: pid_t) -> pid_t {
        guard pid > 1 else { return pid }
        if let resolver = resolveResponsiblePID {
            let responsible = resolver(pid)
            if responsible > 0 { return responsible }
        }
        return pid
    }

    /// Resolves the enclosing regular (GUI/windowed) application owning a process or its ancestor chain
    public static func resolveOwningApplication(for pid: pid_t, maxDepth: Int = 10) -> NSRunningApplication? {
        guard pid > 1 else { return nil }

        // 1. Direct check: Is the process itself a regular application?
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            return app
        }

        // 2. Responsibility check: Does macOS attribute this process to an owning application?
        let respPID = responsiblePID(for: pid)
        if respPID != pid, respPID > 1 {
            if let app = NSRunningApplication(processIdentifier: respPID), app.activationPolicy == .regular {
                return app
            }
        }

        // 3. Ancestor traversal: Walk up parent process hierarchy to locate nearest GUI app
        var current = pid
        for _ in 0..<maxDepth {
            guard let parent = parentPID(of: current), parent > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular {
                return app
            }
            current = parent
        }

        return nil
    }
}
