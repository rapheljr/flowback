import Foundation

/// Shared utility for parsing human-readable conversation titles and objectives from AI agent transcript logs
public struct BrainTranscriptParser: Sendable {

    /// Extracts conversation title or objective from transcript content
    public static func extractConversationTitle(from text: String) -> String? {
        // 1. Look for <USER_REQUEST> ... </USER_REQUEST> block
        if let startRange = text.range(of: "<USER_REQUEST>"),
           let endRange = text.range(of: "</USER_REQUEST>") {
            let userReq = String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = userReq.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for line in lines {
                var clean = line
                if clean.hasPrefix("/goal") { clean = clean.replacingOccurrences(of: "/goal", with: "").trimmingCharacters(in: .whitespaces) }
                if clean.hasPrefix("/plan") { clean = clean.replacingOccurrences(of: "/plan", with: "").trimmingCharacters(in: .whitespaces) }
                while clean.hasPrefix("#") { clean = clean.dropFirst().trimmingCharacters(in: .whitespaces) }
                if !clean.isEmpty {
                    return String(clean.prefix(120))
                }
            }
        }

        // 2. Look for "### USER Objective: <title>"
        if let objRange = text.range(of: "### USER Objective:\\s*([^\\n]+)", options: .regularExpression) {
            let matched = String(text[objRange])
            let title = matched.replacingOccurrences(of: "### USER Objective:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return String(title.prefix(120))
            }
        }

        return nil
    }
}
