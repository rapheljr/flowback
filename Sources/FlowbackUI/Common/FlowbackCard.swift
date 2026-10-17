import SwiftUI
import AppKit

/// Standard card container for Flowback dashboard views
public struct FlowbackCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let title: String?
    private let subtitle: String?
    private let padding: CGFloat
    private let content: Content

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        padding: CGFloat = FlowbackSpacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                    if let title {
                        Text(title)
                            .font(.headline)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: FlowbackRadius.card, style: .continuous)
                .fill(ThemeTokens.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowbackRadius.card, style: .continuous)
                .strokeBorder(ThemeTokens.cardBorder(for: colorScheme), lineWidth: ThemeTokens.cardBorderWidth)
        )
    }
}

/// A structured card grouping related settings controls
public struct FlowbackSettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let title: String?
    private let subtitle: String?
    private let content: Content

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowbackSpacing.md) {
            if let title {
                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FlowbackSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: FlowbackRadius.card, style: .continuous)
                .fill(ThemeTokens.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowbackRadius.card, style: .continuous)
                .strokeBorder(ThemeTokens.cardBorder(for: colorScheme), lineWidth: ThemeTokens.cardBorderWidth)
        )
    }
}

/// A standardized settings row with icon tile, headline, caption, and accessory control
public struct FlowbackSettingsRow<Accessory: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let icon: String
    private let iconColor: Color
    private let title: String
    private let caption: String?
    private let badge: String?
    private let accessory: Accessory

    public init(
        icon: String,
        iconColor: Color = .accentColor,
        title: String,
        caption: String? = nil,
        badge: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.caption = caption
        self.badge = badge
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: FlowbackSpacing.md) {
            // Icon tile
            ZStack {
                RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                    .fill(ThemeTokens.iconTileFill(tint: iconColor, scheme: colorScheme))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .accessibilityHidden(true)

            // Titles
            VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                HStack(spacing: FlowbackSpacing.sm) {
                    Text(title)
                        .font(.body)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .accessibilityHidden(true)
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: FlowbackSpacing.md)

            accessory
        }
    }
}

/// Actionable, structured empty state view
public struct FlowbackEmptyState: View {
    private let icon: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let onAction: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: FlowbackSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: FlowbackSpacing.xs) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, FlowbackSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
    }
}
