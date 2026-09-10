import Foundation
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
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
}
