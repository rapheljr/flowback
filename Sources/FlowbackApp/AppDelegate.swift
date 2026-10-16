import Foundation
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationReplyPending = false
    private var isTerminated = false
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu bar accessory application
        NSApp.setActivationPolicy(.accessory)
        
        Task {
            await FlowbackService.shared.start()
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        FlowbackService.shared.openDashboardWindow()
        return true
    }
    
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if FlowbackService.shared.lifecycleState == .stopped || isTerminated {
            return .terminateNow
        }
        
        // Prevent duplicate tasks and multiple replies if quit is triggered repeatedly
        if terminationReplyPending {
            return .terminateLater
        }
        terminationReplyPending = true
        
        Task { @MainActor in
            await FlowbackService.shared.stop()
            guard !self.isTerminated else { return }
            self.isTerminated = true
            self.terminationReplyPending = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        if FlowbackService.shared.lifecycleState != .stopped {
            isTerminated = true
            FlowbackService.shared.emergencySyncStop()
        }
    }
}
