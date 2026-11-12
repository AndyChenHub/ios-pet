import ActivityKit
import Combine
import CryptoKit
import Foundation
import UIKit

/// End-to-end encrypted (`AES-256-GCM`) wire payload synchronizing each user's pet, custom sprites,
/// pet name, action, partner message, and spontaneous rare 2-dog interactions.
public struct PairWireMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case petState = "pet_state"
        case rareInteraction = "rare_interaction"
    }

    public var kind: Kind
    public var senderDeviceId: String
    public var senderOwnerName: String
    public var petSnapshot: IslandPetSnapshot
    public var message: String?
    public var isExplicitUpdate: Bool
    public var rareInteraction: RarePetInteraction?
    public var sentAt: TimeInterval

    public init(
        kind: Kind,
        senderDeviceId: String,
        senderOwnerName: String,
        petSnapshot: IslandPetSnapshot,
        message: String? = nil,
        isExplicitUpdate: Bool = false,
        rareInteraction: RarePetInteraction? = nil,
        sentAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.kind = kind
        self.senderDeviceId = senderDeviceId
        self.senderOwnerName = senderOwnerName
        self.petSnapshot = petSnapshot
        self.message = message
        self.isExplicitUpdate = isExplicitUpdate
        self.rareInteraction = rareInteraction
        self.sentAt = sentAt
    }
}

private struct NtfyEnvelope: Decodable {
    let id: String?
    let time: Int?
    let event: String
    let message: String?
}

@MainActor
public final class PairSyncService: ObservableObject {
    public static let shared = PairSyncService()

    private static let maxEnvelopeLineBytes = 8192
    private static let maxCiphertextChars = 3900
    private static let maxFutureClockSkewSeconds: TimeInterval = 300
    private static let maxMessageAgeSeconds: TimeInterval = 86_400
    private static let rareInteractionCooldown: TimeInterval = 95

    public enum ConnectionStatus: Equatable, Sendable {
        case unpaired
        case connecting
        case listening
        case partnerLinked(petName: String)
        case error(String)
    }

    @Published public private(set) var roster: [PetProfile]
    @Published public private(set) var myPetProfile: PetProfile
    @Published public private(set) var myAction: PetAction
    @Published public private(set) var myMessage: String?
    @Published public var myName: String {
        didSet { storage.myName = myName }
    }

    @Published public private(set) var pairCode: String
    @Published public var relayBaseURL: String {
        didSet { storage.relayBaseURL = relayBaseURL }
    }

    @Published public private(set) var partnerOwnerName: String?
    @Published public private(set) var partnerPet: IslandPetSnapshot?
    @Published public private(set) var partnerMessage: String?
    @Published public private(set) var activeRareInteraction: RarePetInteraction?
    @Published public private(set) var connectionStatus: ConnectionStatus = .unpaired
    @Published public var toastMessage: String?

    private let storage = SharedStorage.shared
    private let petStore = CustomPetStore.shared
    private var streamTask: Task<Void, Never>?
    private var heartbeatPollTask: Task<Void, Never>?
    private var rareRollTask: Task<Void, Never>?
    private var rareExpiryTask: Task<Void, Never>?

    private init() {
        let loadedRoster = CustomPetStore.shared.loadRoster()
        self.roster = loadedRoster
        let currentProfile = SharedStorage.shared.selectedPetProfile
        self.myPetProfile = currentProfile
        self.myAction = SharedStorage.shared.myAction
        self.myMessage = SharedStorage.shared.myMessage
        self.myName = SharedStorage.shared.myName
        self.pairCode = SharedStorage.shared.pairCode
        self.relayBaseURL = SharedStorage.shared.relayBaseURL
        self.partnerOwnerName = SharedStorage.shared.partnerOwnerName
        self.partnerPet = SharedStorage.shared.partnerPet
        self.partnerMessage = SharedStorage.shared.partnerMessage
        self.activeRareInteraction = SharedStorage.shared.rareInteraction

        refreshConnectionBadge()
        if let rare = activeRareInteraction {
            scheduleRareInteractionExpiry(rare)
        }
    }

    // MARK: - Key Derivation & End-to-End Encryption (AES-256-GCM)

    public static func topicName(forPairCode code: String) -> String {
        let normalized = SharedStorage.normalizePairCode(code)
        let input = Data("islandpup-topic-v3:\(normalized)".utf8)
        let digest = SHA256.hash(data: input)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "islandpup-\(hex.prefix(24))"
    }

    private static func encryptionKey(forPairCode code: String) -> SymmetricKey {
        let normalized = SharedStorage.normalizePairCode(code)
        let input = Data("islandpup-aesgcm-v3:\(normalized)".utf8)
        let digest = SHA256.hash(data: input)
        return SymmetricKey(data: Data(digest))
    }

    public static func encryptWireMessage(_ message: PairWireMessage, pairCode: String) -> Data? {
        var candidate = message
        for attempt in 0..<2 {
            if attempt == 1, let frames = candidate.petSnapshot.customMicroFrames, frames.count > 1 {
                candidate.petSnapshot.customMicroFrames = [frames[0]]
            }
            guard let plaintext = try? JSONEncoder().encode(candidate) else { return nil }
            let key = encryptionKey(forPairCode: pairCode)
            guard let sealed = try? AES.GCM.seal(plaintext, using: key),
                  let combined = sealed.combined else {
                return nil
            }
            let encoded = "v3:\(combined.base64EncodedString())"
            if encoded.utf8.count <= maxCiphertextChars || attempt == 1 {
                return Data(encoded.utf8)
            }
        }
        return nil
    }

    public static func decryptWireMessage(_ text: String, pairCode: String) -> PairWireMessage? {
        guard text.count <= maxCiphertextChars,
              text.hasPrefix("v3:") else {
            return nil
        }
        let b64 = String(text.dropFirst(3))
        guard let combined = Data(base64Encoded: b64) else { return nil }
        let key = encryptionKey(forPairCode: pairCode)
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(box, using: key),
              let wire = try? JSONDecoder().decode(PairWireMessage.self, from: plaintext) else {
            return nil
        }
        return wire
    }

    private var activeTopicURLString: String? {
        guard !pairCode.isEmpty else { return nil }
        let topic = Self.topicName(forPairCode: pairCode)
        return "\(storage.relayBaseURL)/\(topic)"
    }

    public var myPetSnapshot: IslandPetSnapshot {
        petStore.makeSnapshot(for: myPetProfile, action: myAction)
    }

    // MARK: - Pet Roster, Custom Spritesheets & Naming

    public func selectPet(_ profile: PetProfile) async {
        storage.selectedPetID = profile.id
        roster = petStore.loadRoster()
        myPetProfile = storage.selectedPetProfile
        await pushStateToActiveLiveActivities()
        if storage.isPaired {
            _ = await broadcastMyPetState(isExplicitUpdate: true)
        }
        showToast("\(myPetProfile.name) is now your active pet!")
    }

    public func renamePet(id: String, newName: String, colorPreset: PetColorPreset? = nil) async {
        guard let updated = petStore.updatePet(id: id, name: newName, colorPreset: colorPreset) else {
            return
        }
        roster = petStore.loadRoster()
        if myPetProfile.id == updated.id {
            myPetProfile = updated
            await pushStateToActiveLiveActivities()
            if storage.isPaired {
                _ = await broadcastMyPetState(isExplicitUpdate: true)
            }
        }
        showToast("Named pet “\(updated.name)”")
    }

    public func addCustomPet(
        from image: UIImage,
        name: String,
        colorPreset: PetColorPreset,
        layout: SpritesheetLayoutMode
    ) async throws -> PetProfile {
        let created = try petStore.importSpritesheet(
            from: image,
            name: name,
            colorPreset: colorPreset,
            layout: layout
        )
        roster = petStore.loadRoster()
        storage.selectedPetID = created.id
        myPetProfile = created
        await pushStateToActiveLiveActivities()
        if storage.isPaired {
            _ = await broadcastMyPetState(isExplicitUpdate: true)
        }
        showToast("Created \(created.name) and sent to Dynamic Island!")
        return created
    }

    public func deleteCustomPet(id: String) async {
        petStore.deleteCustomPet(id: id)
        roster = petStore.loadRoster()
        myPetProfile = storage.selectedPetProfile
        await pushStateToActiveLiveActivities()
        if storage.isPaired {
            _ = await broadcastMyPetState(isExplicitUpdate: false)
        }
    }

    // MARK: - Setting My Pet's Action (Updates My Phone + Partner's Phone)

    public func setMyPetAction(_ action: PetAction, message: String? = nil) async {
        myAction = action
        storage.myAction = action

        if let message {
            let cleaned = Self.cleanOptionalMessage(message)
            myMessage = cleaned
            storage.myMessage = cleaned
        }

        await pushStateToActiveLiveActivities()

        if storage.isPaired {
            let ok = await broadcastMyPetState(isExplicitUpdate: true)
            if ok {
                if let myMessage, !myMessage.isEmpty {
                    showToast("\(myPetProfile.name) → \(action.title) \(action.emoji) • Sent to partner!")
                } else {
                    showToast("\(myPetProfile.name) is now \(action.title) \(action.emoji) on both phones!")
                }
                // Small chance of triggering a spontaneous 2-dog interaction shortly after an update
                await maybeRollRareInteraction(probability: 0.14)
            } else {
                showToast("Updated locally (couldn't reach partner relay)")
            }
        } else {
            showToast("\(myPetProfile.name) is now \(action.title) \(action.emoji)")
        }
    }

    public func clearMyMessage() async {
        myMessage = nil
        storage.myMessage = nil
        await pushStateToActiveLiveActivities()
        if storage.isPaired {
            _ = await broadcastMyPetState(isExplicitUpdate: false)
        }
    }

    public func handleDynamicIslandActionTap(_ action: PetAction) async {
        reloadFromStorage()
        await setMyPetAction(action, message: nil)
        if storage.isPaired {
            await pollLatestMessages()
        }
    }

    // MARK: - Pairing Lifecycle

    public func joinPairRoom(code: String) async {
        let normalized = SharedStorage.normalizePairCode(code)
        guard !normalized.isEmpty else { return }

        NotificationManager.shared.configureAndRequestPermission()

        let isNewRoom = normalized != pairCode
        pairCode = normalized
        storage.pairCode = normalized

        if isNewRoom {
            storage.clearPartnerMetadata()
            partnerOwnerName = nil
            partnerPet = nil
            partnerMessage = nil
            activeRareInteraction = nil
        }

        connectionStatus = .connecting
        startRealtimeListeners()
        _ = await broadcastMyPetState(isExplicitUpdate: false)
        await pollLatestMessages()
        await pushStateToActiveLiveActivities()
    }

    public func leavePairRoom() async {
        stopRealtimeListeners()
        rareExpiryTask?.cancel()
        pairCode = ""
        storage.pairCode = ""
        storage.clearPartnerMetadata()
        partnerOwnerName = nil
        partnerPet = nil
        partnerMessage = nil
        activeRareInteraction = nil
        connectionStatus = .unpaired
        await pushStateToActiveLiveActivities()
    }

    public func startRealtimeListeners() {
        stopRealtimeListeners()
        guard let base = activeTopicURLString,
              let streamURL = URL(string: "\(base)/json") else {
            connectionStatus = .unpaired
            return
        }

        refreshConnectionBadge()

        streamTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    var request = URLRequest(url: streamURL)
                    request.timeoutInterval = 300
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                        await MainActor.run {
                            self?.refreshConnectionBadge(connected: true)
                        }
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            await self?.handleEnvelopeLine(line)
                        }
                    }
                } catch {
                    if Task.isCancelled { break }
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }

        heartbeatPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollLatestMessages()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }

        // Background spontaneous rare 2-dog interaction roller while both phones are paired
        rareRollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 26_000_000_000)
                if Task.isCancelled { break }
                await self?.maybeRollRareInteraction(probability: 0.10)
            }
        }
    }

    public func stopRealtimeListeners() {
        streamTask?.cancel()
        streamTask = nil
        heartbeatPollTask?.cancel()
        heartbeatPollTask = nil
        rareRollTask?.cancel()
        rareRollTask = nil
    }

    // MARK: - Spontaneous Rare Two-Dog Interactions

    private func maybeRollRareInteraction(probability: Double) async {
        guard storage.isPaired,
              partnerPet != nil,
              activeRareInteraction == nil else {
            return
        }

        let now = Date().timeIntervalSince1970
        guard now - storage.lastRareInteractionAt >= Self.rareInteractionCooldown else {
            return
        }

        var rng = SystemRandomNumberGenerator()
        let roll = Double.random(in: 0..<1, using: &rng)
        guard roll < probability,
              let chosenKind = RareInteractionKind.allCases.randomElement(using: &rng) else {
            return
        }

        let event = RarePetInteraction(kind: chosenKind, startedAt: now, duration: 36)
        await applyRareInteraction(event, broadcastToPartner: true)
    }

    private func applyRareInteraction(_ event: RarePetInteraction, broadcastToPartner: Bool) async {
        guard event.isActive(), let partnerPet else { return }
        storage.lastRareInteractionAt = event.startedAt
        storage.rareInteraction = event
        activeRareInteraction = event
        scheduleRareInteractionExpiry(event)

        let description = event.kind.descriptionText(
            myPetName: myPetProfile.name,
            partnerPetName: partnerPet.name
        )
        showToast("✨ \(description) \(event.kind.badgeEmoji)")
        await pushStateToActiveLiveActivities()

        if broadcastToPartner {
            let wire = PairWireMessage(
                kind: .rareInteraction,
                senderDeviceId: storage.deviceId,
                senderOwnerName: storage.myName,
                petSnapshot: myPetSnapshot,
                message: myMessage,
                isExplicitUpdate: false,
                rareInteraction: event
            )
            _ = await postWireMessage(wire)
        }
    }

    private func scheduleRareInteractionExpiry(_ event: RarePetInteraction) {
        rareExpiryTask?.cancel()
        let remaining = max(0.5, event.expiresAt - Date().timeIntervalSince1970 + 0.3)
        rareExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.activeRareInteraction?.id == event.id {
                self.activeRareInteraction = nil
                self.storage.rareInteraction = nil
                await self.pushStateToActiveLiveActivities()
            }
        }
    }

    // MARK: - Broadcasting & Catch-up Polling

    @discardableResult
    public func broadcastMyPetState(isExplicitUpdate: Bool) async -> Bool {
        guard storage.isPaired else { return false }
        let wire = PairWireMessage(
            kind: .petState,
            senderDeviceId: storage.deviceId,
            senderOwnerName: storage.myName,
            petSnapshot: myPetSnapshot,
            message: myMessage,
            isExplicitUpdate: isExplicitUpdate
        )
        return await postWireMessage(wire)
    }

    public func pollLatestMessages() async {
        reloadFromStorage()
        guard let base = activeTopicURLString,
              let pollURL = URL(string: "\(base)/json?poll=1&since=12h") else {
            return
        }

        do {
            var request = URLRequest(url: pollURL)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 262_144,
                  let text = String(data: data, encoding: .utf8) else {
                return
            }

            let wasFirstPartnerLink = (partnerPet == nil)
            let lines = text.split(whereSeparator: \.isNewline)
            var latestAlertBody: String?
            var didChange = false

            for sub in lines {
                let outcome = await processEnvelopeJSONLine(String(sub))
                if outcome.didMutate {
                    didChange = true
                }
                if let alert = outcome.alertBannerText {
                    latestAlertBody = alert
                }
            }

            refreshConnectionBadge(connected: true)

            if didChange {
                await pushStateToActiveLiveActivities(alertText: latestAlertBody)
                if wasFirstPartnerLink && partnerPet != nil {
                    _ = await broadcastMyPetState(isExplicitUpdate: false)
                }
            }
        } catch {
            // Preserve current state quietly on transient network error
        }
    }

    // MARK: - Internal Encrypted Wire Processing

    private func postWireMessage(_ message: PairWireMessage) async -> Bool {
        guard !pairCode.isEmpty,
              let base = activeTopicURLString,
              let url = URL(string: base),
              let encryptedBody = Self.encryptWireMessage(message, pairCode: pairCode) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = encryptedBody

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    private func handleEnvelopeLine(_ line: String) async {
        let wasUnlinked = (partnerPet == nil)
        let outcome = await processEnvelopeJSONLine(line)
        if outcome.didMutate {
            await pushStateToActiveLiveActivities(alertText: outcome.alertBannerText)
            if wasUnlinked && partnerPet != nil {
                _ = await broadcastMyPetState(isExplicitUpdate: false)
            }
        }
    }

    private struct ProcessOutcome {
        var didMutate: Bool
        var alertBannerText: String?
    }

    private func processEnvelopeJSONLine(_ line: String) async -> ProcessOutcome {
        guard !pairCode.isEmpty,
              line.utf8.count <= Self.maxEnvelopeLineBytes,
              let lineData = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(NtfyEnvelope.self, from: lineData),
              envelope.event == "message",
              let inner = envelope.message,
              let wire = Self.decryptWireMessage(inner, pairCode: pairCode) else {
            return ProcessOutcome(didMutate: false, alertBannerText: nil)
        }

        let cleanSenderId = String(wire.senderDeviceId.prefix(64))
        guard !cleanSenderId.isEmpty, cleanSenderId != storage.deviceId else {
            return ProcessOutcome(didMutate: false, alertBannerText: nil)
        }

        let now = Date().timeIntervalSince1970
        guard wire.sentAt <= now + Self.maxFutureClockSkewSeconds,
              wire.sentAt >= now - Self.maxMessageAgeSeconds else {
            return ProcessOutcome(didMutate: false, alertBannerText: nil)
        }

        // Handle incoming Rare Two-Dog Interaction
        if wire.kind == .rareInteraction, let incomingRare = wire.rareInteraction, incomingRare.isActive(at: now) {
            let sanitizedPartner = Self.sanitizeIncomingSnapshot(wire.petSnapshot)
            partnerPet = sanitizedPartner
            storage.partnerPet = sanitizedPartner

            if activeRareInteraction?.id != incomingRare.id {
                await applyRareInteraction(incomingRare, broadcastToPartner: false)
                NotificationManager.shared.postRareInteractionNotification(
                    myPetName: myPetProfile.name,
                    partnerPetName: sanitizedPartner.name,
                    interaction: incomingRare
                )
                return ProcessOutcome(didMutate: true, alertBannerText: nil)
            }
            return ProcessOutcome(didMutate: false, alertBannerText: nil)
        }

        // Ignore older out-of-order state packets
        guard wire.sentAt >= storage.lastAppliedRemoteSentAt else {
            return ProcessOutcome(didMutate: false, alertBannerText: nil)
        }

        let isStrictlyNewer = wire.sentAt > storage.lastAppliedRemoteSentAt
        storage.lastAppliedRemoteSentAt = wire.sentAt

        let rawOwner = SharedStorage.sanitizeDisplayText(wire.senderOwnerName, maxLength: 20)
        let safeOwner = rawOwner.isEmpty ? "Partner" : rawOwner
        let safeSnapshot = Self.sanitizeIncomingSnapshot(wire.petSnapshot)
        let safeMessage = Self.cleanOptionalMessage(wire.message)

        partnerOwnerName = safeOwner
        partnerPet = safeSnapshot
        partnerMessage = safeMessage

        storage.partnerOwnerName = safeOwner
        storage.partnerPet = safeSnapshot
        storage.partnerMessage = safeMessage

        refreshConnectionBadge(connected: true)

        var alertText: String?
        if isStrictlyNewer && wire.isExplicitUpdate && wire.sentAt > storage.lastNotifiedRemoteSentAt {
            storage.lastNotifiedRemoteSentAt = wire.sentAt
            NotificationManager.shared.postPartnerUpdateNotification(
                partnerPetName: safeSnapshot.name,
                partnerOwnerName: safeOwner,
                action: safeSnapshot.action,
                partnerMessage: safeMessage,
                dedupeKey: String(format: "%.3f", wire.sentAt)
            )
            if let safeMessage, !safeMessage.isEmpty {
                alertText = "\(safeSnapshot.name): “\(safeMessage)”"
                showToast("💬 \(safeSnapshot.name): “\(safeMessage)”")
            } else {
                showToast("\(safeSnapshot.name) \(safeSnapshot.action.statusPhrase) \(safeSnapshot.action.emoji)")
            }
        }

        return ProcessOutcome(didMutate: isStrictlyNewer, alertBannerText: alertText)
    }

    private static func sanitizeIncomingSnapshot(_ raw: IslandPetSnapshot) -> IslandPetSnapshot {
        let cleanName = SharedStorage.sanitizeDisplayText(raw.name, maxLength: 18)
        let finalName = cleanName.isEmpty ? (raw.builtInCharacter?.defaultName ?? "Buddy") : cleanName
        let cleanID = String(raw.id.prefix(64))

        // Enforce strict frame count & byte size bounds on remote custom sprite blobs
        let boundedFrames: [Data]?
        if raw.builtInCharacter != nil {
            boundedFrames = nil
        } else if let frames = raw.customMicroFrames {
            let valid = frames.prefix(2).filter { !$0.isEmpty && $0.count <= 1024 }
            boundedFrames = valid.isEmpty ? nil : Array(valid)
        } else {
            boundedFrames = nil
        }

        return IslandPetSnapshot(
            id: cleanID.isEmpty ? "remote-pet" : cleanID,
            name: finalName,
            builtInCharacter: raw.builtInCharacter,
            customSheetID: nil,
            colorPreset: raw.colorPreset,
            action: raw.action,
            customMicroFrames: boundedFrames
        )
    }

    private func reloadFromStorage() {
        roster = petStore.loadRoster()
        myPetProfile = storage.selectedPetProfile
        myAction = storage.myAction
        myMessage = storage.myMessage
        myName = storage.myName
        pairCode = storage.pairCode
        partnerOwnerName = storage.partnerOwnerName
        partnerPet = storage.partnerPet
        partnerMessage = storage.partnerMessage
        activeRareInteraction = storage.rareInteraction
    }

    private func refreshConnectionBadge(connected: Bool = false) {
        guard !pairCode.isEmpty else {
            connectionStatus = .unpaired
            return
        }
        if let partnerPet {
            connectionStatus = .partnerLinked(petName: partnerPet.name)
        } else {
            connectionStatus = connected ? .listening : .connecting
        }
    }

    private func showToast(_ text: String) {
        toastMessage = text
    }

    private static func cleanOptionalMessage(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = SharedStorage.sanitizeDisplayText(raw, maxLength: 72)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Live Activity Sync

    public func pushStateToActiveLiveActivities(alertText: String? = nil) async {
        let state = storage.currentContentState()
        let staleDate = state.activeInteraction.map { Date(timeIntervalSince1970: $0.expiresAt) }
        let content = ActivityContent(state: state, staleDate: staleDate)

        var alertConfig: AlertConfiguration?
        if let alertText, !alertText.isEmpty {
            let titleRes: LocalizedStringResource = "IslandPup"
            let bodyRes: LocalizedStringResource = "\(alertText)"
            alertConfig = AlertConfiguration(
                title: titleRes,
                body: bodyRes,
                sound: .default
            )
        }

        for activity in Activity<PetActivityAttributes>.activities {
            if let alertConfig {
                await activity.update(content, alertConfiguration: alertConfig)
            } else {
                await activity.update(content)
            }
        }
    }
}
