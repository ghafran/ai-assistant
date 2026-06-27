import Foundation
import UserNotifications

/// Local notifications so the agent's result reaches the user even if the app
/// is backgrounded by the time a longer cloud task finishes.
enum NotificationService {
    static func requestAuth() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    static func notify(_ body: String, title: String = "Ambient Agent") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver now
        )
        UNUserNotificationCenter.current().add(request)
    }
}
