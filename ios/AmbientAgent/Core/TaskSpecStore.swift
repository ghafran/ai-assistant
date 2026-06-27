import Foundation

/// Where a finished TaskSpec goes. In this on-device slice it's persisted to a local
/// outbox and logged. The next milestone replaces `emit` with a POST to the cloud
/// orchestrator (Claude + tools), which actually executes the task.
struct EmittedTask: Codable {
    var spec: TaskSpec
    var resolvedPhone: String?      // filled deterministically from memory
    var createdAt: Date
}

@MainActor
final class TaskSpecStore {
    private let outbox: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        outbox = docs.appendingPathComponent("outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
    }

    @discardableResult
    func emit(_ task: EmittedTask) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: task.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let url = outbox.appendingPathComponent("task-\(stamp).json")
        guard let data = try? JSONEncoder.pretty.encode(task) else { return nil }
        try? data.write(to: url, options: .atomic)
        print("📤 Emitted TaskSpec -> \(url.lastPathComponent)\n\(String(data: data, encoding: .utf8) ?? "")")
        return url
        // NEXT: POST `data` to the cloud orchestrator and await the agent result.
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
