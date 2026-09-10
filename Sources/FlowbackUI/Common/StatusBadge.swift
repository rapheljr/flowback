import SwiftUI
import FlowbackCore

public struct StatusBadge: View {
    public let state: AgentState
    
    public init(state: AgentState) {
        self.state = state
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    private var color: Color {
        switch state {
        case .unknown: return .secondary
        case .starting: return .blue
        case .running: return .blue
        case .waiting: return .purple
        case .permissionRequired: return .orange
        case .paused: return .yellow
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}
