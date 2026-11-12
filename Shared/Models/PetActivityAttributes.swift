import ActivityKit
import Foundation

/// ActivityKit attributes for the Dynamic Island & Lock Screen pet Live Activity.
public struct PetActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// The 1 active pet character running on this iPhone's Dynamic Island.
        public var character: PetCharacter
        /// Current animation state of this phone's pet.
        public var action: PetAction
        /// Display name of the paired friend who triggered this action (if set remotely).
        public var senderName: String?
        /// Optional short note sent alongside the action (e.g. "Goodnight!").
        public var note: String?
        /// Whether this phone is currently paired with another phone.
        public var isPaired: Bool
        /// Partner's pet character (if known), shown as a tiny status hint in Expanded view.
        public var partnerCharacter: PetCharacter?
        /// Partner's latest known action (if known).
        public var partnerAction: PetAction?
        /// Even-second aligned past timestamp anchoring the PetTimerGate mask animation.
        public var anchorTimestamp: TimeInterval

        public init(
            character: PetCharacter,
            action: PetAction,
            senderName: String? = nil,
            note: String? = nil,
            isPaired: Bool = false,
            partnerCharacter: PetCharacter? = nil,
            partnerAction: PetAction? = nil,
            anchorTimestamp: TimeInterval? = nil
        ) {
            self.character = character
            self.action = action
            self.senderName = senderName
            self.note = note
            self.isPaired = isPaired
            self.partnerCharacter = partnerCharacter
            self.partnerAction = partnerAction
            // Align to an exact 2-second boundary 10 seconds in the past so every
            // fractional timer offset immediately counts UP from phase 0.
            if let anchorTimestamp {
                self.anchorTimestamp = anchorTimestamp
            } else {
                let now = Date().timeIntervalSince1970
                self.anchorTimestamp = floor(now / 2.0) * 2.0 - 10.0
            }
        }

        public var anchorDate: Date {
            Date(timeIntervalSince1970: anchorTimestamp)
        }
    }

    public var sessionID: String

    public init(sessionID: String = UUID().uuidString) {
        self.sessionID = sessionID
    }
}
