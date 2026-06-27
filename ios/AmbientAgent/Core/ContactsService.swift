import Foundation
import Contacts

/// Reads the user's real contacts on-device. Aliases like "g" still come from
/// the local alias map (a phone book has no "g"); this resolves the resulting
/// name to an actual phone number.
struct ContactsService {
    // Stateless: CNContactStore isn't Sendable, so we create one per call rather
    // than hold it (keeps this usable from the @MainActor session under Swift 6).

    func requestAccess() async -> Bool {
        if CNContactStore.authorizationStatus(for: .contacts) == .authorized { return true }
        let store = CNContactStore()
        return await withCheckedContinuation { cont in
            store.requestAccess(for: .contacts) { granted, _ in cont.resume(returning: granted) }
        }
    }

    /// Best phone number for a display name, or nil if no match / no access.
    func phone(forName name: String) -> String? {
        let store = CNContactStore()
        let keys = [CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let matches = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return matches.first?.phoneNumbers.first?.value.stringValue
    }
}
