# ai-assistant

An **ambient agent**: press a small (eventually wearable, camera-equipped) button, have a short conversation, and it spins up agents to carry out goals — "find the cheapest weekend trip to Florida," "text g that I'll be 15 minutes late."

**Design split:** the conversation runs **on-device** (low latency, privacy, brief mic/camera use); the **task agents run in the cloud** (browsing, APIs, long-running work). The two meet at a structured [`TaskSpec`](schema/taskspec.schema.json).

```
[ button: mic+cam+BLE ] ─wake─▶ [ phone: on-device loop ] ─TaskSpec─▶ [ cloud: Claude + tools + memory ]
```

## Status

- ✅ [`ios/`](ios/) — on-device conversation loop (SwiftUI + Speech + AVFoundation + FoundationModels for the LLM + **FastVLM/MLX vision, on-device**). Emits a TaskSpec and **POSTs it to the cloud**, then speaks back the agent's result. **Builds green** (iOS + watchOS + tests).
- ✅ [`cloud/`](cloud/) — orchestrator (`claude-opus-4-8` + tool runner). Consumes the TaskSpec, runs the travel-search / send-message agents, returns the result.
- ✅ **Phone ↔ cloud loop connected** ([`CloudClient.swift`](ios/AmbientAgent/Core/CloudClient.swift) → `POST /tasks`).
- ✅ **Apple Watch wake button** ([`AmbientAgentWatch/`](ios/AmbientAgentWatch/) over WatchConnectivity) — the physical trigger.
- ✅ **Auto-endpointing (VAD)**, **native Contacts + Calendar**, **native Messages** (no Twilio — agent drafts, user taps Send), **local notifications**, **model pre-warming**, **unit tests** (iOS + cloud). **← just completed**
- 🟡 Memory service — authoritative `cloud/data/profile.json` + episodic log exist; still needs per-user auth and a real datastore + sync to the on-device cache.

**To build and run everything, see [BUILD.md](BUILD.md).** Component details: [ios/README.md](ios/README.md), [cloud/README.md](cloud/README.md).
