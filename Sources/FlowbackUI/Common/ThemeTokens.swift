import SwiftUI
import AppKit
import FlowbackCore

/// Standardized spacing scale conforming to the 4pt/8pt macOS typographic grid
public enum FlowbackSpacing {
    /// 2pt: Micro-adjustments and badge icon gaps
    public static let xxs: CGFloat = 2
    /// 4pt: Badge internal vertical padding, tight label gaps
    public static let xs: CGFloat = 4
    /// 8pt: Content-to-subheading gap, icon-to-text spacing
    public static let sm: CGFloat = 8
    /// 12pt: List item spacing, card internal gap, control spacing
    public static let md: CGFloat = 12
    /// 16pt: Card internal padding, section row spacing
    public static let lg: CGFloat = 16
    /// 20pt: Major section separation, form insets
    public static let xl: CGFloat = 20
    /// 24pt: Standard page horizontal margins and header offsets
    public static let xxl: CGFloat = 24
}

/// Standardized continuous corner radii across all Flowback surfaces
public enum FlowbackRadius {
    /// 6pt: Inline chips, badges, and code tags
    public static let badge: CGFloat = 6
    /// 8pt: Standard buttons, text fields, and icon tiles
    public static let control: CGFloat = 8
    /// 12pt: Nested containers and alert banners
    public static let subcard: CGFloat = 12
    /// 14pt: Primary section cards and modal surfaces
    public static let card: CGFloat = 14
}

/// Centralized accessible design tokens and contrast adapters adhering to Apple HIG and WCAG AA standards
public enum ThemeTokens {

    /// Whether the user has enabled Increase Contrast in macOS Accessibility preferences
    public static var isHighContrastActive: Bool {
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return true
        }
        let name = NSAppearance.currentDrawing().name
        return name == .accessibilityHighContrastDarkAqua || name == .accessibilityHighContrastAqua
    }

    /// Background card surface fill adjusted for current color scheme
    public static func cardFill(for scheme: ColorScheme) -> Color {
        if isHighContrastActive {
            return scheme == .light ? Color.white : Color(white: 0.16)
        }
        return scheme == .light ? Color.white.opacity(0.70) : Color(white: 0.14).opacity(0.80)
    }

    /// Subtle background fill for controls, text inputs, and search fields
    public static func controlFill(for scheme: ColorScheme) -> Color {
        let highContrast = isHighContrastActive
        if scheme == .light {
            return Color.black.opacity(highContrast ? 0.08 : 0.05)
        } else {
            return Color.white.opacity(highContrast ? 0.12 : 0.08)
        }
    }

    /// Tinted background fill for 28x28 icon tiles
    public static func iconTileFill(tint: Color, scheme: ColorScheme) -> Color {
        tint.opacity(scheme == .light ? 0.14 : 0.22)
    }

    /// Border stroke color adapting automatically to macOS Increase Contrast setting
    public static func cardBorder(for scheme: ColorScheme) -> Color {
        let highContrast = isHighContrastActive
        if scheme == .light {
            return Color.black.opacity(highContrast ? 0.30 : 0.10)
        } else {
            return Color.white.opacity(highContrast ? 0.35 : 0.12)
        }
    }

    /// Border stroke line width adapting to contrast mode
    public static var cardBorderWidth: CGFloat {
        isHighContrastActive ? 1.2 : 0.7
    }

    /// Luminance-adjusted WCAG AA status colors ensuring at least 4.5:1 contrast against light backgrounds
    public static func statusColor(state: FlowbackCore.AgentState, scheme: ColorScheme) -> Color {
        switch state {
        case .starting, .running:
            return scheme == .light ? Color(red: 0.05, green: 0.38, blue: 0.78) : .blue
        case .completed:
            return scheme == .light ? Color(red: 0.08, green: 0.48, blue: 0.22) : .green
        case .permissionRequired:
            return scheme == .light ? Color(red: 0.72, green: 0.32, blue: 0.02) : .orange
        case .waiting:
            return scheme == .light ? Color(red: 0.50, green: 0.20, blue: 0.75) : .purple
        case .paused:
            return scheme == .light ? Color(red: 0.62, green: 0.42, blue: 0.00) : .yellow
        case .failed:
            return scheme == .light ? Color(red: 0.75, green: 0.12, blue: 0.14) : .red
        case .cancelled, .unknown:
            return scheme == .light ? Color(white: 0.40) : .gray
        }
    }

    /// SF Symbol icon name communicating state unambiguously without relying on color perception (WCAG 1.4.1)
    public static func statusIcon(for state: FlowbackCore.AgentState) -> String {
        switch state {
        case .starting:
            return "rays"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle.fill"
        case .permissionRequired:
            return "hand.raised.fill"
        case .waiting:
            return "clock.arrow.circlepath"
        case .paused:
            return "pause.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .cancelled:
            return "slash.circle"
        case .unknown:
            return "circle.dotted"
        }
    }
}

public struct FlowbackCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var cornerRadius: CGFloat
    public var padding: CGFloat

    public init(cornerRadius: CGFloat = FlowbackRadius.card, padding: CGFloat = FlowbackSpacing.md) {
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ThemeTokens.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ThemeTokens.cardBorder(for: colorScheme), lineWidth: ThemeTokens.cardBorderWidth)
            )
    }
}

public extension View {
    func flowbackCard(cornerRadius: CGFloat = FlowbackRadius.card, padding: CGFloat = FlowbackSpacing.md) -> some View {
        modifier(FlowbackCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}
