import Foundation
import CoreImage
import MLXVLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// On-device visual understanding. Captions the camera keyframe with **FastVLM**
/// running on MLX (Metal) — no network, no cloud — and feeds that caption into
/// the intent prompt.
///
/// An actor so the model loads once and inference is serialized. `ChatSession`
/// and `CIImage` are non-Sendable, so they're confined to the nonisolated
/// `caption` helper; only Sendable values (`ModelContainer`, `Data`) cross the
/// actor boundary.
actor VisionDescriber {

    var enabled = true

    private static let prompt =
        "In one short sentence, describe what the camera sees. " +
        "If it's just a face, a wall, or nothing notable, say that plainly."

    /// Loaded lazily; reused across the session. `ModelContainer` is Sendable.
    private var container: ModelContainer?

    /// Load the FastVLM weights ahead of the first request (call on launch).
    func preload() async {
        guard enabled else { return }
        _ = try? await loadIfNeeded()
    }

    /// Returns a short caption for the frame, or nil if disabled/unavailable.
    /// Vision is best-effort — it never throws into the conversation loop.
    func describe(keyframe: Data?) async -> String? {
        guard enabled, let data = keyframe,
              let container = try? await loadIfNeeded() else { return nil }
        return await Self.caption(container: container, jpeg: data)
    }

    private func loadIfNeeded() async throws -> ModelContainer {
        if let container { return container }
        // VLMRegistry.fastvlm == "mlx-community/FastVLM-0.5B-bf16".
        let loaded = try await #huggingFaceLoadModelContainer(configuration: VLMRegistry.fastvlm)
        container = loaded
        return loaded
    }

    /// Runs inference. Nonisolated so the non-Sendable `ChatSession`/`CIImage`
    /// stay in one concurrency region; inputs/outputs are all Sendable.
    private nonisolated static func caption(container: ModelContainer, jpeg: Data) async -> String? {
        guard let image = CIImage(data: jpeg) else { return nil }
        do {
            let session = ChatSession(container)
            let text = try await session.respond(to: prompt, image: .ciImage(image))
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
