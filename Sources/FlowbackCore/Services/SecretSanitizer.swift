import Foundation

/// Fast, deterministic sanitizer that redacts credentials, access tokens, and private keys from event metadata and timeline details.
public enum SecretSanitizer: Sendable {
    private static let sensitiveKeySubstrings = [
        "token", "secret", "password", "apikey", "api_key", "credential", "authorization", "bearer", "privatekey", "private_key"
    ]
    
    // Explicit non-sensitive identifier keys that might contain "token" or "id" substrings
    private static let safeExactKeys: Set<String> = [
        "sessionID", "sessionId", "session_id", "conversationID", "conversationId", "conversation_title",
        "taskID", "taskId", "executionID", "executionId", "parentSessionID", "parent_session_id"
    ]
    
    public static func sanitizeMetadata(_ metadata: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(metadata.count)
        
        for (key, value) in metadata {
            if isSensitiveKey(key) {
                result[key] = "[REDACTED]"
            } else {
                result[key] = sanitizeText(value)
            }
        }
        return result
    }
    
    public static func isSensitiveKey(_ key: String) -> Bool {
        if safeExactKeys.contains(key) {
            return false
        }
        let lower = key.lowercased()
        return sensitiveKeySubstrings.contains { lower.contains($0) }
    }
    
    public static func sanitizeText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var sanitized = text
        
        // 1. Bearer tokens: Bearer <token>
        if let bearerRegex = try? NSRegularExpression(pattern: "Bearer\\s+[A-Za-z0-9_\\-\\.~\\+\\/=]+", options: .caseInsensitive) {
            sanitized = bearerRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(location: 0, length: sanitized.utf16.count),
                withTemplate: "Bearer [REDACTED]"
            )
        }
        
        // 2. Common API key patterns (e.g. sk-..., ghp_..., github_pat_..., xox...)
        if let keyRegex = try? NSRegularExpression(
            pattern: "\\b(sk-[a-zA-Z0-9_-]{12,}|ghp_[a-zA-Z0-9]{12,}|github_pat_[a-zA-Z0-9_]{22,}|xox[baprs]-[a-zA-Z0-9-]{10,})\\b",
            options: []
        ) {
            sanitized = keyRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(location: 0, length: sanitized.utf16.count),
                withTemplate: "[REDACTED_API_KEY]"
            )
        }
        
        // 3. Key-value secrets like token=... or password=...
        if let kvRegex = try? NSRegularExpression(pattern: "(?i)(password|secret|token|api[_-]?key)\\s*[:=]\\s*[\"']?([^\\s\"';&]+)", options: []) {
            sanitized = kvRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(location: 0, length: sanitized.utf16.count),
                withTemplate: "$1=[REDACTED]"
            )
        }

        // 4. URL basic auth credentials (e.g. https://user:secretpassword@host)
        if let urlAuthRegex = try? NSRegularExpression(pattern: "(https?://)([^:\\s/@]+):([^@\\s/]+)@", options: .caseInsensitive) {
            sanitized = urlAuthRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(location: 0, length: sanitized.utf16.count),
                withTemplate: "$1$2:[REDACTED_PASSWORD]@"
            )
        }

        // 5. PEM private-key blocks
        let pemPattern = "-----BEGIN[A-Za-z0-9_ -]*PRIVATE KEY-----[\\s\\S]*?-----END[A-Za-z0-9_ -]*PRIVATE KEY-----"
        if let pemRegex = try? NSRegularExpression(pattern: pemPattern, options: []) {
            sanitized = pemRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(location: 0, length: sanitized.utf16.count),
                withTemplate: "[REDACTED_PRIVATE_KEY_BLOCK]"
            )
        }

        // 6. Sensitive URL query parameters
        let queryPattern = "([?&](?:api[_-]?key|token|access_token|secret|client_secret|password|auth|authorization)=)[^&\\s#]+"
        if let queryRegex = try? NSRegularExpression(pattern: queryPattern, options: .caseInsensitive) {
            sanitized = queryRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(location: 0, length: sanitized.utf16.count),
                withTemplate: "$1[REDACTED]"
            )
        }
        
        return sanitized
    }
}
