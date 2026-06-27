import Foundation
import EventKit

/// Reads the user's real calendar on-device, so references like "our meeting"
/// can be grounded against actual events. Surfaced to the intent model as context.
struct CalendarService {
    // Stateless: EKEventStore isn't Sendable, so we create one per call.

    func requestAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        let store = EKEventStore()
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Upcoming events over the next `days`, as short grounding strings.
    func upcoming(days: Int = 7) -> [String] {
        let store = EKEventStore()
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"

        return store.events(matching: predicate).prefix(8).map { event in
            let who = (event.attendees?.compactMap { $0.name }.joined(separator: ", ")) ?? ""
            let title = event.title ?? "Event"
            let when = formatter.string(from: event.startDate)
            return who.isEmpty ? "\(title) at \(when)" : "\(title) at \(when) with \(who)"
        }
    }
}
