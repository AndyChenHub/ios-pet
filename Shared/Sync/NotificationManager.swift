import Foundation
import UserNotifications

/// Delivers local iOS banner & Notification Center alerts strictly for incoming partner messages
/// (never for silent pet action changes, pet switches, or rare animations).
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationManager()

    private override init() {
        super.init()
    }

    public func configureAndRequestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func postPartnerMessageNotification(
        partnerPetName: String,
        partnerMessage: String,
        dedupeKey: String
    ) {
        let trimmed = partnerMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "🐾 \(partnerPetName)'s message"
        content.body = "“\(trimmed)”"
        content.sound = .default
        content.threadIdentifier = "islandpup-partner-messages"

        let request = UNNotificationRequest(
            identifier: "islandpup-msg-\(dedupeKey)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // Allow banners & sounds even if the app happens to be open
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
