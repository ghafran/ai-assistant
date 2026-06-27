# AmbientAgent (iOS)

The on-device **conversation loop** for the ambient agent: wake → listen + see → understand → emit a `TaskSpec` for the cloud agent layer to execute. The app is just the I/O surface; it never performs the task itself.

## The loop

```
[ wake: Apple Watch button  ·OR·  on-screen button ]   ← WatchConnectivity
      │
      ▼
 SpeechTranscriber   ──┐  on-device streaming ASR (Speech.framework)
 CameraCapture       ──┤  one keyframe (AVFoundation)
 VisionDescriber     ──┘  caption via FastVLM/MLX (on-device, enabled)
      │   (auto-stops on ~1.6s of silence — VAD)
      ▼
 IntentExtractor        FoundationModels, @Generable guided generation
      │   + real Contacts (alias "g" → Greg → phone) + real Calendar (EventKit)
      ▼
 TaskSpec  ──▶ outbox/*.json (local record)
          └──▶ POST /tasks ──▶ cloud agents run it ──▶ reply spoken + local notification
                                        │
                                        └─ if a message was drafted → native Messages sheet
```

Files: `Core/ConversationSession.swift` is the state machine that drives everything; each capability is one focused file beside it.

## Requirements

- **Xcode 26+** (full app, not just Command Line Tools) — for the iOS 26 SDK + `FoundationModels`.
- A device/simulator with **Apple Intelligence** enabled (iPhone 15 Pro / A17 Pro or newer, or the iOS 26 simulator). `IntentExtractor.availabilityMessage()` surfaces a friendly message when it's not available.
- **Real device recommended** — FastVLM/MLX needs Metal (limited in the Simulator), and `MFMessageComposeViewController` only sends on a device.
- **Apple Watch optional** — pair one to use the watch as the wake button; the on-screen button works without it.

## Build & run

```bash
brew install xcodegen        # one-time
cd ios
xcodegen generate            # creates AmbientAgent.xcodeproj from project.yml
open AmbientAgent.xcodeproj  # ⌘R to run
```

On a physical device: select your team in Signing & Capabilities (the bundle id is `com.ghafran.ambientagent`).

## Try it

1. Tap the mic button, say: **"Text g and tell him I'll be 15 minutes late to our meeting."**
   → emits a `send_message` TaskSpec with `recipient: Greg`, message body filled, phone resolved from memory.
2. Tap again, say: **"Find me the cheapest weekend trip to Florida."**
   → emits a `book_travel` TaskSpec with destination + timeframe + your home airport/budget from memory.

Emitted specs land in the app's `Documents/outbox/` and print to the Xcode console.

## On-device vision (FastVLM / MLX)

[VisionDescriber](AmbientAgent/Core/VisionDescriber.swift) runs **FastVLM** via [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) (`ChatSession` + `VLMRegistry.fastvlm` = `mlx-community/FastVLM-0.5B-bf16`) and captions the camera keyframe into `IntentExtractor`. Enabled by default; **compiles green**. Packages are wired in `project.yml` (`mlx-swift-lm`, `swift-transformers`, `swift-huggingface`). Notes:

- **First Xcode build** prompts to **Trust & Enable** the `MLXHuggingFaceMacros` macro — click it (the loader uses a Swift macro). CLI equivalent: `-skipMacroValidation`.
- **Metal Toolchain required** — `xcodebuild -downloadComponent MetalToolchain` (Xcode 26 ships it separately).
- **Real device for runtime** — MLX uses Metal; Simulator GPU support is limited. First run downloads the weights (~hundreds of MB); `preload()` warms them on launch.
- To disable, set `enabled = false` in `VisionDescriber` (the loop runs fine without vision).

## Recently added

- **Apple Watch trigger** (`AmbientAgentWatch/`) — a watchOS app whose button sends `wake` to the phone over **WatchConnectivity** (`WatchLink.swift` on the phone). Same entry point as the on-screen button.
- **Auto-endpointing (VAD)** — the turn ends itself after ~1.6s of silence (`bumpSilence` in `ConversationSession`); no second tap needed.
- **Native Contacts + Calendar** (`ContactsService`, `CalendarService`) — resolves "g"→Greg→real phone number, and grounds "our meeting" against EventKit. Replaces the seeded data.
- **Native Messages, no Twilio** (`MessageComposer`) — the agent *drafts*; the phone presents `MFMessageComposeViewController` pre-filled. iOS can't send SMS silently, so the user taps Send — a built-in confirmation gate.
- **Notifications** (`NotificationService`) — the agent's result also fires a local notification.
- **Pre-warming** — `IntentExtractor.warm()` + `VisionDescriber.preload()` run on launch so the first real session isn't slow.
- **Tests** (`AmbientAgentTests/`) — unit tests for alias resolution, the TaskSpec wire contract, and seed data.

## Cloud handoff

`Core/CloudClient.swift` POSTs an actionable TaskSpec to the orchestrator and reads back `{ reply, compose? }`. Start the orchestrator first (`cd ../cloud && npm run server`). On a physical device, set `CloudClient.baseURL` to your Mac's LAN IP. If the cloud is unreachable it falls back to a local "saved it" confirmation (the outbox copy is kept).

## Shared contract

`../schema/taskspec.schema.json` is the language-neutral version of `TaskSpec` — the same contract the cloud layer consumes.
