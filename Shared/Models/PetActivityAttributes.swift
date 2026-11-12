import ActivityKit
import Foundation

/// ActivityKit attributes for the Dynamic Island & Lock Screen pet Live Activity.
/// Supports solo mode (1 dog) and connected mode (both dogs on the Dynamic Island,
/// partner message display in Lock Screen / Expanded notifications, and rare 2-dog interactions).
public struct PetActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// This iPhone user's selected pet, custom name, and active action.
        public var myPet: IslandPetSnapshot
        /// Optional status note set by this iPhone's owner.
        public var myMessage: String?
        /// Whether this phone is currently connected to a partner room.
        public var isPaired: Bool
        /// The connected partner's pet (when linked), rendered alongside `myPet` on the Dynamic Island.
        public var partnerPet: IslandPetSnapshot?
        /// Display nickname of the partner.
        public var partnerOwnerName: String?
        /// Latest message sent by the partner (shown in notifications & Live Activity banner).
        public var partnerMessage: String?
        /// Optional spontaneous rare interaction where both dogs interact together.
        public var rareInteraction: RarePetInteraction?
        /// Even-second aligned past timestamp anchoring the `PetTimerGate-Regular` mask animation.
        public var anchorTimestamp: TimeInterval

        public init(
            myPet: IslandPetSnapshot,
            myMessage: String? = nil,
            isPaired: Bool = false,
            partnerPet: IslandPetSnapshot? = nil,
            partnerOwnerName: String? = nil,
            partnerMessage: String? = nil,
            rareInteraction: RarePetInteraction? = nil,
            anchorTimestamp: TimeInterval? = nil
        ) {
            self.myPet = myPet
            self.myMessage = myMessage
            self.isPaired = isPaired
            self.partnerPet = partnerPet
            self.partnerOwnerName = partnerOwnerName
            self.partnerMessage = partnerMessage
            self.rareInteraction = rareInteraction
            if let anchorTimestamp {
                self.anchorTimestamp = anchorTimestamp
            } else {
                let now = Date().timeIntervalSince1970
                self.anchorTimestamp = floor(now / 2.0) * 2.0 - 60.0
            }
        }

        public var anchorDate: Date {
            Date(timeIntervalSince1970: anchorTimestamp)
        }

        /// True when paired and we have a partner dog to display beside ours on the Dynamic Island.
        public var hasTwoDogs: Bool {
            isPaired && partnerPet != nil
        }

        /// Returns the rare interaction if both dogs are present and the event hasn't expired.
        public var activeInteraction: RarePetInteraction? {
            guard hasTwoDogs, let rareInteraction, rareInteraction.isActive() else {
                return nil
            }
            return rareInteraction
        }

        /// Snapshot of my pet, temporarily adopting the interaction pose during a rare 2-dog moment.
        public var displayMyPet: IslandPetSnapshot {
            if let interaction = activeInteraction {
                return myPet.withAction(interaction.kind.myDogAction)
            }
            return myPet
        }

        /// Snapshot of partner's pet, temporarily adopting the interaction pose during a rare 2-dog moment.
        public var displayPartnerPet: IslandPetSnapshot? {
            guard let partnerPet else { return nil }
            if let interaction = activeInteraction {
                return partnerPet.withAction(interaction.kind.partnerDogAction)
            }
            return partnerPet
        }

        /// Guarantees the encoded `ContentState` stays safely under ActivityKit's 4,096-byte ceiling.
        public func fittingActivityKitBudget() -> ContentState {
            var candidate = self
            let maxSafeBytes = 3600
            if let encoded = try? JSONEncoder().encode(candidate), encoded.count <= maxSafeBytes {
                return candidate
            }
            if let myFrames = candidate.myPet.customMicroFrames, myFrames.count > 1 {
                candidate.myPet.customMicroFrames = [myFrames[0]]
            }
            if let partnerFrames = candidate.partnerPet?.customMicroFrames, partnerFrames.count > 1 {
                candidate.partnerPet?.customMicroFrames = [partnerFrames[0]]
            }
            if let encoded = try? JSONEncoder().encode(candidate), encoded.count <= maxSafeBytes {
                return candidate
            }
            candidate.myMessage = candidate.myMessage.map { String($0.prefix(32)) }
            candidate.partnerMessage = candidate.partnerMessage.map { String($0.prefix(48)) }
            return candidate
        }
    }

    public var sessionID: String

    public init(sessionID: String = UUID().uuidString) {
        self.sessionID = sessionID
    }
}
