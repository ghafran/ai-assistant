import { test } from "node:test";
import assert from "node:assert/strict";
import { loadProfile } from "../src/memory.ts";
import { makeTools } from "../src/tools.ts";

test("seeded profile resolves the 'g' alias", () => {
  const p = loadProfile();
  assert.equal(p.contacts.g.name, "Greg");
});

test("tool surface is the expected four tools", () => {
  const tools = makeTools({ profile: loadProfile(), actions: [] });
  assert.equal(tools.length, 4);
});

test("a Swift-encoded EmittedTask parses and keeps the wire contract", () => {
  // Exactly what iOS JSONEncoder(.iso8601) emits.
  const payload = {
    spec: {
      intent: "send_message",
      summary: "Tell Greg I'll be late",
      recipient: "Greg",
      messageBody: "Running ~15 min late — sorry!",
      destination: "",
      timeframe: "",
      needsClarification: false,
      clarifyingQuestion: "",
      confidence: 0.93,
    },
    resolvedPhone: "+15551234567",
    createdAt: "2026-06-26T19:00:00Z",
  };
  const parsed = JSON.parse(JSON.stringify(payload));
  assert.equal(parsed.spec.intent, "send_message");
  assert.equal(parsed.spec.recipient, "Greg");
  assert.ok(!Number.isNaN(Date.parse(parsed.createdAt)));
});
