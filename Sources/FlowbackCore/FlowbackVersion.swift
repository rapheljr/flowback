import Foundation

/// Canonical authoritative source of Flowback product versioning metadata.
public struct FlowbackVersion: Sendable {
    /// Semantic product version (MAJOR.MINOR.PATCH)
    public static let marketingVersion: String = "0.4.1"

    /// Monotonically increasing build number for bundle packaging
    public static let buildNumber: String = "2"

    /// Current version string, prioritizing CFBundleShortVersionString when running in an app bundle,
    /// falling back cleanly to canonical marketingVersion in standalone/CLI execution.
    public static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? marketingVersion
    }

    /// Current build string, prioritizing CFBundleVersion when running in an app bundle,
    /// falling back cleanly to canonical buildNumber in standalone/CLI execution.
    public static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? buildNumber
    }

    /// User-facing display banner
    public static var displayString: String {
        "Flowback v\(current) (build \(currentBuild))"
    }
}
