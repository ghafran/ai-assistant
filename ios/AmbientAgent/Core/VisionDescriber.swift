import Foundation

/// On-device visual understanding (camera keyframe → one-line caption that feeds
/// the intent prompt).
///
/// Currently a no-op so the app builds fast and runs in the Simulator. The real
/// implementation runs **FastVLM on MLX**, which (a) only works on a physical
/// device (Metal) and (b) pulls heavy HuggingFace packages into every build — so
/// it's an opt-in. Everything below is verified against `mlx-swift-lm` `main`.
///
/// ── To enable FastVLM ────────────────────────────────────────────────────────
/// 1. In `project.yml`, add the packages + product deps to the AmbientAgent target:
///        packages:
///          mlx-swift-lm:      { url: https://github.com/ml-explore/mlx-swift-lm, branch: main }
///          swift-transformers:{ url: https://github.com/huggingface/swift-transformers, from: "1.3.0" }
///          swift-huggingface: { url: https://github.com/huggingface/swift-huggingface, branch: main }
///        dependencies:
///          - { package: mlx-swift-lm, product: MLXVLM }
///          - { package: mlx-swift-lm, product: MLXLMCommon }
///          - { package: mlx-swift-lm, product: MLXHuggingFace }
///          - { package: swift-transformers, product: Tokenizers }
///          - { package: swift-huggingface, product: HuggingFace }
///    then `xcodegen generate`, and run `xcodebuild -downloadComponent MetalToolchain` once.
///
/// 2. Replace this file's body with:
///        import Foundation
///        import CoreImage
///        import MLXVLM
///        import MLXLMCommon
///        import MLXHuggingFace
///        import HuggingFace
///        import Tokenizers
///
///        actor VisionDescriber {
///            var enabled = true
///            private var session: ChatSession?
///            private let prompt = "In one short sentence, describe what the camera sees."
///
///            func preload() async { _ = try? await loadIfNeeded() }
///
///            func describe(keyframe: Data?) async -> String? {
///                guard enabled, let data = keyframe, let image = CIImage(data: data) else { return nil }
///                do {
///                    let session = try await loadIfNeeded()
///                    let caption = try await session.respond(to: prompt, image: .ciImage(image))
///                    let t = caption.trimmingCharacters(in: .whitespacesAndNewlines)
///                    return t.isEmpty ? nil : t
///                } catch { return nil }
///            }
///
///            private func loadIfNeeded() async throws -> ChatSession {
///                if let session { return session }
///                let model = try await #huggingFaceLoadModelContainer(
///                    configuration: VLMRegistry.fastvlm)   // mlx-community/FastVLM-0.5B-bf16
///                let s = ChatSession(model)
///                session = s
///                return s
///            }
///        }
/// ─────────────────────────────────────────────────────────────────────────────
actor VisionDescriber {
    var enabled = false

    /// No-op until FastVLM is enabled (see header). Keeps the loop building & fast.
    func describe(keyframe: Data?) async -> String? { nil }

    /// No-op preload; the real version downloads/loads the VLM weights on launch.
    func preload() async {}
}
