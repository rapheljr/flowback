import Foundation
import AppKit
import FlowbackCore
import OSLog

private let logger = Logger(subsystem: "com.flowback.app", category: "CursorBackgroundProvider")

/// Protocol abstracting HTTP data loading for injectable network operations and testing
public protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataLoading {}

public final class CursorBackgroundProvider: AgentProvider, @unchecked Sendable {
    public let providerID = AgentProviderID.cursorBackground
    public let displayName = "Cursor Background Agent"
    public let isSupported = true

    private let apiKeyProvider: @Sendable () -> String?
    private let apiBaseURL: URL
    private let httpClient: HTTPDataLoading
    private let keyStoragePath: String
    private let stateLock = NSLock()
    private var backoffUntil: Date?
    private var lastAuthError: String?
    private var isPolling: Bool = false

    public init(
        apiKeyProvider: (@Sendable () -> String?)? = nil,
        apiBaseURL: URL = URL(string: "https://api.cursor.com/v1")!,
        httpClient: HTTPDataLoading = URLSession.shared,
        keyStoragePath: String = ("~/.flowback/cursor_api_key" as NSString).expandingTildeInPath
    ) {
        self.apiBaseURL = apiBaseURL
        self.httpClient = httpClient
        self.keyStoragePath = keyStoragePath

        if let custom = apiKeyProvider {
            self.apiKeyProvider = custom
        } else {
            let storagePath = keyStoragePath
            self.apiKeyProvider = {
                if let envKey = ProcessInfo.processInfo.environment["CURSOR_API_KEY"], !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if FileManager.default.fileExists(atPath: storagePath),
                   let saved = try? String(contentsOfFile: storagePath, encoding: .utf8) {
                    let clean = saved.trimmingCharacters(in: .whitespacesAndNewlines)
                    return clean.isEmpty ? nil : clean
                }
                return nil
            }
        }
    }

    private func getLastAuthError() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastAuthError
    }

    private func tryBeginPolling() -> (allowed: Bool, backoffDate: Date?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let now = Date()
        if let until = backoffUntil, now < until {
            return (false, until)
        }
        if isPolling {
            return (false, nil)
        }
        isPolling = true
        return (true, nil)
    }

    private func finishPolling() {
        stateLock.lock()
        defer { stateLock.unlock() }
        isPolling = false
    }

    private func recordSuccess() {
        stateLock.lock()
        defer { stateLock.unlock() }
        lastAuthError = nil
        backoffUntil = nil
    }

    private func recordAuthError(_ error: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        lastAuthError = error
    }

    private func recordBackoff(seconds: Double) {
        stateLock.lock()
        defer { stateLock.unlock() }
        backoffUntil = Date().addingTimeInterval(seconds)
    }

    public var supportLevel: ProviderSupportLevel {
        if apiKeyProvider() != nil {
            return .nativeLifecycle
        }
        return .partial
    }

    public func checkHealth() async -> ProviderHealth {
        let hasKey = (apiKeyProvider() != nil)
        let keyExistsOnDisk = FileManager.default.fileExists(atPath: keyStoragePath)

        let authErr = getLastAuthError()

        let statusMessage: String
        let support: ProviderSupportLevel

        if !hasKey {
            statusMessage = "Cursor Background Agent API key not configured. Store key in ~/.flowback/cursor_api_key or CURSOR_API_KEY to activate cloud tracking."
            support = .partial
        } else if let err = authErr {
            statusMessage = "Cursor API key configured, but authentication failed: \(err)"
            support = .partial
        } else {
            statusMessage = "Cursor Cloud Agents API key configured; remote background agent tracking enabled"
            support = .nativeLifecycle
        }

        return ProviderHealth(
            providerID: providerID,
            displayName: displayName,
            isInstalled: hasKey,
            version: "v1",
            hookInstalled: hasKey,
            hookExecutable: hasKey,
            configurationPath: keyExistsOnDisk ? keyStoragePath : nil,
            statusMessage: statusMessage,
            isSupported: true,
            supportLevel: support
        )
    }

    public func parseLifecyclePayload(data: Data) throws -> AgentEvent? {
        let decoder = JSONDecoder()
        guard let agent = try? decoder.decode(CursorCloudAgent.self, from: data) else {
            logger.warning("Could not decode Cursor Cloud Agent payload")
            return nil
        }

        let agentId = agent.id
        let rawStatus = (agent.status ?? "RUNNING").uppercased()

        var metadata: [String: String] = [
            "agentId": agentId,
            "status": rawStatus
        ]

        let repoUrl = agent.repository ?? agent.repos?.first?.url
        if let r = repoUrl { metadata["repositoryUrl"] = r }
        if let branch = agent.branchName ?? agent.targetRef ?? agent.repos?.first?.startingRef {
            metadata["branch"] = branch
        }
        if let pr = agent.prUrl { metadata["prUrl"] = pr }
        if let runId = agent.latestRunId { metadata["latestRunId"] = runId }
        if let summary = agent.summary { metadata["summary"] = summary }
        if let parentId = agent.parentAgentId, !parentId.isEmpty {
            metadata["parentSessionId"] = parentId
            metadata["isSubagent"] = "true"
        }
        if let err = agent.error, !err.isEmpty {
            metadata["error"] = err
        }

        // Custom deduplication key: cursor-bg:id:status:runId
        let runPart = agent.latestRunId ?? ""
        metadata["deduplicationKey"] = "cursor-bg:\(agentId):\(rawStatus):\(runPart)"

        let eventType: AgentEventType
        if let err = metadata["error"], !err.isEmpty {
            eventType = .agentFailed
        } else {
            switch rawStatus {
            case "RUNNING", "PENDING", "IN_PROGRESS":
                eventType = .agentRunning
            case "COMPLETED", "FINISHED", "SUCCESS":
                eventType = .agentCompleted
            case "FAILED", "ERROR":
                eventType = .agentFailed
            case "WAITING", "PAUSED":
                eventType = .agentWaiting
            case "CONFIRMATION_REQUIRED", "BLOCKED":
                eventType = .agentPermissionRequired
            case "CANCELLED", "ABORTED":
                eventType = .agentCancelled
            default:
                eventType = .agentRunning
            }
        }

        // Resolve Remote Context
        // Check if there is a local clone of this repository on disk
        var matchedWorkspacePath: String?
        if let r = repoUrl {
            matchedWorkspacePath = findLocalWorkspace(forRepositoryURL: r)
        }

        let remoteDestinationURL: String? = agent.prUrl ?? (agent.repository != nil ? agent.repository : "https://cursor.com/agents/\(agent.id)")

        let origin: OriginContext
        if let localWs = matchedWorkspacePath {
            origin = OriginContext(
                bundleIdentifier: "co.anysphere.cursor",
                processIdentifier: 0,
                workspacePath: localWs,
                provenance: .ipcExplicit,
                confidence: 0.9,
                restorationCapability: .workspaceWindow
            )
        } else {
            origin = OriginContext(
                bundleIdentifier: "com.apple.Safari",
                processIdentifier: 0,
                workspacePath: remoteDestinationURL,
                provenance: .ipcExplicit,
                confidence: 0.7,
                restorationCapability: (remoteDestinationURL != nil) ? .notificationFallbackOnly : .unsupported
            )
        }

        return AgentEvent(
            timestamp: Date(),
            providerID: providerID,
            sessionID: AgentSessionID(agentId),
            type: eventType,
            workspace: matchedWorkspacePath ?? remoteDestinationURL,
            origin: origin,
            metadata: metadata
        )
    }

    public func installIntegration() async throws {
        // No local hooks required for cloud background agent; configuration is the API key
        logger.info("CursorBackgroundProvider integration ready. Ensure ~/.flowback/cursor_api_key or CURSOR_API_KEY is present.")
    }

    public func uninstallIntegration() async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: keyStoragePath) {
            try? fm.removeItem(atPath: keyStoragePath)
            logger.info("Removed Cursor API key from \(self.keyStoragePath)")
        }
    }

    public func discoverActiveSessions() async -> [AgentSession] {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            return []
        }

        let pollStatus = tryBeginPolling()
        if !pollStatus.allowed {
            if let until = pollStatus.backoffDate {
                logger.info("Cursor Cloud Agents API in backoff until \(until); skipping discovery query")
            } else {
                logger.debug("Previous Cursor Cloud Agents poll still in progress; skipping overlapping poll")
            }
            return []
        }

        defer {
            finishPolling()
        }

        var allAgents: [CursorCloudAgent] = []
        var nextCursor: String? = nil
        let maxPages = 5 // Bounded pagination safeguard
        var pageCount = 0

        repeat {
            pageCount += 1
            var components = URLComponents(url: apiBaseURL.appendingPathComponent("agents"), resolvingAgainstBaseURL: false)
            if let cursor = nextCursor, !cursor.isEmpty {
                components?.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
            }
            guard let endpoint = components?.url else { break }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10.0

            do {
                let (data, response) = try await httpClient.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    logger.warning("Cursor Cloud Agents API returned invalid response object")
                    break
                }

                if http.statusCode == 200 {
                    recordSuccess()

                    let listResponse = try JSONDecoder().decode(CursorListAgentsResponse.self, from: data)
                    if let pageAgents = listResponse.agents {
                        allAgents.append(contentsOf: pageAgents)
                    }
                    nextCursor = listResponse.nextCursor
                } else if http.statusCode == 401 || http.statusCode == 403 {
                    recordAuthError("HTTP \(http.statusCode) unauthorized")
                    logger.error("Cursor Cloud Agents API authorization failure (HTTP \(http.statusCode))")
                    break
                } else if http.statusCode == 429 {
                    var backoffSeconds: Double = 30.0
                    if let retryHeader = http.value(forHTTPHeaderField: "Retry-After"),
                       let seconds = Double(retryHeader) {
                        backoffSeconds = min(max(seconds, 5.0), 300.0)
                    }
                    recordBackoff(seconds: backoffSeconds)
                    logger.warning("Cursor Cloud Agents API rate-limited (HTTP 429). Backing off for \(Int(backoffSeconds))s")
                    break
                } else if http.statusCode >= 500 {
                    recordBackoff(seconds: 15.0)
                    logger.warning("Cursor Cloud Agents API server error (HTTP \(http.statusCode)). Backing off for 15s")
                    break
                } else {
                    logger.warning("Cursor Cloud Agents API returned unexpected HTTP status \(http.statusCode)")
                    break
                }
            } catch {
                logger.error("Failed to query Cursor Cloud Agents API: \(error.localizedDescription)")
                break
            }
        } while nextCursor != nil && !nextCursor!.isEmpty && pageCount < maxPages

        var discovered: [AgentSession] = []
        for agent in allAgents {
            let rawStatus = (agent.status ?? "RUNNING").uppercased()
            let state: AgentState
            switch rawStatus {
            case "RUNNING", "PENDING", "IN_PROGRESS": state = .running
            case "COMPLETED", "FINISHED", "SUCCESS": state = .completed
            case "FAILED", "ERROR": state = .failed
            case "WAITING", "PAUSED": state = .waiting
            case "CONFIRMATION_REQUIRED": state = .permissionRequired
            case "CANCELLED", "ABORTED": state = .cancelled
            default: state = .running
            }

            let repoUrl = agent.repository ?? agent.repos?.first?.url
            let localWs = repoUrl.flatMap { findLocalWorkspace(forRepositoryURL: $0) }
            let remoteDestination = agent.prUrl ?? (repoUrl != nil ? repoUrl : "https://cursor.com/agents/\(agent.id)")

            var metadata: [String: String] = [
                "agentId": agent.id,
                "status": rawStatus
            ]
            if let r = repoUrl { metadata["repositoryUrl"] = r }
            if let b = agent.branchName ?? agent.targetRef ?? agent.repos?.first?.startingRef { metadata["branch"] = b }
            if let pr = agent.prUrl { metadata["prUrl"] = pr }
            if let runId = agent.latestRunId { metadata["latestRunId"] = runId }
            if let parent = agent.parentAgentId, !parent.isEmpty {
                metadata["parentSessionId"] = parent
                metadata["isSubagent"] = "true"
            }

            let origin = OriginContext(
                bundleIdentifier: localWs != nil ? "co.anysphere.cursor" : "com.apple.Safari",
                processIdentifier: 0,
                workspacePath: localWs ?? remoteDestination,
                provenance: .ipcExplicit,
                confidence: localWs != nil ? 0.9 : 0.7,
                restorationCapability: localWs != nil ? .workspaceWindow : (remoteDestination != nil ? .notificationFallbackOnly : .unsupported)
            )

            let session = AgentSession(
                id: AgentSessionID(agent.id),
                providerID: providerID,
                providerSessionID: agent.id,
                state: state,
                workspace: localWs ?? remoteDestination,
                originContext: origin,
                metadata: metadata
            )
            discovered.append(session)
        }

        return discovered
    }

    // MARK: - Local Workspace Matching Heuristic

    private func findLocalWorkspace(forRepositoryURL repoURL: String) -> String? {
        let cleanRepo = repoURL.replacingOccurrences(of: ".git", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let repoName = (cleanRepo as NSString).lastPathComponent
        guard !repoName.isEmpty else { return nil }

        let candidateRoots = [
            (NSHomeDirectory() as NSString).appendingPathComponent("workspace/projects"),
            (NSHomeDirectory() as NSString).appendingPathComponent("Projects"),
            (NSHomeDirectory() as NSString).appendingPathComponent("Developer"),
            (NSHomeDirectory() as NSString).appendingPathComponent("src")
        ]

        let fm = FileManager.default
        for root in candidateRoots {
            let directCandidate = (root as NSString).appendingPathComponent(repoName)
            if fm.fileExists(atPath: directCandidate) {
                return directCandidate
            }
        }

        return nil
    }
}
