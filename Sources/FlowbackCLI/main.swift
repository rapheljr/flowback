import Foundation
import FlowbackCore

let client = IPCClient()
let args = CommandLine.arguments

func printHelp() {
    print("""
    Flowback — Universal macOS AI Agent Context & Focus Manager CLI
    
    Usage:
      flowback <command> [arguments]
      
    Commands:
      status                    Show daemon status and summary
      refresh                   Scan for active agents and refresh status
      agents                    List currently active agent sessions
      sessions                  List recent agent sessions and timelines
      doctor                    Run diagnostics and permission checks
      focus [session-id]        Manually restore focus to a session origin
      focus-lock [duration]     Toggle or set focus lock (e.g. 15m, 30m, 1h, off)
      providers                 List detected agent providers and health
      test-focus                Simulate focus restoration evaluation
      test-notification         Send a test macOS actionable notification
      hook <provider>           Process hook input from stdin (for Antigravity, Claude, etc.)
      emit <json>               Emit a generic agent event into Flowback
      help, -h                  Display this help message
    """)
}

guard args.count > 1 else {
    printHelp()
    exit(0)
}

let command = args[1]

switch command {
case "help", "-h", "--help":
    printHelp()
    exit(0)

case "version", "-v", "--version":
    print("flowback v1.0.0 (build 1) — CLI tool for Flowback Context & Focus Orchestrator")
    exit(0)

case "refresh":
    do {
        let resp = try client.send(command: "refresh")
        print(resp.message)
        if let data = resp.data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let active = json["activeSessions"] as? [[String: Any]], !active.isEmpty {
                print("Active Agents:")
                for a in active {
                    let proj = a["projectName"] as? String ?? "unknown"
                    let prov = a["provider"] as? String ?? "unknown"
                    let st = a["state"] as? String ?? "running"
                    print("  • [\(st)] \(prov) — \(proj)")
                }
            } else {
                print("No active agents running.")
            }
        }
    } catch {
        print("Flowback daemon is not running.")
        exit(1)
    }

case "hook":
    let providerName = args.count > 2 ? args[2] : "antigravity"
    // Read stdin
    let inputData = FileHandle.standardInput.readDataToEndOfFile()
    do {
        let response = try client.send(command: "hook", argument: providerName, payload: inputData)
        if let data = response.data, let str = String(data: data, encoding: .utf8) {
            print(str)
        } else {
            print("{\"decision\":\"allow\"}")
        }
    } catch {
        // Safe degradation: if Flowback daemon isn't running, never fail the agent's hook!
        if let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
           (json["invocationNum"] != nil && json["terminationReason"] == nil) || json["hook_event_name"] as? String == "PreInvocation" {
            print("{\"injectSteps\":[]}")
        } else {
            print("{\"decision\":\"allow\"}")
        }
    }
    exit(0)

case "emit":
    guard args.count > 2 else {
        print("Error: emit requires a JSON string argument")
        exit(1)
    }
    let jsonStr = args[2]
    guard let payload = jsonStr.data(using: .utf8) else {
        print("Error: invalid UTF-8 string")
        exit(1)
    }
    do {
        let resp = try client.send(command: "emit", payload: payload)
        print(resp.message)
        exit(resp.success ? 0 : 1)
    } catch {
        print("Error communicating with Flowback daemon: \(error.localizedDescription)")
        exit(1)
    }

case "status":
    do {
        let resp = try client.send(command: "status")
        print("Flowback Status: \(resp.message)")
        if let data = resp.data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("----------------------------------------")
            for (k, v) in json.sorted(by: { $0.key < $1.key }) {
                print("  \(k): \(v)")
            }
        }
    } catch {
        print("Flowback is NOT running. (Could not connect to ~/.flowback/flowback.sock)")
        print("Launch the Flowback app to begin managing AI agent focus.")
        exit(1)
    }

case "agents":
    do {
        let resp = try client.send(command: "agents")
        print(resp.message)
        if let data = resp.data, let sessions = try? JSONDecoder().decode([AgentSession].self, from: data) {
            if sessions.isEmpty {
                print("No active agent sessions.")
            } else {
                for s in sessions {
                    print("• [\(s.state.rawValue)] \(s.providerID.rawValue) — \(s.projectName) (Started: \(s.formattedDuration) ago)")
                    if let origin = s.originContext {
                        print("    Origin: \(origin.displayLabel) (PID: \(origin.processIdentifier))")
                    }
                }
            }
        }
    } catch {
        print("Error: Flowback daemon is not running.")
        exit(1)
    }

case "sessions":
    do {
        let resp = try client.send(command: "sessions")
        print(resp.message)
        if let data = resp.data, let sessions = try? JSONDecoder().decode([AgentSession].self, from: data) {
            for s in sessions {
                print("• [\(s.state.rawValue)] \(s.providerID.rawValue) — \(s.projectName) [ID: \(s.id.rawValue.prefix(8))]")
                if let origin = s.originContext {
                    print("    Origin: \(origin.displayLabel)")
                }
            }
        }
    } catch {
        print("Error: Flowback daemon is not running.")
        exit(1)
    }

case "doctor", "providers":
    do {
        let resp = try client.send(command: "doctor")
        if let data = resp.data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("========================================")
            print("Flowback Doctor Diagnostics")
            print("========================================")
            if let perms = json["permissions"] as? [String: Any] {
                print("\nPermissions:")
                for (k, v) in perms {
                    let flag = (v as? Bool) == true ? "✓" : "✗"
                    print("  \(flag) \(k)")
                }
            }
            if let provs = json["providers"] as? [[String: Any]] {
                print("\nAgent Providers:")
                for p in provs {
                    let name = (p["name"] as? String) ?? ""
                    let status = (p["status"] as? String) ?? ""
                    let tier = (p["supportLevel"] as? String) ?? "adapter"
                    let isInst = (p["installed"] as? Bool) == true ? "✓" : "○"
                    print("  \(isInst) \(name) [\(tier)]: \(status)")
                }
            }
        } else {
            print(resp.message)
        }
    } catch {
        print("Error: Flowback daemon is not running.")
        exit(1)
    }

case "focus":
    let targetID = args.count > 2 ? args[2] : nil
    do {
        let resp = try client.send(command: "focus", argument: targetID)
        print(resp.message)
        exit(resp.success ? 0 : 1)
    } catch {
        print("Error: Flowback daemon is not running.")
        exit(1)
    }

case "focus-lock":
    let durationArg = args.count > 2 ? args[2] : nil
    do {
        let resp = try client.send(command: "focus-lock", argument: durationArg)
        print(resp.message)
        exit(resp.success ? 0 : 1)
    } catch {
        print("Error: Flowback daemon is not running.")
        exit(1)
    }

case "test-focus":
    do {
        let resp = try client.send(command: "test-focus")
        print(resp.message)
    } catch {
        print("Error: Flowback daemon is not running.")
        exit(1)
    }

case "test-notification":
    do {
        let resp = try client.send(command: "test-focus")
        print("Dispatched test notification request: \(resp.message)")
    } catch {
        print("Error: Flowback daemon is not running.")
        exit(1)
    }

default:
    print("Unknown command '\(command)'. Run 'flowback help' for available commands.")
    exit(1)
}
