import SwiftUI
import FlowbackCore

public struct WhatsNewView: View {
    @Environment(\.colorScheme) private var colorScheme
    public let releaseNotes: [ReleaseNote]

    public init(releaseNotes: [ReleaseNote] = ReleaseNotesModel.bundledNotes) {
        self.releaseNotes = releaseNotes
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowbackSpacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                    Text("What's New in Flowback")
                        .font(.title2.bold())
                    if let latest = releaseNotes.first {
                        Text("Version \(latest.version) · Released \(latest.date)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Release notes and version history.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                if releaseNotes.isEmpty {
                    FlowbackEmptyState(
                        icon: "sparkles",
                        title: "No Release Notes Available",
                        message: "Flowback is up to date. Release notes for future updates will appear here."
                    )
                } else {
                    ForEach(releaseNotes) { note in
                        renderReleaseNote(note)
                    }
                }
            }
            .padding(FlowbackSpacing.xxl)
        }
        .accessibilityIdentifier("whats-new-scroll-view")
    }

    @ViewBuilder
    private func renderReleaseNote(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: FlowbackSpacing.lg) {
            // Summary Banner Card
            FlowbackCard {
                HStack(alignment: .top, spacing: FlowbackSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: FlowbackRadius.control, style: .continuous)
                            .fill(ThemeTokens.iconTileFill(tint: .accentColor, scheme: colorScheme))
                            .frame(width: 36, height: 36)
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: FlowbackSpacing.xxs) {
                        HStack(spacing: FlowbackSpacing.sm) {
                            Text("Flowback v\(note.version)")
                                .font(.headline)
                            Text("Current Release")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.accentColor))
                        }

                        Text(note.summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Categorized Sections
            ForEach(note.sections) { section in
                renderSection(section)
            }
        }
    }

    @ViewBuilder
    private func renderSection(_ section: ReleaseNoteSection) -> some View {
        VStack(alignment: .leading, spacing: FlowbackSpacing.sm) {
            HStack(spacing: FlowbackSpacing.xs) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(sectionColor(for: section.title))
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.top, FlowbackSpacing.xs)

            VStack(alignment: .leading, spacing: FlowbackSpacing.sm) {
                ForEach(section.items, id: \.self) { item in
                    HStack(alignment: .top, spacing: FlowbackSpacing.sm) {
                        Circle()
                            .fill(sectionColor(for: section.title).opacity(0.8))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                            .accessibilityHidden(true)

                        Text(item)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, FlowbackSpacing.xs)
                }
            }
            .flowbackCard(cornerRadius: FlowbackRadius.subcard, padding: FlowbackSpacing.md)
        }
    }

    private func sectionColor(for title: String) -> Color {
        let lower = title.lowercased()
        if lower.contains("add") {
            return .blue
        } else if lower.contains("change") || lower.contains("improve") {
            return .purple
        } else if lower.contains("fix") {
            return .green
        } else if lower.contains("security") || lower.contains("privacy") {
            return .teal
        } else if lower.contains("limit") || lower.contains("warn") {
            return .orange
        }
        return .accentColor
    }
}
