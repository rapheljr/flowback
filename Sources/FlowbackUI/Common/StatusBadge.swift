import SwiftUI
import FlowbackCore

public struct StatusBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    public let state: AgentState
    
    public init(state: AgentState) {
        self.state = state
    }
    
    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
            Text(state.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(indicatorColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(state.displayName)")
        .accessibilityIdentifier("status-badge-\(state.rawValue)")
    }
    
    private var indicatorColor: Color {
        switch state {
        case .unknown: return .secondary
        case .starting, .running: return .blue
        case .waiting: return .purple
        case .permissionRequired: return .orange
        case .paused: return .yellow
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
    
    private var textColor: Color {
        if colorScheme == .light {
            switch state {
            case .paused:
                // WCAG AA compliant amber for light backgrounds
                return Color(red: 0.60, green: 0.42, blue: 0.0)
            case .completed:
                // WCAG AA compliant forest green for light backgrounds
                return Color(red: 0.10, green: 0.50, blue: 0.20)
            case .starting, .running:
                return Color(red: 0.05, green: 0.35, blue: 0.75)
            case .permissionRequired:
                return Color(red: 0.70, green: 0.32, blue: 0.0)
            default:
                return indicatorColor
            }
        }
        return indicatorColor
    }
}
