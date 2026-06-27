import Foundation

/// Local, on-device slice of user memory. This is the cache the conversation loop
/// uses to resolve aliases ("g" -> Greg) and personalize without a cloud round-trip.
/// The authoritative profile lives in the cloud and syncs down to this.
struct UserProfile: Codable {
    struct Contact: Codable { var name: String; var phone: String }

    var displayName: String
    var homeAirport: String
    var budgetTier: String                 // e.g. "cheapest", "comfort"
    var contacts: [String: Contact]        // alias -> contact

    /// Inject known facts into the model instructions so it can resolve entities.
    func promptContext() -> String {
        let contactLines = contacts
            .map { "  - \"\($0.key)\" -> \($0.value.name)" }
            .sorted()
            .joined(separator: "\n")
        return """
        Known user facts:
        - Name: \(displayName)
        - Home airport: \(homeAirport)
        - Budget preference: \(budgetTier)
        Known contact aliases:
        \(contactLines.isEmpty ? "  (none)" : contactLines)
        """
    }

    /// Deterministic, code-side resolution (don't trust the model with phone numbers).
    func resolveContact(_ aliasOrName: String) -> Contact? {
        let key = aliasOrName.lowercased()
        if let c = contacts[key] { return c }
        return contacts.values.first { $0.name.lowercased() == key }
    }
}

@MainActor
final class MemoryStore {
    private let url: URL
    private(set) var profile: UserProfile

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent("user_profile.json")
        profile = MemoryStore.load(from: url) ?? MemoryStore.seed
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func load(from url: URL) -> UserProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    /// Seed data so the two demo flows work out of the box. `nonisolated` — it's
    /// pure data, usable off the main actor (e.g. from tests).
    nonisolated static let seed = UserProfile(
        displayName: "Ghafran",
        homeAirport: "JFK",
        budgetTier: "cheapest",
        contacts: [
            "g": .init(name: "Greg", phone: "+15551234567")
        ]
    )
}
