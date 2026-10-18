import Foundation
import AppKit
import FlowbackCore

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    Flowback — macOS Focus & Context Orchestrator
    
    Usage:
      Flowback [options]
      
    Execution Modes:
      1. Packaged Menu-Bar App (Recommended):
         Launch 'dist/Flowback.app' or '/Applications/Flowback.app'
         Full AppKit menu-bar UI, UserNotifications, and background orchestration.
         
      2. Headless Service / Daemon:
         Flowback --daemon (or --headless)
         Runs central focus engine, SQLite persistence, and Unix domain socket IPC
         without status bar item. Notifications degrade safely to system logs.
         
      3. Native CLI Tool:
         Use 'flowback' (dist/bin/flowback) to inspect agents, check doctor status,
         manage focus lock, or dispatch hook events over IPC.
         
    Options:
      --daemon, -d        Run as headless background service
      --headless          Run without menu-bar item
      --version, -v       Display version and build info
      --help, -h          Display this help message
    """)
    exit(0)
}

if args.contains("--version") || args.contains("-v") {
    let version = FlowbackVersion.current
    let build = FlowbackVersion.currentBuild
    print("Flowback v\(version) (build \(build)) — Focus & Context Orchestrator for macOS")
    exit(0)
}

let isHeadless = args.contains("--daemon") || args.contains("-d") || args.contains("--headless")
FlowbackService.shared.isHeadless = isHeadless

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
