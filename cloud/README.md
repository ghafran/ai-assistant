# Cloud orchestrator

The half that turns an understood intent into a done thing. It receives the **TaskSpec** the phone emits and runs **Claude (`claude-opus-4-8`) + a tool surface** to actually execute it — booking-style searches, sending messages — then writes the outcome back to memory.

```
phone  ──EmittedTask JSON──▶  POST /tasks  ──▶  toolRunner loop (Claude + tools)  ──▶  { reply, actions }
                                                        │
                                 get_contacts · get_calendar · draft_message · search_travel
```

Built on the official `@anthropic-ai/sdk` beta **tool runner** (`betaZodTool` + `client.beta.messages.toolRunner`), which drives the call → tool → result → repeat loop. Adaptive thinking is on.

## Files

- [src/orchestrator.ts](src/orchestrator.ts) — builds the prompt from the TaskSpec + profile, runs the tool loop, records the episode.
- [src/tools.ts](src/tools.ts) — the agent's tools. Mocks today, each shaped like its real counterpart (Twilio, a flights API, a calendar API) so swapping in production is a one-function change.
- [src/memory.ts](src/memory.ts) — authoritative `profile.json` (the phone syncs a subset) + append-only `episodic.jsonl`.
- [src/server.ts](src/server.ts) — `POST /tasks` HTTP endpoint.
- [src/demo.ts](src/demo.ts) — runs the two example flows with no phone needed.

## Run

Requires Node 23+ (uses native TypeScript type-stripping — no build step). Verified on Node 25.

```bash
cd cloud
npm install
export ANTHROPIC_API_KEY=sk-ant-...

npm run demo     # runs both example TaskSpecs end-to-end
# or
npm run server   # then POST a TaskSpec:
curl -s localhost:8787/tasks -X POST -H 'content-type: application/json' -d '{
  "spec": {"intent":"send_message","summary":"Tell Greg I'\''ll be 15 min late",
           "recipient":"g","messageBody":"Running ~15 min late — sorry!",
           "needsClarification":false,"confidence":0.93},
  "resolvedPhone":"+15551234567","createdAt":"2026-06-26T19:00:00Z"
}'
```

`npm run demo` exercises both vision flows:
- **"Text g, I'll be 15 min late"** → `get_contacts` resolves g→Greg, `get_calendar` grounds "our meeting", `send_sms` sends.
- **"Cheapest weekend trip to Florida"** → `search_travel` from your home airport, sorted by price per your budget preference.

## Messaging is native (no Twilio)

`draft_message` does **not** send. It returns the drafted message, and the orchestrator surfaces it as `compose` in the result; the phone opens the native Messages sheet pre-filled for the user to send. iOS can't send SMS silently — so this is also the confirmation gate for the one hard-to-reverse action.

## Tests

`npm test` runs the contract tests (profile resolution, tool surface builds, Swift-encoded payload parses) — no API key needed.

## What's mocked / next

- **`search_travel` is a stub.** A real flights/hotels API drops into its `run` body in [src/tools.ts](src/tools.ts).
- **Auth & multi-user.** Single local profile. Production needs per-user auth on `/tasks` and a real datastore behind `memory.ts`.
- **Result push.** The reply is returned synchronously; long tasks should run async and push back to the phone (the phone already fires a local notification on the reply it gets).
