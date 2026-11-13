import ActivityKit
import Foundation

/// ActivityKit attributes for the Dynamic Island & Lock Screen pet Live Activity.
/// Supports solo mode (1 dog + special solo quirks) and connected mode (both dogs on the Dynamic Island,
/// message display, and 20 combined two-dog interactions).
public struct PetActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// This iPhone user's selected pet, custom name, and chosen Emotion/Task.
        public var myPet: IslandPetSnapshot
        /// Optional status note set by this iPhone's owner (auto-expires after 24 hours).
        public var myMessage: String?
        /// Unix timestamp when `myMessage` expires (24 hours after creation).
        public var myMessageExpiresAt: TimeInterval?
        /// Whether this phone is currently connected to a room.
        public var isPaired: Bool
        /// The connected pet (when linked), rendered alongside `myPet` on the Dynamic Island.
        public var partnerPet: IslandPetSnapshot?
        /// Legacy optional nickname field.
        public var partnerOwnerName: String?
        /// Latest message sent by the connected pet (auto-expires after 24 hours).
        public var partnerMessage: String?
        /// Unix timestamp when `partnerMessage` expires (24 hours after creation).
        public var partnerMessageExpiresAt: TimeInterval?
        /// Optional combined two-dog interaction scene triggered by status sync, clash, message, or chaos.
        public var rareInteraction: RarePetInteraction?
        /// Optional temporary solo special quirk (e.g. Snoot Boop, Zoomies, Blep) preserving `myPet.action`.
        public var soloQuirk: SoloPetQuirk?
        /// Even-second aligned past timestamp anchoring the `PetTimerGate-Regular` mask animation.
        public var anchorTimestamp: TimeInterval

        private enum CodingKeys: String, CodingKey {
            case myPet
            case myMessage
            case myMessageExpiresAt
            case isPaired
            case partnerPet
            case partnerOwnerName
            case partnerMessage
            case partnerMessageExpiresAt
            case rareInteraction
            case soloQuirk
            case anchorTimestamp
        }

        public init(
            myPet: IslandPetSnapshot,
            myMessage: String? = nil,
            myMessageExpiresAt: TimeInterval? = nil,
            isPaired: Bool = false,
            partnerPet: IslandPetSnapshot? = nil,
            partnerOwnerName: String? = nil,
            partnerMessage: String? = nil,
            partnerMessageExpiresAt: TimeInterval? = nil,
            rareInteraction: RarePetInteraction? = nil,
            soloQuirk: SoloPetQuirk? = nil,
            anchorTimestamp: TimeInterval? = nil
        ) {
            self.myPet = myPet
            self.myMessage = myMessage
            self.myMessageExpiresAt = myMessageExpiresAt
            self.isPaired = isPaired
            self.partnerPet = partnerPet
            self.partnerOwnerName = partnerOwnerName
            self.partnerMessage = partnerMessage
            self.partnerMessageExpiresAt = partnerMessageExpiresAt
            self.rareInteraction = rareInteraction
            self.soloQuirk = soloQuirk
            if let anchorTimestamp {
                self.anchorTimestamp = anchorTimestamp
            } else {
                let now = Date().timeIntervalSince1970
                self.anchorTimestamp = floor(now / 6.0) * 6.0 - 60.0
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.myPet = try container.decode(IslandPetSnapshot.self, forKey: .myPet)
            self.myMessage = try? container.decodeIfPresent(String.self, forKey: .myMessage)
            self.myMessageExpiresAt = try? container.decodeIfPresent(TimeInterval.self, forKey: .myMessageExpiresAt)
            self.isPaired = (try? container.decode(Bool.self, forKey: .isPaired)) ?? false
            self.partnerPet = try? container.decodeIfPresent(IslandPetSnapshot.self, forKey: .partnerPet)
            self.partnerOwnerName = try? container.decodeIfPresent(String.self, forKey: .partnerOwnerName)
            self.partnerMessage = try? container.decodeIfPresent(String.self, forKey: .partnerMessage)
            self.partnerMessageExpiresAt = try? container.decodeIfPresent(TimeInterval.self, forKey: .partnerMessageExpiresAt)
            self.rareInteraction = try? container.decodeIfPresent(RarePetInteraction.self, forKey: .rareInteraction)
            self.soloQuirk = try? container.decodeIfPresent(SoloPetQuirk.self, forKey: .soloQuirk)
            let now = Date().timeIntervalSince1970
            self.anchorTimestamp = (try? container.decode(TimeInterval.self, forKey: .anchorTimestamp))
                ?? (floor(now / 6.0) * 6.0 - 60.0)
        }

        public var anchorDate: Date {
            if let active = activeInteraction {
                let aligned = floor(active.startedAt / 6.0) * 6.0 - 60.0
                return Date(timeIntervalSince1970: aligned)
            }
            return Date(timeIntervalSince1970: anchorTimestamp)
        }

        /// True when paired and we have a connected dog to display beside ours on the Dynamic Island.
        public var hasTwoDogs: Bool {
            isPaired && partnerPet != nil
        }

        /// Returns the active combined interaction if both dogs are present and the event hasn't expired.
        public var activeInteraction: RarePetInteraction? {
            guard hasTwoDogs, let rareInteraction, rareInteraction.isActive() else {
                return nil
            }
            return rareInteraction
        }

        /// Returns the active temporary solo quirk when no two-dog interaction is overriding it.
        public var activeSoloQuirk: SoloPetQuirk? {
            guard activeInteraction == nil, let soloQuirk, soloQuirk.isActive() else {
                return nil
            }
            return soloQuirk
        }

        /// True when both connected pets are built-in characters so combined duo sprite scenes apply cleanly.
        public var canRenderCombinedDuoArtwork: Bool {
            hasTwoDogs && myPet.builtInCharacter != nil && partnerPet?.builtInCharacter != nil
        }

        /// Returns `myMessage` only when non-empty and within its 24-hour lifetime.
        public var activeMyMessage: String? {
            guard let myMessage, !myMessage.isEmpty else { return nil }
            if let exp = myMessageExpiresAt, Date().timeIntervalSince1970 + 1.0 >= exp {
                return nil
            }
            return myMessage
        }

        /// Returns `partnerMessage` only when non-empty and within its 24-hour lifetime.
        public var activePartnerMessage: String? {
            guard let partnerMessage, !partnerMessage.isEmpty else { return nil }
            if let exp = partnerMessageExpiresAt, Date().timeIntervalSince1970 + 1.0 >= exp {
                return nil
            }
            return partnerMessage
        }

        /// Earliest upcoming expiry date of any active interaction, quirk, or 24-hour message for ActivityKit `staleDate`.
        public var nextExpiryDate: Date? {
            let now = Date().timeIntervalSince1970
            let myMsgExp = (activeMyMessage != nil) ? myMessageExpiresAt.map { $0 + 0.5 } : nil
            let partnerMsgExp = (activePartnerMessage != nil) ? partnerMessageExpiresAt.map { $0 + 0.5 } : nil
            let candidates = [
                activeInteraction?.expiresAt,
                activeSoloQuirk?.expiresAt,
                myMsgExp,
                partnerMsgExp
            ]
            .compactMap { $0 }
            .filter { $0 > now }
            guard let earliest = candidates.min() else { return nil }
            return Date(timeIntervalSince1970: earliest)
        }

        /// Snapshot of my pet, temporarily adopting an interaction pose or solo quirk when active.
        public var displayMyPet: IslandPetSnapshot {
            if let interaction = activeInteraction {
                return myPet.withAction(interaction.kind.myDogAction)
            }
            if let quirk = activeSoloQuirk {
                return myPet.withAction(quirk.action)
            }
            return myPet
        }

        /// Snapshot of connected pet, temporarily adopting an interaction pose during a combined moment.
        public var displayPartnerPet: IslandPetSnapshot? {
            guard let partnerPet else { return nil }
            if let interaction = activeInteraction {
                return partnerPet.withAction(interaction.kind.partnerDogAction)
            }
            return partnerPet
        }

        /// Guarantees the encoded `ContentState` stays safely under ActivityKit's 4,096-byte ceiling.
        public func fittingActivityKitBudget() -> ContentState {
            if myPet.customMicroFrames == nil && partnerPet?.customMicroFrames == nil {
                return self
            }
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
