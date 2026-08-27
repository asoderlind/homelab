import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import test from "node:test";
import {
  constantTimeEqual,
  extractSession,
  linearSignature,
  normalizeActivity,
  verifyLinearWebhook,
} from "./core.mjs";

if (!globalThis.crypto) {
  Object.defineProperty(globalThis, "crypto", { value: webcrypto });
}

test("validates Linear signatures and rejects stale requests", async () => {
  const body = new TextEncoder().encode('{"action":"created"}').buffer;
  const timestamp = "1787700000000";
  const signature = await linearSignature("secret", body);
  assert.equal(await verifyLinearWebhook("secret", body, signature, timestamp, 1787700000000), true);
  assert.equal(await verifyLinearWebhook("secret", body, signature, timestamp, 1787700060001), false);
  assert.equal(await verifyLinearWebhook("wrong", body, signature, timestamp, 1787700000000), false);
});

test("constant-time comparison rejects different lengths and contents", () => {
  assert.equal(constantTimeEqual("abc", "abc"), true);
  assert.equal(constantTimeEqual("abc", "abd"), false);
  assert.equal(constantTimeEqual("abc", "ab"), false);
});

test("extracts both top-level and nested agent sessions", () => {
  assert.deepEqual(
    extractSession({ action: "created", agentSession: { id: "s1" }, promptContext: "hello" }),
    { id: "s1", action: "created", promptContext: "hello", actorId: "" },
  );
  assert.equal(extractSession({ data: { agentSession: { id: "s2" } } })?.id, "s2");
  assert.equal(extractSession({ action: "created" }), null);
});

test("allows only Linear agent activity shapes", () => {
  assert.deepEqual(normalizeActivity({ type: "response", body: "done" }), {
    type: "response",
    body: "done",
  });
  assert.throws(() => normalizeActivity({ type: "prompt", body: "no" }));
});
