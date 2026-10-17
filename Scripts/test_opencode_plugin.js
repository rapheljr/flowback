#!/usr/bin/env node
/**
 * Test Harness for OpenCode Flowback Plugin
 * Exercises the actual flowback-opencode-plugin.js entrypoint with a mocked plugin context
 * and a temporary Unix domain socket server.
 */

const net = require("net");
const fs = require("fs");
const path = require("path");
const os = require("os");
const assert = require("assert");

const plugin = require("../Sources/FlowbackProviders/OpenCode/Plugin/flowback-opencode-plugin.js");

async function runTests() {
  console.log("================================================================");
  console.log("OpenCode Plugin Entry Point & IPC Serialization Test Suite");
  console.log("================================================================");

  let passed = 0;
  let failed = 0;

  function test(desc, fn) {
    try {
      fn();
      console.log(`  ✓ ${desc}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ FAILED: ${desc}`);
      console.error(`    ${err.message}`);
      failed++;
    }
  }

  async function asyncTest(desc, fn) {
    try {
      await fn();
      console.log(`  ✓ ${desc}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ FAILED: ${desc}`);
      console.error(`    ${err.message}`);
      failed++;
    }
  }

  // 1. Export structure
  test("Plugin exports id and name metadata", () => {
    assert.strictEqual(plugin.id, "flowback-opencode");
    assert.strictEqual(plugin.name, "Flowback OpenCode Integration");
    assert.strictEqual(typeof plugin.setup, "function");
  });

  // 2. Setup mock IPC server
  const testSocketDir = fs.mkdtempSync(path.join(os.tmpdir(), "flowback-test-sock-"));
  const socketPath = path.join(testSocketDir, "test.sock");
  process.env.FLOWBACK_SOCKET = socketPath;

  const receivedMessages = [];
  const server = net.createServer((socket) => {
    let buf = "";
    socket.on("data", (chunk) => {
      buf += chunk.toString("utf8");
      const lines = buf.split("\n");
      buf = lines.pop();
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const req = JSON.parse(line);
          if (req.payload) {
            const raw = Buffer.from(req.payload, "base64").toString("utf8");
            req.decodedPayload = JSON.parse(raw);
          }
          receivedMessages.push(req);
        } catch (e) {
          console.error("Failed to parse socket message", e);
        }
      }
      socket.write("OK\n");
    });
  });

  await new Promise((resolve) => server.listen(socketPath, resolve));

  try {
    // Queue of events to emit from mock subscription
    const eventQueue = [];
    let subscriberResolve = null;

    async function* eventGenerator(options) {
      while (!options?.signal?.aborted) {
        if (eventQueue.length > 0) {
          yield eventQueue.shift();
        } else {
          await new Promise((r) => {
            subscriberResolve = r;
          });
        }
      }
    }

    const mockCtx = {
      workspace: "/Users/abin/workspace/projects/flowback",
      event: {
        subscribe: (opts) => eventGenerator(opts)
      },
      session: {
        hook: async (name, handler) => {
          if (name === "prompt") {
            mockCtx._promptHandler = handler;
          }
        }
      }
    };

    const teardown = await plugin.setup(mockCtx);
    test("setup returns a teardown function", () => {
      assert.strictEqual(typeof teardown, "function");
    });

    function pushEvent(e) {
      eventQueue.push(e);
      if (subscriberResolve) {
        const r = subscriberResolve;
        subscriberResolve = null;
        r();
      }
    }

    // Emit session.created
    pushEvent({
      type: "session.created",
      session: { id: "sess-js-1", directory: "/Users/abin/workspace/projects/flowback" }
    });

    // Emit tool.execute.before with permission
    pushEvent({
      type: "tool.execute.before",
      session: { id: "sess-js-1" },
      toolName: "bash",
      callId: "c-101",
      requiresPermission: true
    });

    // Emit tool.execute.after
    pushEvent({
      type: "tool.execute.after",
      session: { id: "sess-js-1" },
      toolName: "bash",
      callId: "c-101"
    });

    // Emit session.idle (waiting for user prompt)
    pushEvent({
      type: "session.idle",
      session: { id: "sess-js-1" }
    });

    // Emit session.completed
    pushEvent({
      type: "session.completed",
      session: { id: "sess-js-1" }
    });

    // Emit session.deleted
    pushEvent({
      type: "session.deleted",
      session: { id: "sess-js-1" }
    });

    // Emit session.error
    pushEvent({
      type: "session.error",
      session: { id: "sess-js-1" },
      error: "IPC transport failure"
    });

    // Trigger prompt hook
    if (mockCtx._promptHandler) {
      await mockCtx._promptHandler({ sessionId: "sess-js-1" });
    }

    // Give asynchronous IPC deliveries 300ms to settle
    await new Promise((r) => setTimeout(r, 300));

    test("Received 8 normalized IPC messages at socket protocol boundary", () => {
      assert.strictEqual(receivedMessages.length, 8);
    });

    test("All messages have command = 'hook' and argument = 'opencode'", () => {
      for (const msg of receivedMessages) {
        assert.strictEqual(msg.command, "hook");
        assert.strictEqual(msg.argument, "opencode");
        assert.ok(msg.decodedPayload);
        assert.strictEqual(msg.decodedPayload.sessionId, "sess-js-1");
      }
    });

    const findMsg = (ev) => receivedMessages.find((m) => m.decodedPayload?.event === ev);

    test("session.created correctly serialized", () => {
      const msg = findMsg("session.created");
      assert.ok(msg, "Found session.created event");
      assert.strictEqual(msg.decodedPayload.directory, "/Users/abin/workspace/projects/flowback");
    });

    test("tool.execute.before with requiresPermission serialized", () => {
      const msg = findMsg("tool.execute.before");
      assert.ok(msg, "Found tool.execute.before event");
      assert.strictEqual(msg.decodedPayload.tool?.name, "bash");
      assert.strictEqual(msg.decodedPayload.tool?.requiresPermission, true);
    });

    test("tool.execute.after serialized", () => {
      const msg = findMsg("tool.execute.after");
      assert.ok(msg, "Found tool.execute.after event");
      assert.strictEqual(msg.decodedPayload.tool?.status, "finished");
    });

    test("session.idle distinct from session.completed", () => {
      const idleMsg = findMsg("session.idle");
      const compMsg = findMsg("session.completed");
      assert.ok(idleMsg, "Found session.idle event");
      assert.ok(compMsg, "Found session.completed event");
      assert.strictEqual(idleMsg.decodedPayload.event, "session.idle");
      assert.strictEqual(compMsg.decodedPayload.event, "session.completed");
    });

    test("session.deleted serialized", () => {
      const msg = findMsg("session.deleted");
      assert.ok(msg, "Found session.deleted event");
      assert.strictEqual(msg.decodedPayload.event, "session.deleted");
    });

    test("session.error preserves error message", () => {
      const msg = findMsg("session.error");
      assert.ok(msg, "Found session.error event");
      assert.strictEqual(msg.decodedPayload.error, "IPC transport failure");
    });

    test("session.running emitted on prompt hook", () => {
      const msg = findMsg("session.running");
      assert.ok(msg, "Found session.running event");
      assert.strictEqual(msg.decodedPayload.action, "prompt");
    });

    // Teardown plugin
    teardown();
    test("Teardown executes cleanly without throwing", () => {
      assert.ok(true);
    });

  } finally {
    server.close();
    try {
      fs.rmSync(testSocketDir, { recursive: true, force: true });
    } catch (e) {}
  }

  console.log("================================================================");
  console.log(`OpenCode Plugin JS Tests: ${passed} passed, ${failed} failed`);
  console.log("================================================================");

  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch((e) => {
  console.error(e);
  process.exit(1);
});
