// Flowback Universal Focus Orchestrator — OpenCode Plugin
// Subscribes to OpenCode lifecycle and tool events and emits normalized IPC events.

const net = require("net");
const fs = require("fs");
const path = require("path");
const os = require("os");

const SOCKET_PATH = process.env.FLOWBACK_SOCKET || path.join(os.homedir(), ".flowback", "flowback.sock");
const TOKEN_PATH = path.join(os.homedir(), ".flowback", ".session_token");

function getSessionToken() {
  try {
    if (fs.existsSync(TOKEN_PATH)) {
      return fs.readFileSync(TOKEN_PATH, "utf8").trim();
    }
  } catch (e) {
    // Session token optional for unauthenticated commands
  }
  return null;
}

function sendIPCEvent(eventData) {
  const token = getSessionToken();
  const request = {
    command: "hook",
    argument: "opencode",
    payload: Buffer.from(JSON.stringify(eventData)).toString("base64"),
    authToken: token
  };

  try {
    const client = net.createConnection({ path: SOCKET_PATH }, () => {
      client.write(JSON.stringify(request) + "\n");
    });
    client.on("data", () => {
      client.end();
    });
    client.on("error", () => {
      // Daemon offline: fail silently without blocking OpenCode workflow
    });
  } catch (e) {
    // Non-blocking fail-open
  }
}

/**
 * OpenCode Plugin Entrypoint
 * Compatible with @opencode/plugin v2 and v1 functional plugins.
 */
async function setup(ctx) {
  const abortController = new AbortController();
  const { signal } = abortController;

  const currentWorkspace = ctx?.workspace || process.cwd();

  // Helper to normalize and emit
  const emitLifecycle = (eventType, session, extra = {}) => {
    const sId = session?.id || session?.sessionId || "opencode-session";
    const dir = session?.directory || session?.project || currentWorkspace;
    const payload = {
      event: eventType,
      sessionId: sId,
      directory: dir,
      workspace: dir,
      timestamp: new Date().toISOString(),
      ...extra
    };
    sendIPCEvent(payload);
  };

  try {
    if (ctx?.event?.subscribe) {
      (async () => {
        try {
          for await (const event of ctx.event.subscribe({ signal })) {
            if (!event || !event.type) continue;
            switch (event.type) {
              case "session.created":
                emitLifecycle("session.created", event.session || event);
                break;
              case "session.idle":
              case "session.completed":
                emitLifecycle("session.idle", event.session || event);
                break;
              case "session.deleted":
                emitLifecycle("session.deleted", event.session || event);
                break;
              case "session.error":
                emitLifecycle("session.error", event.session || event, { error: event.error || "Session error" });
                break;
              case "tool.execute.before":
                emitLifecycle("tool.execute.before", event.session || {}, {
                  tool: {
                    name: event.toolName || event.name,
                    callId: event.callId,
                    requiresPermission: !!event.requiresConfirmation || !!event.requiresPermission
                  }
                });
                break;
              case "tool.execute.after":
                emitLifecycle("tool.execute.after", event.session || {}, {
                  tool: {
                    name: event.toolName || event.name,
                    callId: event.callId,
                    status: "finished"
                  }
                });
                break;
              case "session.status":
                if (event.status === "busy" || event.status === "running") {
                  emitLifecycle("session.running", event.session || event);
                }
                break;
            }
          }
        } catch (err) {
          if (!signal.aborted) {
            // Subscription ended
          }
        }
      })();
    }

    if (ctx?.session?.hook) {
      await ctx.session.hook("prompt", async (event) => {
        emitLifecycle("session.running", { id: event?.sessionId }, { action: "prompt" });
      });
    }
  } catch (setupError) {
    // Safe initialization failure
  }

  // Teardown function executed on plugin reload or unload
  return () => {
    abortController.abort();
  };
}

module.exports = {
  id: "flowback-opencode",
  name: "Flowback OpenCode Integration",
  setup
};

// Export for ES Module dynamic imports
module.exports.default = module.exports;
