import Foundation
import SwiftUI

/// The on-device conversation loop, as a small state machine:
///
///   idle ──wake()──▶ listening ──finishAndProcess()──▶ thinking ──▶ speaking ──▶ idle
///
/// On wake: open mic + grab one camera keyframe, stream ASR.
/// On finish: fuse transcript + visual context + memory → TaskSpec, confirm by voice,
/// emit to the outbox (later: hand off to the cloud agent layer).
@MainActor
@Observable
final class ConversationSession {

    enum Phase: Equatable {
        case idle, listening, thinking, speaking, error(String)

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .listening: return "Listening…"
            case .thinking: return "Thinking…"
            case .speaking: return "Speaking…"
            case .error(let m): return m
            }
        }
        var tint: Color {
            switch self {
            case .idle: return .secondary
            case .listening: return .red
            case .thinking: return .orange
            case .speaking: return .blue
            case .error: return .pink
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var displayText: String = ""
    private(set) var lastTaskSpec: TaskSpec?
    /// Set when the agent drafted a message; the UI presents the native sheet.
    private(set) var pendingCompose: CloudClient.Compose?

    private let transcriber = SpeechTranscriber()
    private let camera = CameraCapture()
    private let vision = VisionDescriber()
    private let extractor = IntentExtractor()
    private let speaker = Speaker()
    private let memory = MemoryStore()
    private let store = TaskSpecStore()
    private let cloud = CloudClient()
    private let contacts = ContactsService()
    private let calendar = CalendarService()

    private var keyframe: Data?
    private var silenceTimer: Task<Void, Never>?
    private let silenceSeconds = 1.6

    /// One-time setup: surface model availability, request permissions, and
    /// pre-warm the on-device models so the first real session isn't slow.
    func prepare() async {
        if let msg = IntentExtractor.availabilityMessage() {
            phase = .error(msg)
        }
        await NotificationService.requestAuth()
        _ = await contacts.requestAccess()
        _ = await calendar.requestAccess()
        Task { await vision.preload() }
        Task { await IntentExtractor.warm() }
    }

    func dismissCompose() { pendingCompose = nil }

    /// Simulated button press. (The BLE button will call straight into this.)
    func wake() async {
        guard phase == .idle || isError else { return }
        displayText = ""
        lastTaskSpec = nil
        keyframe = nil

        do {
            try await transcriber.requestAuthorization()
        } catch {
            phase = .error("Microphone/Speech permission is required.")
            return
        }

        // Grab a keyframe in the background while we start listening.
        Task { self.keyframe = await self.camera.captureKeyframe() }

        transcriber.onUpdate = { [weak self] text in
            guard let self else { return }
            self.displayText = text
            self.bumpSilence() // each new word resets the auto-stop countdown
        }
        do {
            try transcriber.start()
            phase = .listening
            bumpSilence()
        } catch {
            phase = .error("Couldn't start listening.")
        }
    }

    /// Auto-endpointing: after a beat of silence, end the turn on its own so the
    /// "short conversation" finishes without a second tap.
    private func bumpSilence() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.silenceSeconds ?? 1.6))
            guard !Task.isCancelled, let self else { return }
            await self.finishAndProcess()
        }
    }

    private func cancelSilence() {
        silenceTimer?.cancel()
        silenceTimer = nil
    }

    /// End of the short conversation → process it.
    func finishAndProcess() async {
        guard phase == .listening else { return }
        cancelSilence()
        let transcript = transcriber.stop()
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase = .idle
            return
        }

        phase = .thinking
        displayText = transcript

        let visualContext = await vision.describe(keyframe: keyframe)
        let calendarContext = calendar.upcoming()

        do {
            var spec = try await extractor.extract(
                transcript: transcript,
                visualContext: visualContext,
                calendar: calendarContext,
                memory: memory.profile
            )

            // Resolve the recipient: alias → name (local map), then name → phone
            // from the real Contacts database; fall back to the seeded number.
            var resolvedPhone: String?
            if !spec.recipient.isEmpty {
                let aliased = memory.profile.resolveContact(spec.recipient)
                let name = aliased?.name ?? spec.recipient
                spec.recipient = name
                resolvedPhone = contacts.phone(forName: name) ?? aliased?.phone
            }
            lastTaskSpec = spec

            // Not actionable yet — ask the follow-up and stop here.
            if spec.needsClarification {
                let question = spec.clarifyingQuestion.isEmpty
                    ? "Could you say a bit more?"
                    : spec.clarifyingQuestion
                phase = .speaking
                speaker.say(question)
                phase = .idle
                return
            }

            // Persist locally, then hand off to the cloud agents to actually do it.
            let emitted = EmittedTask(spec: spec, resolvedPhone: resolvedPhone, createdAt: Date())
            store.emit(emitted)

            phase = .speaking
            speaker.say("On it.")
            await dispatch(emitted, summary: spec.summary)
            phase = .idle
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Send the task to the orchestrator and speak back what the agent did. Falls
    /// back gracefully (and keeps the local outbox copy) if the cloud is unreachable.
    private func dispatch(_ task: EmittedTask, summary: String) async {
        do {
            let result = try await cloud.run(task)
            displayText = result.reply
            speaker.say(result.reply)
            NotificationService.notify(result.reply)
            // If the agent drafted a message, hand it to the native Messages sheet.
            if let compose = result.compose, MessageComposer.canSend {
                pendingCompose = compose
            }
        } catch {
            let fallback = "Saved it, but I couldn't reach the cloud to finish. \(summary)"
            displayText = fallback
            speaker.say(fallback)
            NotificationService.notify(fallback)
        }
    }

    private var isError: Bool { if case .error = phase { return true }; return false }
}
