import Foundation
import AppKit
import FlowbackCore
import FlowbackStorage
import FlowbackFocus
import FlowbackProviders
import FlowbackServer
import FlowbackTestHarness

// MARK: - Extended Audit Remediation Verification Suites (F-14 through F-22)

@MainActor
func runExtendedRemediationSuites() async {
    print("\n================================================================")
    print("FLOWBACK EXTENDED AUDIT REMEDIATION SUITES (F-14 to F-22)")
    print("================================================================")

    // MARK: - F-14: AsyncProcessRunner Bounded Streaming, Pipe Deadlock Immunity, and Task Leak Prevention
    await testGroup("F-14: AsyncProcessRunner Bounded Streaming & Watchdog Safety") {
        // 1. Process producing large stdout stream (>128KB) completes without pipe buffer deadlock
        let largeOutputResult = try? await AsyncProcessRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "for i in $(seq 1 3000); do echo '01234567890123456789012345678901234567890123456789'; done"],
            timeoutSeconds: 3.0,
            maxOutputBytes: 262_144
        )
        assertTest(largeOutputResult != nil, "F-14: Process with >150KB output completes without hanging")
        assertTest(largeOutputResult?.exitCode == 0, "F-14: Process exit status is 0")
        assertTest((largeOutputResult?.stdout.count ?? 0) > 100_000, "F-14: Successfully drained large output across pipe buffer boundaries")

        // 2. Output capping at maxOutputBytes
        let cappedResult = try? await AsyncProcessRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "for i in $(seq 1 500); do echo '1234567890'; done"],
            timeoutSeconds: 2.0,
            maxOutputBytes: 100
        )
        assertTest(cappedResult != nil, "F-14: Capped execution completes")
        assertTest((cappedResult?.stdout.utf8.count ?? 0) <= 100, "F-14: Output byte count strictly bounded by maxOutputBytes")

        // 3. Fast completion does not leak running watchdog task
        let fastResult = try? await AsyncProcessRunner.run(
            executablePath: "/bin/echo",
            arguments: ["fast"],
            timeoutSeconds: 10.0
        )
        assertTest(fastResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "fast",
                   "F-14: Fast command completes immediately without waiting for watchdog timeout")

        // 4. Adversarial test: Orphaned pipe / inherited stdout from background child must not hang or exceed timeout
        let orphanStart = Date()
        let orphanResult = try? await AsyncProcessRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "(sleep 4 &); echo 'orphaned'"],
            timeoutSeconds: 1.5
        )
        let orphanElapsed = Date().timeIntervalSince(orphanStart)
        assertTest(orphanResult != nil, "F-14 Adversarial: Subprocess with background child completed")
        assertTest(orphanElapsed < 3.0, "F-14 Adversarial: Orphaned pipe did not hang waiting for background sleep: took \(orphanElapsed)s")
    }

    // MARK: - F-15: UIEventCoalescer Flush Awaits In-Flight Execution
    await testGroup("F-15: UIEventCoalescer Flush Synchronization") {
        var actionExecuted = false
        var executionFinished = false
        let coalescer = UIEventCoalescer(interval: 0.05) {
            actionExecuted = true
            try? await Task.sleep(nanoseconds: 30_000_000)
            executionFinished = true
        }

        coalescer.schedule()
        // Wait for execution to start
        while !coalescer.isCurrentlyExecuting && coalescer.executionCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        // flush while action is in flight: flush MUST await completion of active execution
        await coalescer.flush()
        assertTest(actionExecuted, "F-15: Action was initiated")
        assertTest(executionFinished, "F-15: flush() blocked until in-flight execution completed")
        assertTest(!coalescer.isCurrentlyExecuting, "F-15: Coalescer isCurrentlyExecuting is false after flush")
    }

    // MARK: - F-16: SessionManager Evicted Session Resurrection from Storage
    await testGroup("F-16: Session Eviction & Storage Resurrection") {
        let tempDb = NSTemporaryDirectory() + "flowback_f16_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let repo = SessionRepository(db: db)
        let sessionMgr = SessionManager()
        await sessionMgr.setStorageDelegate(repo)

        let sessionID = AgentSessionID("sess-evict-123")
        let origin = OriginContext(bundleIdentifier: "com.apple.Terminal", processIdentifier: 1234, windowIdentifier: 999)
        
        // Create and complete session
        let initialEvent = AgentEvent(
            providerID: .antigravityCLI,
            sessionID: sessionID,
            type: .agentStarted,
            workspace: "/Users/test/workspace",
            origin: origin
        )
        _ = await sessionMgr.handleEvent(initialEvent)
        
        let finishEvent = AgentEvent(
            providerID: .antigravityCLI,
            sessionID: sessionID,
            type: .agentCompleted,
            workspace: "/Users/test/workspace"
        )
        _ = await sessionMgr.handleEvent(finishEvent)

        // Force eviction from in-memory cache by simulating cold start / memory cap
        // Verify session exists in DB
        let stored = try? await repo.fetchSession(id: sessionID)
        assertTest(stored != nil, "F-16: Session was stored in database")
        assertTest(stored?.originContext?.windowIdentifier == 999, "F-16: Stored session retains window ID")

        // Create new session manager with same storage to simulate post-eviction event
        let coldManager = SessionManager()
        await coldManager.setStorageDelegate(repo)
        
        // Receive title update event for cold session (where event has no origin attached)
        let titleUpdateEvent = AgentEvent(
            providerID: .antigravityCLI,
            sessionID: sessionID,
            type: .conversationTitleUpdated,
            conversationTitle: "Updated Multi-Turn Conversation"
        )
        let resurrected = await coldManager.handleEvent(titleUpdateEvent)
        assertTest(resurrected.id == sessionID, "F-16: Resurrected session ID matches")
        assertTest(resurrected.workspace == "/Users/test/workspace", "F-16: Original workspace preserved from storage")
        assertTest(resurrected.originContext?.windowIdentifier == 999, "F-16: Original window ID preserved from storage")
        assertTest(resurrected.originContext?.bundleIdentifier == "com.apple.Terminal", "F-16: Original bundle ID preserved from storage")
        assertTest(resurrected.conversationTitle == "Updated Multi-Turn Conversation", "F-16: Title updated on resurrected session")

        // Concurrent resurrection of cold session: multiple tasks handle events for same cold session
        let concurrentSessID = AgentSessionID("sess-concurrent-resurrect")
        let concurrentSession = AgentSession(id: concurrentSessID, providerID: .antigravityCLI, state: .completed, workspace: "/Users/test/concurrent")
        try? await repo.saveSession(concurrentSession)

        let concurrentMgr = SessionManager()
        await concurrentMgr.setStorageDelegate(repo)

        await withTaskGroup(of: AgentSession.self) { group in
            for i in 1...5 {
                group.addTask {
                    let evt = AgentEvent(
                        providerID: .antigravityCLI,
                        sessionID: concurrentSessID,
                        type: .conversationTitleUpdated,
                        conversationTitle: "Update \(i)"
                    )
                    return await concurrentMgr.handleEvent(evt)
                }
            }
        }
        let finalSess = await concurrentMgr.getSession(id: concurrentSessID)
        assertTest(finalSess?.workspace == "/Users/test/concurrent", "F-16: Concurrent resurrection preserves stored workspace")
    }

    // MARK: - F-17: IPCClient Socket Timeout Configuration
    await testGroup("F-17: IPCClient Socket Options & Timeouts") {
        let client = IPCClient(socketPath: "/tmp/nonexistent-test.sock", timeoutSeconds: 0.5)
        assertTest(client.timeoutSeconds == 0.5, "F-17: Configurable timeoutSeconds property")
        
        // Nonexistent socket fails fast with ECONNREFUSED or ENOENT, not hanging
        var didCatch = false
        do {
            _ = try client.send(command: "ping")
        } catch {
            didCatch = true
        }
        assertTest(didCatch, "F-17: Client gracefully throws on connection failure without hanging")
    }

    // MARK: - F-18: EventRepository Explicit Column Projection & Mapping
    await testGroup("F-18: EventRepository Column Projection") {
        let tempDb = NSTemporaryDirectory() + "flowback_f18_\(UUID().uuidString).sqlite"
        let db = await RecoveryManager.shared.initializeStorage(path: tempDb)
        let sessionRepo = SessionRepository(db: db)
        let eventRepo = EventRepository(db: db)

        assertTest(EventRepository.eventColumnsProjection.contains("id"), "F-18: Projection contains id")
        assertTest(EventRepository.eventColumnsProjection.contains("timestamp"), "F-18: Projection contains timestamp")
        assertTest(EventRepository.eventColumnsProjection.contains("metadata_json"), "F-18: Projection contains metadata_json")

        let sessID = AgentSessionID("sess-evt-proj")
        let session = AgentSession(id: sessID, providerID: .antigravityCLI, state: .running, workspace: "/Users/test/project")
        try? await sessionRepo.saveSession(session)

        let evt = AgentEvent(
            providerID: .antigravityCLI,
            sessionID: sessID,
            type: .agentStarted,
            workspace: "/Users/test/project",
            metadata: ["testKey": "testVal"]
        )
        try? await eventRepo.saveEvent(evt)
        let fetched = try? await eventRepo.fetchEvents(for: sessID)
        assertTest(fetched?.count == 1, "F-18: Successfully fetched saved event via explicit projection")
        assertTest(fetched?.first?.metadata["testKey"] == "testVal", "F-18: Correctly mapped metadata through explicit projection")
    }

    // MARK: - F-19: Provider Version Probe Caching & Background Activity
    await testGroup("F-19: Background Subprocess & Maintenance Throttling") {
        let provider = AntigravityCLIProvider()
        // Call checkHealth twice
        let health1 = await provider.checkHealth()
        let health2 = await provider.checkHealth()
        assertTest(health1.providerID == .antigravityCLI, "F-19: First health check succeeded")
        assertTest(health2.providerID == .antigravityCLI, "F-19: Second health check succeeded with cache")
        assertTest(health1.version == health2.version, "F-19: Version consistent across cached invocations")
    }

    // MARK: - F-20: Secret Sanitization Across Events & Timeline
    await testGroup("F-20: SecretSanitizer Redaction Invariant") {
        let sensitiveMetadata: [String: String] = [
            "sessionID": "sess-safe-123",
            "conversationId": "conv-safe-456",
            "apiKey": "sk-proj-1234567890abcdef12345678",
            "anthropic_api_key": "sk-ant-api03-1234567890abcdef",
            "user_token": "ghp_1234567890abcdef1234567890abcdef",
            "database_password": "supersecretpassword123",
            "normalNote": "All systems operational"
        ]
        
        let sanitized = SecretSanitizer.sanitizeMetadata(sensitiveMetadata)
        assertTest(sanitized["sessionID"] == "sess-safe-123", "F-20: Non-sensitive sessionID preserved")
        assertTest(sanitized["conversationId"] == "conv-safe-456", "F-20: Non-sensitive conversationId preserved")
        assertTest(sanitized["apiKey"] == "[REDACTED]", "F-20: apiKey redacted")
        assertTest(sanitized["anthropic_api_key"] == "[REDACTED]", "F-20: anthropic_api_key redacted")
        assertTest(sanitized["user_token"] == "[REDACTED]", "F-20: user_token redacted")
        assertTest(sanitized["database_password"] == "[REDACTED]", "F-20: database_password redacted")
        assertTest(sanitized["normalNote"] == "All systems operational", "F-20: Normal note preserved")

        // Free-text string redaction
        let bearerText = "Request failed with header: Bearer ya29.a0AfH6SMD_secret_token_12345"
        let cleanBearer = SecretSanitizer.sanitizeText(bearerText)
        assertTest(!cleanBearer.contains("ya29"), "F-20: Bearer token value stripped from free text")
        assertTest(cleanBearer.contains("Bearer [REDACTED]"), "F-20: Bearer token sanitized to Bearer [REDACTED]")

        // PEM private key redaction
        let pemKey = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA0m...\n-----END RSA PRIVATE KEY-----"
        let cleanPem = SecretSanitizer.sanitizeText(pemKey)
        assertTest(!cleanPem.contains("MIIEowIBAAKCAQEA0m"), "F-20: Private key payload stripped")
        assertTest(cleanPem.contains("[REDACTED_PRIVATE_KEY_BLOCK]"), "F-20: Private key block replaced with placeholder")

        // Query parameters
        let urlWithSecret = "https://api.example.com/v1?token=ghp_secretToken123456&client_secret=topsecret"
        let cleanURL = SecretSanitizer.sanitizeText(urlWithSecret)
        assertTest(!cleanURL.contains("ghp_secretToken123456"), "F-20: Query token stripped")
        assertTest(!cleanURL.contains("topsecret"), "F-20: Query client_secret stripped")
        assertTest(cleanURL.contains("token=[REDACTED]"), "F-20: Query token replaced with token=[REDACTED]")

        // AgentEvent automatic metadata & title/summary redaction
        let event = AgentEvent(
            providerID: .antigravityCLI,
            sessionID: AgentSessionID("s1"),
            type: .agentRunning,
            metadata: ["secretToken": "secret_abc123"],
            conversationTitle: "Debug with token=secret12345678",
            taskSummary: "Execute task with Bearer eyJhbGciOi..."
        )
        assertTest(event.metadata["secretToken"] == "[REDACTED]", "F-20: AgentEvent automatically scrubs sensitive metadata")
        assertTest(event.conversationTitle?.contains("secret12345678") == false, "F-20: Event title sanitized")
        assertTest(event.taskSummary?.contains("eyJhbGciOi") == false, "F-20: Event summary sanitized")
    }

    // MARK: - F-21: macOS Focus Unhide & Expanded Terminal Adapter Support
    await testGroup("F-21: macOS Focus & Terminal Emulator Coverage") {
        let adapter = TerminalAdapter()
        assertTest(adapter.canHandle(bundleIdentifier: "com.apple.Terminal"), "F-21: Supports Terminal.app")
        assertTest(adapter.canHandle(bundleIdentifier: "com.googlecode.iterm2"), "F-21: Supports iTerm2")
        assertTest(adapter.canHandle(bundleIdentifier: "com.mitchellh.ghostty"), "F-21: Supports Ghostty")
        assertTest(adapter.canHandle(bundleIdentifier: "org.alacritty"), "F-21: Supports Alacritty")
        assertTest(adapter.canHandle(bundleIdentifier: "net.kovidgoyal.kitty"), "F-21: Supports Kitty")
        assertTest(adapter.canHandle(bundleIdentifier: "com.github.wez.wezterm"), "F-21: Supports WezTerm")
    }

    // MARK: - F-22: Modern macOS Notification Settings Deep-Link
    await testGroup("F-22: Notification Settings Extension Deep-Link") {
        let modernURL = PermissionManager.modernNotificationSettingsURL.absoluteString
        let expectedModern = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        assertTest(modernURL == expectedModern, "F-22: Modern notification settings extension URL defined")
        let standardURL = PermissionManager.notificationSettingsURL.absoluteString
        let expectedStandard = "x-apple.systempreferences:com.apple.preference.notifications"
        assertTest(standardURL == expectedStandard, "F-22: Standard notification settings preference URL defined")
    }
}
