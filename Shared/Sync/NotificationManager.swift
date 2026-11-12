import Foundation
import UserNotifications

/// Delivers local iOS banner & Notification Center alerts showing the partner's message
/// whenever the connected partner updates their pet with a message.
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

    public func postPartnerUpdateNotification(
        partnerPetName: String,
        partnerOwnerName: String?,
        action: PetAction,
        partnerMessage: String?,
        dedupeKey: String
    ) {
        let content = UNMutableNotificationContent()
        if let owner = partnerOwnerName, !owner.isEmpty {
            content.title = "🐾 \(partnerPetName) (\(owner)) \(action.emoji)"
        } else {
            content.title = "🐾 \(partnerPetName) \(action.emoji)"
        }

        if let msg = partnerMessage, !msg.isEmpty {
            content.subtitle = "\(partnerPetName) \(action.statusPhrase)"
            content.body = "“\(msg)”"
        } else {
            content.body = "\(partnerPetName) \(action.statusPhrase)"
        }
        content.sound = .default
        content.threadIdentifier = "islandpup-partner-updates"

        let request = UNNotificationRequest(
            identifier: "islandpup-msg-\(dedupeKey)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func postRareInteractionNotification(
        myPetName: String,
        partnerPetName: String,
        interaction: RarePetInteraction
    ) {
        let content = UNMutableNotificationContent()
        content.title = "✨ Rare Puppy Moment! \(interaction.kind.badgeEmoji)"
        content.body = interaction.kind.descriptionText(
            myPetName: myPetName,
            partnerPetName: partnerPetName
        )
        content.sound = .default
        content.threadIdentifier = "islandpup-rare-interactions"

        let request = UNNotificationRequest(
            identifier: "islandpup-rare-\(interaction.id)",
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
