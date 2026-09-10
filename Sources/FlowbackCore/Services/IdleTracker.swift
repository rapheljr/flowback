import Foundation
import CoreGraphics

public protocol IdleTracking: Sendable {
    func systemIdleSeconds() -> Double
    func isUserActive(within seconds: Double) -> Bool
}

/// Tracks user inactivity without recording keystrokes or mouse positions
public final class IdleTracker: IdleTracking, Sendable {
    public static let shared = IdleTracker()
    
    public init() {}
    
    public func systemIdleSeconds() -> Double {
        // CGEventSource.secondsSinceLastEventType returns system-wide idle time in seconds
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0) ?? .null)
        if idle < 0 { return 0.0 }
        return Double(idle)
    }
    
    public func isUserActive(within seconds: Double) -> Bool {
        systemIdleSeconds() <= seconds
    }
}
