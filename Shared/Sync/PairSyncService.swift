import ActivityKit
import Combine
import CryptoKit
import Foundation
import UIKit

/// End-to-end encrypted (`AES-256-GCM`) wire payload synchronizing each pet, custom sprites,
/// pet name, chosen Emotion/Task, message, and combined two-dog interactions.
public struct PairWireMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case petState = "pet_state"
        case rareInteraction = "rare_interaction"
    }

    public var kind: Kind
    public var senderDeviceId: String
    public var senderOwnerName: String?
    public var petSnapshot: IslandPetSnapshot
    public var message: String?
    public var isExplicitUpdate: Bool
    public var notifyMessage: Bool?
    public var rareInteraction: RarePetInteraction?
    public var sentAt: TimeInterval

    public init(
        kind: Kind,
        senderDeviceId: String,
        senderOwnerName: String? = "",
        petSnapshot: IslandPetSnapshot,
        message: String? = nil,
        isExplicitUpdate: Bool = false,
        notifyMessage: Bool? = nil,
        rareInteraction: RarePetInteraction? = nil,
        sentAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.kind = kind
        self.senderDeviceId = senderDeviceId
        self.senderOwnerName = senderOwnerName
        self.petSnapshot = petSnapshot
        self.message = message
        self.isExplicitUpdate = isExplicitUpdate
        self.notifyMessage = notifyMessage
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
    private static let randomInteractionCooldown: TimeInterval = 180
    private static let clashInteractionCooldown: TimeInterval = 28
    private static let ultraRareSkitCooldown: TimeInterval = 2_700 // 45-minute cooldown between ultra-rare story skits

    private static let cryptoCacheLock = NSLock()
    private static var cachedTopicPair: (code: String, topic: String)?
    private static var cachedSymmetricKey: (code: String, key: SymmetricKey)?

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
    @Published public private(set) var activeSoloQuirk: SoloPetQuirk?
    @Published public private(set) var connectionStatus: ConnectionStatus = .unpaired
    @Published public var toastMessage: String?

    private let storage = SharedStorage.shared
    private let petStore = CustomPetStore.shared
    private let requestSession: URLSession
    private let streamSession: URLSession
    private var streamTask: Task<Void, Never>?
    private var fallbackPollTask: Task<Void, Never>?
    private var rareRollTask: Task<Void, Never>?
    private var rareExpiryTask: Task<Void, Never>?
    private var soloQuirkExpiryTask: Task<Void, Never>?
    private var isStreamConnected: Bool = false
    private var processedEnvelopeIDs: Set<String> = []
    private var processedEnvelopeOrder: [String] = []
    private var lastPushedContentState: PetActivityAttributes.ContentState?
    private var recentSwitchTimestamps: [TimeInterval] = []
    private var recentBoopTimestamps: [TimeInterval] = []

    private init() {
        let reqConfig = URLSessionConfiguration.ephemeral
        reqConfig.timeoutIntervalForRequest = 8
        reqConfig.timeoutIntervalForResource = 10
        reqConfig.urlCache = nil
        reqConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.requestSession = URLSession(configuration: reqConfig)

        let streamConfig = URLSessionConfiguration.ephemeral
        streamConfig.timeoutIntervalForRequest = 120
        streamConfig.timeoutIntervalForResource = 3600
        streamConfig.waitsForConnectivity = true
        streamConfig.urlCache = nil
        streamConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.streamSession = URLSession(configuration: streamConfig)

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
        self.activeSoloQuirk = SharedStorage.shared.soloQuirk

        refreshConnectionBadge()
        if let rare = activeRareInteraction {
            scheduleRareInteractionExpiry(rare)
        }
        if let quirk = activeSoloQuirk {
            scheduleSoloQuirkExpiry(quirk)
        }
    }

    // MARK: - Key Derivation & End-to-End Encryption (AES-256-GCM)

    public static func topicName(forPairCode code: String) -> String {
        let normalized = SharedStorage.normalizePairCode(code)
        cryptoCacheLock.lock()
        if let cached = cachedTopicPair, cached.code == normalized {
            cryptoCacheLock.unlock()
            return cached.topic
        }
        cryptoCacheLock.unlock()

        let input = Data("islandpup-topic-v3:\(normalized)".utf8)
        let digest = SHA256.hash(data: input)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let topic = "islandpup-\(hex.prefix(24))"

        cryptoCacheLock.lock()
        cachedTopicPair = (normalized, topic)
        cryptoCacheLock.unlock()
        return topic
    }

    private static func encryptionKey(forPairCode code: String) -> SymmetricKey {
        let normalized = SharedStorage.normalizePairCode(code)
        cryptoCacheLock.lock()
        if let cached = cachedSymmetricKey, cached.code == normalized {
            cryptoCacheLock.unlock()
            return cached.key
        }
        cryptoCacheLock.unlock()

        let input = Data("islandpup-aesgcm-v3:\(normalized)".utf8)
        let digest = SHA256.hash(data: input)
        let key = SymmetricKey(data: Data(digest))

        cryptoCacheLock.lock()
        cachedSymmetricKey = (normalized, key)
        cryptoCacheLock.unlock()
        return key
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

    /// Lightweight in-memory snapshot for the in-app Dynamic Island preview (zero UserDefaults or JSON encoding).
    public var inAppPreviewState: PetActivityAttributes.ContentState {
        let paired = !pairCode.isEmpty
        let activeRare = paired && partnerPet != nil && (activeRareInteraction?.isActive() == true)
            ? activeRareInteraction
            : nil
        let activeQuirk = activeRare == nil && (activeSoloQuirk?.isActive() == true)
            ? activeSoloQuirk
            : nil
        let myPreviewPet = IslandPetSnapshot(
            id: myPetProfile.id,
            name: myPetProfile.name,
            builtInCharacter: myPetProfile.builtInCharacter,
            customSheetID: myPetProfile.customSheetID,
            colorPreset: myPetProfile.colorPreset,
            action: myAction,
            customMicroFrames: nil
        )
        return PetActivityAttributes.ContentState(
            myPet: myPreviewPet,
            myMessage: myMessage,
            isPaired: paired,
            partnerPet: partnerPet,
            partnerOwnerName: partnerOwnerName,
            partnerMessage: partnerMessage,
            rareInteraction: activeRare,
            soloQuirk: activeQuirk,
            anchorTimestamp: storage.stableAnchorTimestamp()
        )
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
        showToast("\(myPetProfile.name) is now active!")
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

    // MARK: - Emotions, Tasks, Messages & Interactive Triggers

    /// Updates ONLY your pet's Emotion/Task silently (no notification), checking special status triggers!
    public func setMyPetAction(_ action: PetAction) async {
        let now = Date().timeIntervalSince1970
        recentSwitchTimestamps = recentSwitchTimestamps.filter { now - $0 <= 10.0 }
        recentSwitchTimestamps.append(now)
        let isMoodWhiplash = recentSwitchTimestamps.count >= 4
        if isMoodWhiplash {
            recentSwitchTimestamps.removeAll()
        }

        myAction = action
        storage.myAction = action
        clearSoloQuirkLocally()

        var triggeredDuo: RarePetInteraction?
        if storage.isPaired, let connectedPet = partnerPet {
            if isMoodWhiplash {
                triggeredDuo = RarePetInteraction(
                    kind: .spinIntoDizzy,
                    triggerBadge: "🌀 MOOD WHIPLASH",
                    startedAt: now,
                    duration: 38
                )
            } else if connectedPet.action == action {
                let kind = Self.pickTwinStatusDuo(for: action)
                triggeredDuo = makeDuoEventWithRareSkitChance(
                    standardKind: kind,
                    standardBadge: "⚡ TWIN STATUS (\(action.title.uppercased()))",
                    now: now,
                    standardDuration: 44,
                    ultraRareProbability: 0.035
                )
            } else if now - storage.lastRareInteractionAt >= Self.clashInteractionCooldown,
                      let clashKind = Self.pickClashStatusDuo(first: action, second: connectedPet.action) {
                var rng = SystemRandomNumberGenerator()
                if Double.random(in: 0..<1, using: &rng) < 0.72 {
                    triggeredDuo = makeDuoEventWithRareSkitChance(
                        standardKind: clashKind,
                        standardBadge: "💥 SIBLING CLASH",
                        now: now,
                        standardDuration: 40,
                        ultraRareProbability: 0.03
                    )
                }
            }
        } else if isMoodWhiplash {
            let quirk = SoloPetQuirk(
                action: .dizzy,
                triggerBadge: "🌀 MOOD WHIPLASH",
                startedAt: now,
                duration: 30
            )
            applySoloQuirk(quirk, toastText: "🌀 \(myPetProfile.name) got dizzy from all the mood switches!")
        }

        if let triggeredDuo {
            await applyRareInteraction(triggeredDuo, broadcastToPartner: false, pushIslandNow: false)
        }

        await pushStateToActiveLiveActivities()

        if storage.isPaired {
            let ok = await broadcastMyPetState(
                isExplicitUpdate: true,
                notifyMessage: false,
                piggybackedRare: triggeredDuo
            )
            if ok {
                if triggeredDuo == nil {
                    showToast("\(myPetProfile.name) is now \(action.title) \(action.emoji)")
                    await maybeRollSpecialMoment(probability: 0.12)
                }
            } else if triggeredDuo == nil {
                showToast("Updated locally (couldn't reach sync relay)")
            }
        } else if !isMoodWhiplash {
            showToast("\(myPetProfile.name) is now \(action.title) \(action.emoji)")
        }
    }

    /// Sends a message that pushes a notification on the connected iPhone, plus checks secret phrase triggers!
    public func sendMyMessage(_ rawMessage: String, optionalAction: PetAction? = nil) async {
        guard let cleaned = Self.cleanOptionalMessage(rawMessage) else { return }
        let now = Date().timeIntervalSince1970

        if let optionalAction {
            myAction = optionalAction
            storage.myAction = optionalAction
        }
        myMessage = cleaned
        storage.myMessage = cleaned

        var triggeredDuo: RarePetInteraction?
        if storage.isPaired, let connectedPet = partnerPet {
            if let phraseDuo = Self.keywordTriggeredDuo(for: cleaned) {
                triggeredDuo = makeDuoEventWithRareSkitChance(
                    standardKind: phraseDuo,
                    standardBadge: "💬 MESSAGE REACTION",
                    now: now,
                    standardDuration: 44,
                    ultraRareProbability: 0.035
                )
            } else if let optionalAction, optionalAction == connectedPet.action {
                let twinKind = Self.pickTwinStatusDuo(for: optionalAction)
                triggeredDuo = makeDuoEventWithRareSkitChance(
                    standardKind: twinKind,
                    standardBadge: "⚡ TWIN STATUS (\(optionalAction.title.uppercased()))",
                    now: now,
                    standardDuration: 44,
                    ultraRareProbability: 0.035
                )
            }
        } else if let soloReaction = Self.keywordTriggeredSoloQuirk(for: cleaned) {
            let quirk = SoloPetQuirk(
                action: soloReaction,
                triggerBadge: "💬 MESSAGE REACTION",
                startedAt: now,
                duration: 32
            )
            applySoloQuirk(quirk, toastText: nil)
        }

        if let triggeredDuo {
            await applyRareInteraction(triggeredDuo, broadcastToPartner: false, pushIslandNow: false)
        }

        await pushStateToActiveLiveActivities()

        if storage.isPaired {
            let ok = await broadcastMyPetState(
                isExplicitUpdate: true,
                notifyMessage: true,
                piggybackedRare: triggeredDuo
            )
            if ok {
                if triggeredDuo == nil {
                    if let connectedPet = partnerPet {
                        showToast("💬 \(myPetProfile.name) → \(connectedPet.name): “\(cleaned)”")
                    } else {
                        showToast("💬 \(myPetProfile.name): “\(cleaned)”")
                    }
                    await maybeRollSpecialMoment(probability: 0.14)
                }
            } else {
                showToast("Saved locally (couldn't reach sync relay)")
            }
        } else {
            showToast("💬 \(myPetProfile.name): “\(cleaned)”")
        }
    }

    public func clearMyMessage() async {
        myMessage = nil
        storage.myMessage = nil
        await pushStateToActiveLiveActivities()
        if storage.isPaired {
            _ = await broadcastMyPetState(isExplicitUpdate: false, notifyMessage: false)
        }
    }

    /// Interactive snoot-boop (single tap) or dizzy spin (rapid triple-tap) on your pet!
    public func boopMyPet() async {
        let now = Date().timeIntervalSince1970
        recentBoopTimestamps = recentBoopTimestamps.filter { now - $0 <= 3.2 }
        recentBoopTimestamps.append(now)

        if recentBoopTimestamps.count >= 3 {
            recentBoopTimestamps.removeAll()
            if storage.isPaired, partnerPet != nil {
                let event = RarePetInteraction(
                    kind: .spinIntoDizzy,
                    triggerBadge: "🌀 TRIPLE BOOP",
                    startedAt: now,
                    duration: 38
                )
                await applyRareInteraction(event, broadcastToPartner: true, pushIslandNow: true)
            } else {
                let quirk = SoloPetQuirk(
                    action: .spinning,
                    triggerBadge: "🌀 TRIPLE BOOP",
                    startedAt: now,
                    duration: 28
                )
                applySoloQuirk(quirk, toastText: "🌀 \(myPetProfile.name) is spinning in circles!")
                await pushStateToActiveLiveActivities()
            }
            return
        }

        let quirk = SoloPetQuirk(
            action: .booping,
            triggerBadge: "🐽 SNOOT BOOP",
            startedAt: now,
            duration: 26
        )
        applySoloQuirk(quirk, toastText: "🐽 Booped \(myPetProfile.name)'s snoot!")
        await pushStateToActiveLiveActivities()
    }

    /// Triggers a surprise combined interaction (when paired) or rare solo quirk (when solo) on demand.
    public func triggerSurpriseSpecial() async {
        let now = Date().timeIntervalSince1970
        var rng = SystemRandomNumberGenerator()

        if storage.isPaired, partnerPet != nil {
            let canRollUltraRare = Double.random(in: 0..<1, using: &rng) < 0.04
            let candidatePool = canRollUltraRare
                ? RareInteractionKind.ultraRareSkitCases
                : RareInteractionKind.standardCases
            let pool = candidatePool.filter { $0 != activeRareInteraction?.kind }
            guard let chosen = pool.randomElement(using: &rng) ?? candidatePool.randomElement(using: &rng) else {
                return
            }
            let event = RarePetInteraction(
                kind: chosen,
                triggerBadge: chosen.isUltraRareLongSkit ? "🌟 ULTRA-RARE STORY SKIT" : "🎲 SURPRISE MOMENT",
                startedAt: now,
                duration: chosen.defaultDuration
            )
            await applyRareInteraction(event, broadcastToPartner: true, pushIslandNow: true)
        } else {
            let pool = PetAction.quirkActions.filter { $0 != activeSoloQuirk?.action }
            guard let chosen = pool.randomElement(using: &rng) ?? PetAction.quirkActions.first else {
                return
            }
            let quirk = SoloPetQuirk(
                action: chosen,
                triggerBadge: "🎲 SURPRISE QUIRK",
                startedAt: now,
                duration: 34
            )
            applySoloQuirk(quirk, toastText: "✨ \(myPetProfile.name) \(chosen.statusPhrase) \(chosen.emoji)")
            await pushStateToActiveLiveActivities()
        }
    }

    public func handleDynamicIslandActionTap(_ action: PetAction) async {
        reloadFromStorage()
        await setMyPetAction(action)
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
            processedEnvelopeIDs.removeAll()
            processedEnvelopeOrder.removeAll()
            partnerOwnerName = nil
            partnerPet = nil
            partnerMessage = nil
            activeRareInteraction = nil
        }

        stopRealtimeListeners()
        connectionStatus = .connecting
        startRealtimeListeners()
        _ = await broadcastMyPetState(isExplicitUpdate: false)
        await pollLatestMessages()
        await pushStateToActiveLiveActivities()
    }

    /// Ensures paired devices stay seamlessly linked on launch and across in-place IPA updates.
    public func handleAppBecameActive() async {
        let didUpgradeSchema = storage.consumeDidUpgradeSchemaIfNeeded()
        if didUpgradeSchema {
            reloadFromStorage()
        }
        guard storage.isPaired else {
            await pushStateToActiveLiveActivities()
            return
        }
        startRealtimeListeners()
        await pollLatestMessages()
        if didUpgradeSchema {
            _ = await broadcastMyPetState(isExplicitUpdate: false, notifyMessage: false)
        }
        await pushStateToActiveLiveActivities()
    }

    public func leavePairRoom() async {
        stopRealtimeListeners()
        rareExpiryTask?.cancel()
        pairCode = ""
        storage.pairCode = ""
        storage.clearPartnerMetadata()
        processedEnvelopeIDs.removeAll()
        processedEnvelopeOrder.removeAll()
        partnerOwnerName = nil
        partnerPet = nil
        partnerMessage = nil
        activeRareInteraction = nil
        connectionStatus = .unpaired
        await pushStateToActiveLiveActivities()
    }

    public func startRealtimeListeners() {
        if streamTask != nil {
            refreshConnectionBadge(connected: isStreamConnected)
            return
        }
        guard let base = activeTopicURLString,
              let streamURL = URL(string: "\(base)/json") else {
            connectionStatus = .unpaired
            return
        }

        refreshConnectionBadge()
        let session = streamSession

        streamTask = Task { [weak self] in
            var retryDelaySeconds: UInt64 = 3
            var didDisconnectOnce = false

            while !Task.isCancelled {
                do {
                    var request = URLRequest(url: streamURL)
                    request.timeoutInterval = 120
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                        retryDelaySeconds = 3
                        await MainActor.run {
                            self?.isStreamConnected = true
                            self?.refreshConnectionBadge(connected: true)
                        }
                        if didDisconnectOnce {
                            await self?.pollLatestMessages()
                        }
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            if line.contains("v3:") {
                                await self?.handleEnvelopeLine(line)
                            }
                        }
                    }
                } catch {
                    if Task.isCancelled { break }
                }

                await MainActor.run {
                    self?.isStreamConnected = false
                }
                didDisconnectOnce = true
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: retryDelaySeconds * 1_000_000_000)
                retryDelaySeconds = min(retryDelaySeconds * 2, 60)
            }
        }

        // Fallback poll runs ONLY when the live push stream is disconnected.
        fallbackPollTask = Task { [weak self] in
            while !Task.isCancelled {
                let intervalSeconds: UInt64 = ProcessInfo.processInfo.isLowPowerModeEnabled ? 240 : 120
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                if Task.isCancelled { break }
                let streamHealthy = await MainActor.run { self?.isStreamConnected ?? false }
                if !streamHealthy {
                    await self?.pollLatestMessages()
                }
            }
        }

        // Low-frequency spontaneous roller (paused automatically in Low Power Mode).
        rareRollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                if Task.isCancelled { break }
                await self?.maybeRollSpecialMoment(probability: 0.18)
            }
        }
    }

    public func stopRealtimeListeners() {
        isStreamConnected = false
        streamTask?.cancel()
        streamTask = nil
        fallbackPollTask?.cancel()
        fallbackPollTask = nil
        rareRollTask?.cancel()
        rareRollTask = nil
    }

    // MARK: - Special-Case Trigger Rules (Twin Match, Clash, Secret Words & Time-Weighted Chaos)

    private static func pickTwinStatusDuo(for action: PetAction) -> RareInteractionKind {
        var rng = SystemRandomNumberGenerator()
        let choices: [RareInteractionKind]
        switch action {
        case .sleeping:  choices = [.cozyNapTruce, .cozyNapTruce, .cozyNapTruce, .blanketHog]
        case .eating:    choices = [.doubleBegSquad, .stealingFood]
        case .walk:      choices = [.zoomieChase, .zoomieCrash]
        case .working:   choices = [.sharedBraincell, .interruptWork]
        case .review:    choices = [.sharedBraincell, .doubleSideEye]
        case .waiting:   choices = [.doubleBegSquad, .sittingOnHead]
        case .idle:      choices = [.sittingOnHead, .buttSniff]
        case .happy:     choices = [.tugOfWar, .biteyFace]
        case .celebrate: choices = [.zoomieChase, .spinIntoDizzy]
        case .waving:    choices = [.buttSniff, .tugOfWar]
        case .love:      choices = [.cheerUpLove]
        case .sad:       choices = [.cheerUpLove]
        case .confused:  choices = [.sharedBraincell, .blameEachOther]
        case .grumpy:    choices = [.barkArgument, .pawBonk]
        case .zoomies:   choices = [.zoomieCrash, .zoomieChase]
        case .begging:   choices = [.doubleBegSquad, .stealingFood]
        case .spinning, .dizzy: choices = [.spinIntoDizzy]
        case .booping:   choices = [.cheerUpLove, .pawBonk]
        case .splooting: choices = [.cozyNapTruce, .blanketHog]
        case .sideEye:   choices = [.doubleSideEye, .blameEachOther]
        case .blep:      choices = [.sharedBraincell, .sittingOnHead]
        }
        return choices.randomElement(using: &rng) ?? .cheerUpLove
    }

    private static func pickClashStatusDuo(first: PetAction, second: PetAction) -> RareInteractionKind? {
        guard first != second else { return nil }
        let pair: Set<PetAction> = [first, second]
        var rng = SystemRandomNumberGenerator()

        let focusSet: Set<PetAction> = [.working, .review]
        let energeticSet: Set<PetAction> = [.happy, .celebrate, .waving, .walk, .zoomies]
        if !pair.isDisjoint(with: focusSet) && !pair.isDisjoint(with: energeticSet) {
            return .interruptWork
        }

        if pair.contains(.eating) && !pair.isDisjoint(with: [.waiting, .sad, .begging, .grumpy, .confused]) {
            return [.foodEnvyBeg, .foodEnvyBeg, .stealingFood].randomElement(using: &rng)
        }

        if pair.contains(.sleeping) && !pair.isDisjoint(with: [.happy, .celebrate, .walk, .grumpy, .waving]) {
            return [.earNibbleAnnoy, .sittingOnHead].randomElement(using: &rng)
        }

        if pair.contains(.sad) && !pair.isDisjoint(with: [.love, .happy, .celebrate, .waving]) {
            return .cheerUpLove
        }

        if pair.contains(.grumpy) && !pair.isDisjoint(with: [.confused, .waiting, .idle]) {
            return [.blameEachOther, .doubleSideEye].randomElement(using: &rng)
        }

        if pair.contains(.grumpy) && !pair.isDisjoint(with: [.happy, .celebrate, .love]) {
            return .pawBonk
        }

        return nil
    }

    private static func keywordTriggeredDuo(for message: String) -> RareInteractionKind? {
        let lower = message.lowercased()
        var rng = SystemRandomNumberGenerator()

        if containsAny(lower, ["love", "miss u", "miss you", "hug", "kiss", "cuddle", "❤️", "💕", "🥰", "😘"]) {
            return .cheerUpLove
        }
        if containsAny(lower, ["goodnight", "gn", "sleep", "nap", "bedtime", "cozy", "🌙", "💤"]) {
            return [.cozyNapTruce, .cozyNapTruce, .blanketHog].randomElement(using: &rng)
        }
        if containsAny(lower, ["food", "hungry", "eat", "snack", "dinner", "lunch", "treat", "boba", "pizza", "🍖", "🍕", "🍔", "🍜"]) {
            return [.stealingFood, .doubleBegSquad, .foodEnvyBeg].randomElement(using: &rng)
        }
        if containsAny(lower, ["work", "busy", "meeting", "study", "focus", "coding", "wfh", "💻"]) {
            return .interruptWork
        }
        if containsAny(lower, ["sus", "side eye", "side-eye", "judge", "bruh", "👀", "😒"]) {
            return .doubleSideEye
        }
        if containsAny(lower, ["fault", "blame", "wasn't me", "wasnt me", "who did"]) {
            return .blameEachOther
        }
        if containsAny(lower, ["bonk", "mad", "hmph", "argue", "no!", "stop", "😤", "💢"]) {
            return [.pawBonk, .barkArgument, .earNibbleAnnoy].randomElement(using: &rng)
        }
        if containsAny(lower, ["zoom", "walk", "chase", "run", "play", "tug", "party", "🎉", "⚡"]) {
            return [.zoomieChase, .tugOfWar, .biteyFace, .zoomieCrash].randomElement(using: &rng)
        }
        if containsAny(lower, ["dizzy", "spin", "braincell", "confused", "🌀", "😵‍💫"]) {
            return [.spinIntoDizzy, .sharedBraincell].randomElement(using: &rng)
        }
        return nil
    }

    private static func keywordTriggeredSoloQuirk(for message: String) -> PetAction? {
        let lower = message.lowercased()
        if containsAny(lower, ["food", "hungry", "eat", "snack", "dinner", "lunch", "treat", "boba", "pizza", "🍖", "🍕"]) {
            return .begging
        }
        if containsAny(lower, ["sus", "side eye", "judge", "bruh", "👀", "😒"]) {
            return .sideEye
        }
        if containsAny(lower, ["lol", "lmao", "haha", "hehe", "silly", "blep", "😛", "😋"]) {
            return .blep
        }
        if containsAny(lower, ["tired", "exhausted", "dead", "melted", "done", "ugh", "🫠"]) {
            return .splooting
        }
        if containsAny(lower, ["omw", "hurry", "run", "zoom", "lets go", "let's go", "💨"]) {
            return .zoomies
        }
        if containsAny(lower, ["boop", "poke", "hi!", "miss u", "miss you", "🐽"]) {
            return .booping
        }
        if containsAny(lower, ["spin", "dizzy", "crazy", "🌀", "😵‍💫"]) {
            return .spinning
        }
        return nil
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func pickTimeWeightedRandomDuo() -> RareInteractionKind {
        var rng = SystemRandomNumberGenerator()
        let hour = Calendar.current.component(.hour, from: Date())
        var pool = RareInteractionKind.standardCases
        if hour >= 22 || hour < 7 {
            pool += [.cozyNapTruce, .cozyNapTruce, .blanketHog, .earNibbleAnnoy]
        } else if (11...13).contains(hour) || (18...20).contains(hour) {
            pool += [.stealingFood, .foodEnvyBeg, .doubleBegSquad]
        } else if (9...17).contains(hour) {
            pool += [.interruptWork, .sharedBraincell, .sittingOnHead, .tugOfWar]
        }
        return pool.randomElement(using: &rng) ?? .tugOfWar
    }

    private func makeDuoEventWithRareSkitChance(
        standardKind: RareInteractionKind,
        standardBadge: String,
        now: TimeInterval,
        standardDuration: TimeInterval,
        ultraRareProbability: Double
    ) -> RarePetInteraction {
        var rng = SystemRandomNumberGenerator()
        if now - storage.lastUltraRareSkitAt >= Self.ultraRareSkitCooldown,
           Double.random(in: 0..<1, using: &rng) < ultraRareProbability {
            let skit = standardKind.matchingUltraRareSkit
            if skit.isUltraRareLongSkit {
                return RarePetInteraction(
                    kind: skit,
                    triggerBadge: "🌟 ULTRA-RARE STORY SKIT",
                    startedAt: now,
                    duration: skit.defaultDuration
                )
            }
        }
        return RarePetInteraction(
            kind: standardKind,
            triggerBadge: standardBadge,
            startedAt: now,
            duration: standardDuration
        )
    }

    private func maybeRollSpecialMoment(probability: Double) async {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

        let now = Date().timeIntervalSince1970
        guard now - storage.lastRareInteractionAt >= Self.randomInteractionCooldown else {
            return
        }

        var rng = SystemRandomNumberGenerator()
        guard Double.random(in: 0..<1, using: &rng) < probability else {
            return
        }

        if storage.isPaired, partnerPet != nil, activeRareInteraction == nil {
            let rollUltraRare = (now - storage.lastUltraRareSkitAt >= Self.ultraRareSkitCooldown)
                && (Double.random(in: 0..<1, using: &rng) < 0.04)
            let chosen: RareInteractionKind
            if rollUltraRare, let randomSkit = RareInteractionKind.ultraRareSkitCases.randomElement(using: &rng) {
                chosen = randomSkit
            } else {
                chosen = Self.pickTimeWeightedRandomDuo()
            }
            let event = RarePetInteraction(
                kind: chosen,
                triggerBadge: chosen.isUltraRareLongSkit ? "🌟 ULTRA-RARE STORY SKIT" : "🎲 RANDOM CHAOS",
                startedAt: now,
                duration: chosen.isUltraRareLongSkit ? chosen.defaultDuration : 40
            )
            await applyRareInteraction(event, broadcastToPartner: true, pushIslandNow: true)
        } else if !storage.isPaired, activeSoloQuirk == nil {
            guard let quirkAction = PetAction.quirkActions.randomElement(using: &rng) else { return }
            storage.lastRareInteractionAt = now
            let quirk = SoloPetQuirk(
                action: quirkAction,
                triggerBadge: "🎲 RANDOM QUIRK",
                startedAt: now,
                duration: 32
            )
            applySoloQuirk(quirk, toastText: "✨ \(myPetProfile.name) \(quirkAction.statusPhrase) \(quirkAction.emoji)")
            await pushStateToActiveLiveActivities()
        }
    }

    private func applyRareInteraction(
        _ event: RarePetInteraction,
        broadcastToPartner: Bool,
        pushIslandNow: Bool
    ) async {
        guard event.isActive(), let partnerPet else { return }
        clearSoloQuirkLocally()
        storage.lastRareInteractionAt = event.startedAt
        if event.kind.isUltraRareLongSkit {
            storage.lastUltraRareSkitAt = event.startedAt
        }
        storage.rareInteraction = event
        activeRareInteraction = event
        scheduleRareInteractionExpiry(event)

        let description = event.kind.descriptionText(
            myPetName: myPetProfile.name,
            partnerPetName: partnerPet.name
        )
        showToast("\(event.kind.badgeEmoji) \(description)")

        if pushIslandNow {
            await pushStateToActiveLiveActivities()
        }

        if broadcastToPartner {
            let wire = PairWireMessage(
                kind: .rareInteraction,
                senderDeviceId: storage.deviceId,
                senderOwnerName: "",
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

    private func applySoloQuirk(_ quirk: SoloPetQuirk, toastText: String?) {
        storage.soloQuirk = quirk
        activeSoloQuirk = quirk
        scheduleSoloQuirkExpiry(quirk)
        if let toastText {
            showToast(toastText)
        }
    }

    private func clearSoloQuirkLocally() {
        soloQuirkExpiryTask?.cancel()
        soloQuirkExpiryTask = nil
        activeSoloQuirk = nil
        storage.soloQuirk = nil
    }

    private func scheduleSoloQuirkExpiry(_ quirk: SoloPetQuirk) {
        soloQuirkExpiryTask?.cancel()
        let remaining = max(0.5, quirk.expiresAt - Date().timeIntervalSince1970 + 0.3)
        soloQuirkExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.activeSoloQuirk?.id == quirk.id {
                if quirk.action == .spinning {
                    let dizzyFollowUp = SoloPetQuirk(
                        action: .dizzy,
                        triggerBadge: "😵‍💫 SPUN OUT",
                        duration: 18
                    )
                    self.applySoloQuirk(dizzyFollowUp, toastText: nil)
                } else {
                    self.activeSoloQuirk = nil
                    self.storage.soloQuirk = nil
                }
                await self.pushStateToActiveLiveActivities()
            }
        }
    }

    // MARK: - Broadcasting & Incremental Catch-up Polling

    @discardableResult
    public func broadcastMyPetState(
        isExplicitUpdate: Bool,
        notifyMessage: Bool = false,
        piggybackedRare: RarePetInteraction? = nil
    ) async -> Bool {
        guard storage.isPaired else { return false }
        let wire = PairWireMessage(
            kind: .petState,
            senderDeviceId: storage.deviceId,
            senderOwnerName: "",
            petSnapshot: myPetSnapshot,
            message: myMessage,
            isExplicitUpdate: isExplicitUpdate,
            notifyMessage: notifyMessage,
            rareInteraction: piggybackedRare
        )
        return await postWireMessage(wire)
    }

    public func pollLatestMessages() async {
        reloadFromStorage()
        let lastServerTime = storage.lastRelayEnvelopeTime
        let sinceParam = lastServerTime > 0 ? "\(max(1, lastServerTime - 2))" : "12h"
        guard let base = activeTopicURLString,
              let pollURL = URL(string: "\(base)/json?poll=1&since=\(sinceParam)") else {
            return
        }

        do {
            var request = URLRequest(url: pollURL)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await requestSession.data(for: request)
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
            let (_, response) = try await requestSession.data(for: request)
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

    private func rememberEnvelopeID(_ id: String) -> Bool {
        if processedEnvelopeIDs.contains(id) {
            return false
        }
        processedEnvelopeIDs.insert(id)
        processedEnvelopeOrder.append(id)
        if processedEnvelopeOrder.count > 64 {
            let oldest = processedEnvelopeOrder.removeFirst()
            processedEnvelopeIDs.remove(oldest)
        }
        return true
    }

    private func processEnvelopeJSONLine(_ line: String) async -> ProcessOutcome {
        guard !pairCode.isEmpty,
              line.utf8.count <= Self.maxEnvelopeLineBytes,
              line.contains("v3:"),
              let lineData = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(NtfyEnvelope.self, from: lineData),
              envelope.event == "message",
              let inner = envelope.message else {
            return ProcessOutcome(didMutate: false, alertBannerText: nil)
        }

        if let envID = envelope.id, !envID.isEmpty, !rememberEnvelopeID(envID) {
            return ProcessOutcome(didMutate: false, alertBannerText: nil)
        }

        guard let wire = Self.decryptWireMessage(inner, pairCode: pairCode) else {
            return ProcessOutcome(didMutate: false, alertBannerText: nil)
        }

        if let serverTime = envelope.time, serverTime > storage.lastRelayEnvelopeTime {
            storage.lastRelayEnvelopeTime = serverTime
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

        // Handle dedicated Rare Two-Dog Interaction packets (silent, no notification)
        if wire.kind == .rareInteraction, let incomingRare = wire.rareInteraction, incomingRare.isActive(at: now) {
            let sanitizedPartner = Self.sanitizeIncomingSnapshot(wire.petSnapshot)
            partnerPet = sanitizedPartner
            storage.partnerPet = sanitizedPartner

            if activeRareInteraction?.id != incomingRare.id {
                await applyRareInteraction(incomingRare, broadcastToPartner: false, pushIslandNow: false)
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

        let safeSnapshot = Self.sanitizeIncomingSnapshot(wire.petSnapshot)
        let safeMessage = Self.cleanOptionalMessage(wire.message)

        partnerOwnerName = nil
        partnerPet = safeSnapshot
        partnerMessage = safeMessage

        storage.partnerOwnerName = nil
        storage.partnerPet = safeSnapshot
        storage.partnerMessage = safeMessage

        refreshConnectionBadge(connected: true)

        var didApplyRare = false
        if let incomingRare = wire.rareInteraction, incomingRare.isActive(at: now),
           activeRareInteraction?.id != incomingRare.id {
            await applyRareInteraction(incomingRare, broadcastToPartner: false, pushIslandNow: false)
            didApplyRare = true
        } else if isStrictlyNewer,
                  wire.isExplicitUpdate,
                  safeSnapshot.action == myAction,
                  activeRareInteraction == nil {
            // Receiver-side Twin Status Match safety net when both pets land on the exact same status!
            let twinKind = Self.pickTwinStatusDuo(for: myAction)
            let twinEvent = makeDuoEventWithRareSkitChance(
                standardKind: twinKind,
                standardBadge: "⚡ TWIN STATUS (\(myAction.title.uppercased()))",
                now: now,
                standardDuration: 44,
                ultraRareProbability: 0.035
            )
            await applyRareInteraction(twinEvent, broadcastToPartner: true, pushIslandNow: false)
            didApplyRare = true
        }

        var alertText: String?
        if isStrictlyNewer,
           wire.notifyMessage == true,
           let safeMessage, !safeMessage.isEmpty,
           wire.sentAt > storage.lastNotifiedRemoteSentAt {
            storage.lastNotifiedRemoteSentAt = wire.sentAt
            NotificationManager.shared.postPartnerMessageNotification(
                partnerPetName: safeSnapshot.name,
                partnerMessage: safeMessage,
                dedupeKey: String(format: "%.3f", wire.sentAt)
            )
            alertText = "\(safeSnapshot.name): “\(safeMessage)”"
            showToast("💬 \(safeSnapshot.name): “\(safeMessage)”")
        } else if isStrictlyNewer && wire.isExplicitUpdate && !didApplyRare {
            showToast("\(safeSnapshot.name) \(safeSnapshot.action.statusPhrase) \(safeSnapshot.action.emoji)")
        }

        return ProcessOutcome(didMutate: isStrictlyNewer || didApplyRare, alertBannerText: alertText)
    }

    private static func sanitizeIncomingSnapshot(_ raw: IslandPetSnapshot) -> IslandPetSnapshot {
        let cleanName = SharedStorage.sanitizeDisplayText(raw.name, maxLength: 18)
        let finalName = cleanName.isEmpty ? (raw.builtInCharacter?.defaultName ?? "Buddy") : cleanName
        let cleanID = String(raw.id.prefix(64))

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
        activeSoloQuirk = storage.soloQuirk
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

    public func recordPushedState(_ state: PetActivityAttributes.ContentState?) {
        lastPushedContentState = state
    }

    public func pushStateToActiveLiveActivities(alertText: String? = nil) async {
        let activities = Activity<PetActivityAttributes>.activities
        guard !activities.isEmpty else {
            lastPushedContentState = nil
            return
        }

        let state = storage.currentContentState()
        let hasAlert = (alertText != nil && !(alertText?.isEmpty ?? true))
        if !hasAlert, state == lastPushedContentState {
            return
        }
        lastPushedContentState = state

        let content = ActivityContent(state: state, staleDate: state.nextExpiryDate)

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

        for activity in activities {
            if let alertConfig {
                await activity.update(content, alertConfiguration: alertConfig)
            } else {
                await activity.update(content)
            }
        }
    }
}
