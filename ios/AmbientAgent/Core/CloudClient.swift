import Foundation

/// Sends a finished TaskSpec to the cloud orchestrator and reads back what the
/// agent did. This is the seam between the on-device loop and the cloud agents.
struct CloudClient {
    /// Where the orchestrator runs. `localhost` works from the iOS Simulator (it
    /// shares the Mac's network). For a physical device, set this to your Mac's
    /// LAN IP (e.g. http://192.168.1.20:8787).
    var baseURL = URL(string: "http://localhost:8787")!

    /// Matches the cloud's TaskResult. `compose` is present when the agent drafted
    /// a message for the user to send via the native Messages sheet.
    struct Reply: Decodable {
        let reply: String
        let compose: Compose?
    }

    struct Compose: Decodable {
        let toName: String
        let toPhone: String
        let body: String
    }

    enum CloudError: Error, LocalizedError {
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Orchestrator returned HTTP \(code)."
            }
        }
    }

    func run(_ task: EmittedTask) async throws -> Reply {
        var request = URLRequest(url: baseURL.appendingPathComponent("tasks"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(task)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw CloudError.badStatus(http.statusCode) }

        return try JSONDecoder().decode(Reply.self, from: data)
    }
}
