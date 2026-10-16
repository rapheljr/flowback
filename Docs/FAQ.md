# Frequently Asked Questions (FAQ) & Limitations

---

## 1. How is Flowback different from a simple bash script that triggers macOS notifications?

Simple notification scripts (like `osascript -e 'display notification...'`) suffer from three major issues:
1. **No Context Memory:** They do not know which specific window, project directory, or application originally spawned the agent.
2. **Aggressive Focus Stealing:** If an agent script runs `open -a Editor`, it blindly steals your focus even while you are actively typing an email or chatting on Slack.
3. **No Multi-Agent Arbitration:** If three agents finish within 5 seconds of each other, naive scripts trigger rapid, disorienting window thrashing.

Flowback solves all three:
* Captures origin context (Window ID, process ID, workspace folder, start time).
* Senses system idle time (< 5-second typing threshold) before raising windows.
* Uses an Attention Arbiter with priority queues and focus cooldowns (1000ms) to aggregate simultaneous completions into a single digestible notification.

---

## 2. Does Flowback send any code, prompts, or telemetry to the cloud?

**No.** Flowback has zero outbound network requests, zero telemetry, zero analytics, and zero cloud dependencies. It runs completely offline on your Mac. All session data is stored locally in SQLite at `~/.flowback/flowback.sqlite`.

---

## 3. Why does Flowback request Accessibility permissions?

macOS security models require Accessibility (`AXUIElement`) authorization to inspect window titles and bring a specific background window to the front (`kAXRaiseAction`). Without Accessibility, Flowback can only activate the parent application as a whole, rather than the specific window of your project.

---

## 4. What happens if I use multiple macOS Spaces or full-screen apps?

By default, Flowback follows a `neverSwitchSpaces` policy: it does not switch virtual Spaces abruptly, because sudden Space transitions can be highly disorienting. Instead, it displays an actionable notification banner on your current Space with a `[Focus Window]` action button. You can change this behavior in Settings if you prefer automatic Space jumping.

---

## 5. Can I use Flowback with custom scripts or unsupported agents?

**Yes.** Any script or custom agent can emit events using the Generic Hook Protocol:
```bash
flowback emit '{"schemaVersion":1,"event":"agent.completed","provider":"custom","sessionId":"my-run","workspace":"/path/to/project"}'
```
Or via a one-line curl/socat call to `~/.flowback/flowback.sock`.
