import XCTest
@testable import AmbientAgent

final class CoreTests: XCTestCase {

    private func profile() -> UserProfile {
        UserProfile(
            displayName: "Ghafran",
            homeAirport: "JFK",
            budgetTier: "cheapest",
            contacts: ["g": .init(name: "Greg", phone: "+15551234567")]
        )
    }

    func testAliasResolves() {
        let p = profile()
        XCTAssertEqual(p.resolveContact("g")?.name, "Greg")
        XCTAssertEqual(p.resolveContact("g")?.phone, "+15551234567")
    }

    func testNameResolvesCaseInsensitively() {
        XCTAssertEqual(profile().resolveContact("greg")?.name, "Greg")
    }

    func testUnknownContactIsNil() {
        XCTAssertNil(profile().resolveContact("nobody"))
    }

    func testIntentRawValuesMatchCloudContract() {
        // These strings are the wire contract the cloud orchestrator switches on.
        XCTAssertEqual(Intent.sendMessage.rawValue, "send_message")
        XCTAssertEqual(Intent.bookTravel.rawValue, "book_travel")
    }

    func testTaskSpecRoundTrips() throws {
        let spec = TaskSpec(
            intent: .sendMessage,
            summary: "Tell Greg I'll be late",
            recipient: "Greg",
            messageBody: "Running late",
            destination: "",
            timeframe: "",
            needsClarification: false,
            clarifyingQuestion: "",
            confidence: 0.9
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(TaskSpec.self, from: data)
        XCTAssertEqual(decoded, spec)

        // The encoded intent must be the snake_case string the cloud expects.
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"send_message\""))
    }

    func testSeedProfileHasGreg() {
        XCTAssertEqual(MemoryStore.seed.contacts["g"]?.name, "Greg")
    }
}
