# Build & run

How to get the whole system running for testing: the **cloud orchestrator** (Node) and the **iOS + watchOS app** (Xcode).

```
Apple Watch / on-screen button → iPhone app (on-device ASR + VLM + LLM) → POST /tasks → cloud agents
```

## Prerequisites

- **Xcode 26+** (full app — `/Applications/Xcode.app`). Command Line Tools alone can't build the app or use FoundationModels.
- **XcodeGen** — `brew install xcodegen` (generates the `.xcodeproj` from `ios/project.yml`).
- **Node 23+** (verified on 25) — runs the TypeScript cloud with no build step.
- An **`ANTHROPIC_API_KEY`** for the cloud orchestrator.
- Recommended: a **real iPhone** (A17 Pro+ with Apple Intelligence enabled) and a paired **Apple Watch**.

---

## One-time toolchain setup

Xcode ships but the toolchain may still point at Command Line Tools. Switch it, accept the license, then launch Xcode once so it installs components:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
open -a Xcode        # let it finish "installing components" the first time
```

Verify:

```bash
xcode-select -p      # → /Applications/Xcode.app/Contents/Developer
xcodebuild -version  # → Xcode 26.x
```

---

## 1. Start the cloud orchestrator

Leave this running in its own terminal — the app POSTs tasks to it.

```bash
cd cloud
export ANTHROPIC_API_KEY=sk-ant-...
npm install
npm run server          # → http://localhost:8787/tasks
```

Quick checks (no app needed):

```bash
npm test                # contract tests (no API key required)
npm run demo            # runs both example flows end-to-end (needs the key)
```

---

## 2. Generate & open the Xcode project

```bash
cd ios
xcodegen generate                 # writes AmbientAgent.xcodeproj from project.yml
open AmbientAgent.xcodeproj
```

- Wait for **Package Resolution** to finish on first open — it downloads MLX Swift (a few minutes).
- Re-run `xcodegen generate` any time you change `project.yml` or add/remove files.

## 3. Sign & run

1. Select the **AmbientAgent** scheme.
2. Target → **Signing & Capabilities** → set **Team** to your Apple ID.
   - Free Apple account? The bundle id `com.ghafran.ambientagent` may collide — change it (and the watch/test ids) to something unique like `com.<you>.ambientagent`.
3. Pick a destination and **⌘R**.

Approve the permission prompts on first launch: **microphone, speech, camera, contacts, calendar, notifications**.

### Device vs. Simulator

Use a **real iPhone** for the full experience. The Simulator launches the app, but these only work on-device:

| Feature | Simulator | Device |
|---|---|---|
| FoundationModels (the LLM) | needs Apple Intelligence | ✅ |
| FastVLM/MLX vision (opt-in, off by default) | n/a | needs device when enabled |
| Camera keyframe | no real camera | ✅ |
| Messages compose sheet | won't send | ✅ |

### Networking

- **Simulator** reaches `localhost:8787` directly (ATS exception is in the Info.plist).
- **Device** can't see your Mac's `localhost` — set `CloudClient.baseURL` in
  [ios/AmbientAgent/Core/CloudClient.swift](ios/AmbientAgent/Core/CloudClient.swift)
  to your Mac's LAN IP (e.g. `http://192.168.1.20:8787`) on the same Wi-Fi.

---

## Apple Watch (wake button)

Pair an Apple Watch with the iPhone; the watch app installs alongside (or select the **AmbientAgentWatch** scheme and run it on the watch). Tapping its mic button sends `wake` to the phone over WatchConnectivity and starts a listening session.

> Reliable wake assumes the phone app is foreground or recently used — iOS restricts starting microphone capture from a cold background launch.

## Tests

- **iOS:** ⌘U (runs `AmbientAgentTests`).
- **Cloud:** `cd cloud && npm test`.

---

## Try it

With the orchestrator running and the app on a device:

1. Tap the Watch (or on-screen) mic button, say:
   **"Text g and tell him I'll be 15 minutes late to our meeting."**
   → resolves *g → Greg → real phone*, drafts the message → the **native Messages sheet** opens pre-filled; you tap Send.
2. Say: **"Find me the cheapest weekend trip to Florida."**
   → the agent searches and speaks back the cheapest option; a local notification mirrors the reply.

The turn auto-ends after ~1.6s of silence — no second tap.

---

## Troubleshooting

- **"requires Xcode, but active developer directory is CommandLineTools"** — you skipped the `xcode-select -s` step above.
- **Package resolution fails / MLX won't fetch** — File → Packages → Reset Package Caches, then resolve again. The LLM/VLM libraries come from `mlx-swift-lm` (`branch: main` in `project.yml`); pin a tag for reproducibility.
- **`cannot execute tool 'metal' due to missing Metal Toolchain`** — Xcode 26 ships the Metal compiler as a separate component (MLX needs it). Install once: `xcodebuild -downloadComponent MetalToolchain` (or Xcode → Settings → Components).
- **Want on-device vision?** `VisionDescriber.swift` is a no-op by default (keeps builds fast + Simulator-friendly). Its header comment has the exact `mlx-swift-lm` + HuggingFace package deps and verified `ChatSession`/`VLMRegistry.fastvlm` code to enable FastVLM. Enabling it requires a real device and the Metal Toolchain.
- **Watch app doesn't embed / build** — confirm the watch bundle id is a prefix-child of the iOS id (`com.<you>.ambientagent.watchkitapp`) and `WKCompanionAppBundleIdentifier` matches the iOS id.
- **"On-device model unavailable"** — enable Apple Intelligence in Settings (Apple-Intelligence-capable device required); `IntentExtractor.availabilityMessage()` reports the specific reason.
- **App can't reach the cloud on device** — wrong `CloudClient.baseURL` (use the Mac's LAN IP), Mac firewall blocking 8787, or phone on a different network.
