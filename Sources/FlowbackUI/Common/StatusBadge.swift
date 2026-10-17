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
            Image(systemName: ThemeTokens.statusIcon(for: state))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(textColor)
                .accessibilityHidden(true)
            Text(state.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(indicatorColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
        .overlay(
            Capsule()
                .strokeBorder(
                    indicatorColor.opacity(ThemeTokens.isHighContrastActive ? 0.65 : 0.25),
                    lineWidth: ThemeTokens.isHighContrastActive ? 1.2 : 0.7
                )
        )
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(state.displayName)")
        .accessibilityIdentifier("status-badge-\(state.rawValue)")
    }
    
    private var indicatorColor: Color {
        ThemeTokens.statusColor(state: state, scheme: colorScheme)
    }
    
    private var textColor: Color {
        ThemeTokens.statusColor(state: state, scheme: colorScheme)
    }
}
