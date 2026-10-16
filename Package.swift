// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// In macOS environments where only Command Line Tools are installed without Xcode.app,
// Apple omits the XCTest.framework from the CLT SDK.
// When running in CI (GitHub Actions) or with Xcode installed, XCTest is fully available.
let isXCTestAvailable: Bool = {
    if ProcessInfo.processInfo.environment["ENABLE_XCTEST"] == "1" ||
       ProcessInfo.processInfo.environment["CI"] != nil {
        return true
    }
    let xcodeDefault = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
    return FileManager.default.fileExists(atPath: xcodeDefault)
}()

var packageTargets: [Target] = [
    // Core domain models, state machine, event bus, policies, interfaces
    .target(
        name: "FlowbackCore",
        dependencies: [],
        path: "Sources/FlowbackCore"
    ),
    
    // SQLite persistence engine and migrations
    .target(
        name: "FlowbackStorage",
        dependencies: ["FlowbackCore"],
        path: "Sources/FlowbackStorage"
    ),
    
    // Window, application, workspace focus and user intent engine
    .target(
        name: "FlowbackFocus",
        dependencies: ["FlowbackCore"],
        path: "Sources/FlowbackFocus"
    ),
    
    // Agent providers (Antigravity, Claude Code, Codex, GenericHook, etc.)
    .target(
        name: "FlowbackProviders",
        dependencies: ["FlowbackCore"],
        path: "Sources/FlowbackProviders"
    ),
    
    // Unix domain socket IPC server & hook dispatcher
    .target(
        name: "FlowbackServer",
        dependencies: [
            "FlowbackCore",
            "FlowbackFocus",
            "FlowbackProviders",
            "FlowbackStorage"
        ],
        path: "Sources/FlowbackServer"
    ),
    
    // Native macOS UserNotifications integration
    .target(
        name: "FlowbackNotifications",
        dependencies: ["FlowbackCore"],
        path: "Sources/FlowbackNotifications"
    ),
    
    // SwiftUI Dashboard & AppKit Menu Bar UI
    .target(
        name: "FlowbackUI",
        dependencies: [
            "FlowbackCore",
            "FlowbackFocus",
            "FlowbackProviders",
            "FlowbackStorage",
            "FlowbackNotifications"
        ],
        path: "Sources/FlowbackUI"
    ),
    
    // Main macOS application executable
    .executableTarget(
        name: "FlowbackApp",
        dependencies: [
            "FlowbackCore",
            "FlowbackStorage",
            "FlowbackFocus",
            "FlowbackProviders",
            "FlowbackServer",
            "FlowbackNotifications",
            "FlowbackUI"
        ],
        path: "Sources/FlowbackApp"
    ),
    
    // Native CLI binary `flowback`
    .executableTarget(
        name: "FlowbackCLI",
        dependencies: [
            "FlowbackCore"
        ],
        path: "Sources/FlowbackCLI"
    ),
    
    // Test harness & simulation fixtures
    .target(
        name: "FlowbackTestHarness",
        dependencies: [
            "FlowbackCore",
            "FlowbackFocus",
            "FlowbackProviders"
        ],
        path: "Sources/FlowbackTestHarness"
    ),
    
    // Standalone verification & acceptance test runner executable
    .executableTarget(
        name: "FlowbackTestRunner",
        dependencies: [
            "FlowbackCore",
            "FlowbackStorage",
            "FlowbackFocus",
            "FlowbackProviders",
            "FlowbackServer",
            "FlowbackTestHarness"
        ],
        path: "Sources/FlowbackTestRunner"
    )
]

if isXCTestAvailable {
    packageTargets.append(contentsOf: [
        .testTarget(
            name: "FlowbackCoreTests",
            dependencies: ["FlowbackCore"],
            path: "Tests/FlowbackCoreTests"
        ),
        .testTarget(
            name: "FlowbackStorageTests",
            dependencies: [
                "FlowbackStorage",
                "FlowbackCore"
            ],
            path: "Tests/FlowbackStorageTests"
        ),
        .testTarget(
            name: "FlowbackFocusTests",
            dependencies: [
                "FlowbackFocus",
                "FlowbackCore"
            ],
            path: "Tests/FlowbackFocusTests"
        ),
        .testTarget(
            name: "FlowbackProviderTests",
            dependencies: [
                "FlowbackProviders",
                "FlowbackCore"
            ],
            path: "Tests/FlowbackProviderTests"
        ),
        .testTarget(
            name: "FlowbackIntegrationTests",
            dependencies: [
                "FlowbackCore",
                "FlowbackStorage",
                "FlowbackFocus",
                "FlowbackProviders",
                "FlowbackServer",
                "FlowbackTestHarness"
            ],
            path: "Tests/FlowbackIntegrationTests"
        )
    ])
}

let package = Package(
    name: "Flowback",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Flowback", targets: ["FlowbackApp"]),
        .executable(name: "flowback-cli", targets: ["FlowbackCLI"]),
        .executable(name: "FlowbackTestRunner", targets: ["FlowbackTestRunner"]),
        .library(name: "FlowbackCore", targets: ["FlowbackCore"]),
        .library(name: "FlowbackStorage", targets: ["FlowbackStorage"]),
        .library(name: "FlowbackFocus", targets: ["FlowbackFocus"]),
        .library(name: "FlowbackProviders", targets: ["FlowbackProviders"]),
        .library(name: "FlowbackServer", targets: ["FlowbackServer"]),
        .library(name: "FlowbackNotifications", targets: ["FlowbackNotifications"]),
        .library(name: "FlowbackUI", targets: ["FlowbackUI"]),
        .library(name: "FlowbackTestHarness", targets: ["FlowbackTestHarness"])
    ],
    dependencies: [],
    targets: packageTargets
)
