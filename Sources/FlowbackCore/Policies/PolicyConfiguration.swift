import Foundation

/// Main versioned configuration for Flowback
public struct PolicyConfiguration: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var focusPolicy: FocusPolicyType
    public var completionBehavior: CompletionBehavior
    public var permissionBehavior: PermissionBehavior
    public var failureBehavior: FailureBehavior
    public var spacePolicy: SpacePolicy
    public var focusCooldownMs: Int
    public var attentionAggregationMs: Int
    public var activeInteractionThresholdSeconds: Double
    public var protectedApplications: [String]
    public var launchAtLogin: Bool
    public var providerOverrides: [String: FocusPolicyType]
    public var applicationOverrides: [String: FocusPolicyType]
    public var workspaceOverrides: [String: FocusPolicyType]
    
    public init(
        schemaVersion: Int = 1,
        focusPolicy: FocusPolicyType = .smart,
        completionBehavior: CompletionBehavior = .restoreOrigin,
        permissionBehavior: PermissionBehavior = .focusAgent,
        failureBehavior: FailureBehavior = .focusAgent,
        spacePolicy: SpacePolicy = .neverSwitchSpaces,
        focusCooldownMs: Int = 1000,
        attentionAggregationMs: Int = 1500,
        activeInteractionThresholdSeconds: Double = 5.0,
        protectedApplications: [String] = [
            "com.apple.keynote",
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.cisco.webexmeetingsapp",
            "com.apple.FaceTime",
            "com.apple.QuickTimePlayerX",
            "com.telestream.screenflow10"
        ],
        launchAtLogin: Bool = false,
        providerOverrides: [String: FocusPolicyType] = [:],
        applicationOverrides: [String: FocusPolicyType] = [:],
        workspaceOverrides: [String: FocusPolicyType] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.focusPolicy = focusPolicy
        self.completionBehavior = completionBehavior
        self.permissionBehavior = permissionBehavior
        self.failureBehavior = failureBehavior
        self.spacePolicy = spacePolicy
        self.focusCooldownMs = focusCooldownMs
        self.attentionAggregationMs = attentionAggregationMs
        self.activeInteractionThresholdSeconds = activeInteractionThresholdSeconds
        self.protectedApplications = protectedApplications
        self.launchAtLogin = launchAtLogin
        self.providerOverrides = providerOverrides
        self.applicationOverrides = applicationOverrides
        self.workspaceOverrides = workspaceOverrides
    }
    
    public static let `default` = PolicyConfiguration()
    
    /// Resolves the effective focus policy considering overrides in order: workspace -> app -> provider -> global
    public func resolvePolicy(
        provider: AgentProviderID?,
        appBundleID: String?,
        workspace: String?
    ) -> FocusPolicyType {
        if let ws = workspace, let override = workspaceOverrides[ws] {
            return override
        }
        if let bundle = appBundleID, let override = applicationOverrides[bundle] {
            return override
        }
        if let prov = provider, let override = providerOverrides[prov.rawValue] {
            return override
        }
        return focusPolicy
    }
}
