import Foundation

/// Shared utility for parsing human-readable conversation titles and objectives from AI agent transcript logs
public struct BrainTranscriptParser: Sendable {

    /// Extracts conversation title or objective from transcript content
    public static func extractConversationTitle(from text: String) -> String? {
        // 1. Look for <USER_REQUEST> ... </USER_REQUEST> block
        if let startRange = text.range(of: "<USER_REQUEST>"),
           let endRange = text.range(of: "</USER_REQUEST>") {
            var userReq = String(text[startRange.upperBound..<endRange.lowerBound])
            // Normalize JSON-escaped newlines and carriage returns found in raw transcript JSONL
            userReq = userReq.replacingOccurrences(of: "\\r\\n", with: "\n")
                             .replacingOccurrences(of: "\\n", with: "\n")
                             .replacingOccurrences(of: "\\r", with: "\n")
                             .trimmingCharacters(in: .whitespacesAndNewlines)

            let lines = userReq.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for line in lines {
                var clean = line
                while clean.hasPrefix("\\n") || clean.hasPrefix("\\r") {
                    clean = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                if clean.hasPrefix("/goal") { clean = clean.replacingOccurrences(of: "/goal", with: "").trimmingCharacters(in: .whitespaces) }
                if clean.hasPrefix("/plan") { clean = clean.replacingOccurrences(of: "/plan", with: "").trimmingCharacters(in: .whitespaces) }
                while clean.hasPrefix("#") { clean = clean.dropFirst().trimmingCharacters(in: .whitespaces) }

                // Strip leading project prefixes like "Project × Reference — Title" or "Project — Title"
                if let dashRange = clean.range(of: " — ") {
                    let afterDash = String(clean[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !afterDash.isEmpty {
                        clean = afterDash
                    }
                } else if let hyphenRange = clean.range(of: " - ") {
                    let afterHyphen = String(clean[hyphenRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !afterHyphen.isEmpty {
                        clean = afterHyphen
                    }
                }

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

    /// Extracts workspace path from transcript content
    public static func extractWorkspacePath(from text: String) -> String? {
        let userHome = NSHomeDirectory()

        // 1. Antigravity system prompt format: [URI] -> [CorpusName]
        if let uriRange = text.range(of: "(/[^\\s\n\"']+)\\s*->", options: .regularExpression) {
            let uriLine = String(text[uriRange])
            if let pathPart = uriLine.components(separatedBy: "->").first?.trimmingCharacters(in: .whitespaces),
               pathPart.hasPrefix("/") {
                return pathPart
            }
        }

        // 1b. Reverse format: -> /path/...
        if let uriRange = text.range(of: "->\\s*(/[^\\n\\s\"']+)", options: .regularExpression) {
            let uriLine = String(text[uriRange])
            let pathPart = uriLine.replacingOccurrences(of: "->", with: "").trimmingCharacters(in: .whitespaces)
            if pathPart.hasPrefix("/") {
                return pathPart
            }
        }

        // 2. Explicit JSON field: "workspacePaths": ["/path/..."]
        if let wsRange = text.range(of: "\"workspacePaths\":\\s*\\[\\s*\"([^\"]+)\"", options: .regularExpression) {
            let matched = String(text[wsRange])
            let comps = matched.components(separatedBy: "\"")
            if comps.count >= 4 {
                let candidate = comps[3].replacingOccurrences(of: "\\/", with: "/")
                if candidate.hasPrefix("/") {
                    return candidate
                }
            }
        }

        // 3. Explicit JSON field: "Cwd": "..."
        if let cwdRange = text.range(of: "\"Cwd\":\\s*\"([^\"]+)\"", options: .regularExpression) {
            let matched = String(text[cwdRange])
            let comps = matched.components(separatedBy: "\"")
            if comps.count >= 4 {
                return comps[3].replacingOccurrences(of: "\\/", with: "/")
            }
        }

        // 4. Active Document: /path/...
        if let docRange = text.range(of: "Active Document:\\s*([^\\n]+)", options: .regularExpression) {
            let docLine = String(text[docRange])
            let pathPart = docLine.replacingOccurrences(of: "Active Document:", with: "").trimmingCharacters(in: .whitespaces)
            if let firstSlash = pathPart.firstIndex(of: "/") {
                let fullPath = String(pathPart[firstSlash...])
                let comps = fullPath.components(separatedBy: "/workspace/projects/")
                if comps.count > 1, let proj = comps.last?.components(separatedBy: "/").first, !proj.isEmpty {
                    return (userHome as NSString).appendingPathComponent("workspace/projects/\(proj)")
                } else {
                    return (fullPath as NSString).deletingLastPathComponent
                }
            }
        }

        // 5. file:///Users/... URI
        let filePattern = "file://(/[^/\\s\n\"']+/[^/\\s\n\"']+/[^/\\s\n\"']+/[^/\\s\n\"']+)"
        if let fileUriRange = text.range(of: filePattern, options: .regularExpression) {
            let fileLine = String(text[fileUriRange])
            let pathPart = fileLine.replacingOccurrences(of: "file://", with: "").trimmingCharacters(in: .whitespaces)
            let comps = pathPart.components(separatedBy: "/workspace/projects/")
            if comps.count > 1, let proj = comps.last?.components(separatedBy: "/").first, !proj.isEmpty {
                return (userHome as NSString).appendingPathComponent("workspace/projects/\(proj)")
            }
        }

        // 6. Fallback heuristic: /workspace/projects/<name>
        if let projRange = text.range(of: "/workspace/projects/([A-Za-z0-9_-]+)", options: .regularExpression) {
            let matched = String(text[projRange])
            let comps = matched.components(separatedBy: "/workspace/projects/")
            if comps.count > 1, let proj = comps.last?.components(separatedBy: "/").first, !proj.isEmpty {
                return (userHome as NSString).appendingPathComponent("workspace/projects/\(proj)")
            }
        }

        return nil
    }
}
