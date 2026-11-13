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
    public var messageSentAt: TimeInterval?
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
        messageSentAt: TimeInterval? = nil,
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
        self.messageSentAt = messageSentAt
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

public struct BackgroundWorkToken: Sendable {
    private let endHandler: @Sendable () -> Void

    public init(endHandler: @escaping @Sendable () -> Void) {
        self.endHandler = endHandler
    }

    public func end() {
        endHandler()
    }
}

@MainActor
public final class PairSyncService: ObservableObject {
    public static let shared = PairSyncService()

    private static let maxEnvelopeLineBytes = 8192
    private static let maxCiphertextChars = 3900
    private static let maxFutureClockSkewSeconds: TimeInterval = 300
    private static let maxMessageAgeSeconds: TimeInterval = 86_400

    // Very low probability & long cooldowns so special animations feel genuinely rare
    private static let rareInteractionCooldown: TimeInterval = 1_200     // 20 minutes between any special animations
    private static let superRareCooldown: TimeInterval = 2_700           // 45 minutes between Super Rare animations
    private static let ultraRareCooldown: TimeInterval = 7_200           // 2 hours between Ultra Rare animations

    private static let twinStatusTriggerChance: Double = 0.05            // 5.0% when both pets match status
    private static let clashStatusTriggerChance: Double = 0.035          // 3.5% on contrasting moods
    private static let normalStatusTriggerChance: Double = 0.015         // 1.5% on general status change
    private static let keywordMessageTriggerChance: Double = 0.06        // 6.0% on themed message
    private static let normalMessageTriggerChance: Double = 0.02         // 2.0% on general message
    private static let spontaneousIdleTriggerChance: Double = 0.015      // 1.5% per 5-minute idle check
    private static let soloQuirkTriggerChance: Double = 0.02             // 2.0% when unpaired

    private static let ultraRareTierWeight: Double = 0.06                // 6% of triggered moments -> Ultra Rare
    private static let superRareTierWeight: Double = 0.22                // 22% of triggered moments -> Super Rare

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

    /// Injected by the main application (`IslandPupApp`) to protect outgoing sync POSTs
    /// and brief Home Screen Dynamic Island viewing windows without referencing `UIApplication.shared` in `Shared`.
    public var beginBackgroundWork: ((@escaping @MainActor () -> Void) -> BackgroundWorkToken?)?

    private let storage = SharedStorage.shared
    private let petStore = CustomPetStore.shared
    private let requestSession: URLSession
    private let streamSession: URLSession
    private var streamTask: Task<Void, Never>?
    private var fallbackPollTask: Task<Void, Never>?
    private var rareRollTask: Task<Void, Never>?
    private var rareExpiryTask: Task<Void, Never>?
    private var soloQuirkExpiryTask: Task<Void, Never>?
    private var messageExpiryTask: Task<Void, Never>?
    private var myMessageSentAt: TimeInterval?
    private var partnerMessageSentAt: TimeInterval?
    private var backgroundStreamToken: BackgroundWorkToken?
    private var isStreamConnected: Bool = false
    private var processedEnvelopeIDs: Set<String> = []
    private var processedEnvelopeOrder: [String] = []
    private var lastPushedContentState: PetActivityAttributes.ContentState?

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
        self.myMessageSentAt = SharedStorage.shared.myMessageSentAt
        self.myName = SharedStorage.shared.myName
        self.pairCode = SharedStorage.shared.pairCode
        self.relayBaseURL = SharedStorage.shared.relayBaseURL
        self.partnerOwnerName = SharedStorage.shared.partnerOwnerName
        self.partnerPet = SharedStorage.shared.partnerPet
        self.partnerMessage = SharedStorage.shared.partnerMessage
        self.partnerMessageSentAt = SharedStorage.shared.partnerMessageSentAt
        self.activeRareInteraction = SharedStorage.shared.rareInteraction
        self.activeSoloQuirk = SharedStorage.shared.soloQuirk

        refreshConnectionBadge()
        if let rare = activeRareInteraction {
            scheduleRareInteractionExpiry(rare)
        }
        if let quirk = activeSoloQuirk {
            scheduleSoloQuirkExpiry(quirk)
        }
        scheduleNextMessageExpiry()
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
        let now = Date().timeIntervalSince1970
        let paired = !pairCode.isEmpty
        let activeRare = paired && partnerPet != nil && (activeRareInteraction?.isActive(at: now) == true)
            ? activeRareInteraction
            : nil
        let activeQuirk = activeRare == nil && (activeSoloQuirk?.isActive(at: now) == true)
            ? activeSoloQuirk
            : nil
        let myMsgExp = myMessageSentAt.map { $0 + SharedStorage.messageTTL }
        let validMyMsg = (myMessage != nil && (myMsgExp == nil || now < myMsgExp!)) ? myMessage : nil
        let partnerMsgExp = partnerMessageSentAt.map { $0 + SharedStorage.messageTTL }
        let validPartnerMsg = (partnerMessage != nil && (partnerMsgExp == nil || now < partnerMsgExp!)) ? partnerMessage : nil
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
            myMessage: validMyMsg,
            myMessageExpiresAt: validMyMsg != nil ? myMsgExp : nil,
            isPaired: paired,
            partnerPet: partnerPet,
            partnerOwnerName: partnerOwnerName,
            partnerMessage: validPartnerMsg,
            partnerMessageExpiresAt: validPartnerMsg != nil ? partnerMsgExp : nil,
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

    // MARK: - Emotions, Tasks & Messages

    /// Updates ONLY your pet's Emotion/Task silently (no notification), rolling a very low chance for synced special animations!
    public func setMyPetAction(_ action: PetAction) async {
        let now = Date().timeIntervalSince1970

        myAction = action
        storage.myAction = action
        clearSoloQuirkLocally()

        var candidateDuo: RarePetInteraction?
        if storage.isPaired, let connectedPet = partnerPet {
            if connectedPet.action == action {
                candidateDuo = rollSyncedSpecialInteraction(
                    triggerChance: Self.twinStatusTriggerChance,
                    preferredKinds: Self.twinStatusCandidates(for: action),
                    now: now
                )
            } else {
                let clashCandidates = Self.clashStatusCandidates(first: action, second: connectedPet.action)
                if !clashCandidates.isEmpty {
                    candidateDuo = rollSyncedSpecialInteraction(
                        triggerChance: Self.clashStatusTriggerChance,
                        preferredKinds: clashCandidates,
                        now: now
                    )
                } else {
                    candidateDuo = rollSyncedSpecialInteraction(
                        triggerChance: Self.normalStatusTriggerChance,
                        preferredKinds: [],
                        now: now
                    )
                }
            }
        } else if !storage.isPaired {
            maybeRollRareSoloQuirk(preferredAction: nil, now: now)
        }

        if storage.isPaired {
            let ok = await broadcastMyPetState(
                isExplicitUpdate: true,
                notifyMessage: false,
                piggybackedRare: candidateDuo
            )
            if ok {
                if let candidateDuo {
                    await applyRareInteraction(candidateDuo, broadcastToPartner: false, pushIslandNow: true)
                } else {
                    await pushStateToActiveLiveActivities()
                    showToast("\(myPetProfile.name) is now \(action.title) \(action.emoji)")
                }
            } else {
                await pushStateToActiveLiveActivities()
                showToast("Updated locally (couldn't reach sync relay)")
            }
        } else {
            await pushStateToActiveLiveActivities()
            if activeSoloQuirk == nil {
                showToast("\(myPetProfile.name) is now \(action.title) \(action.emoji)")
            }
        }
    }

    /// Sends a message that pushes a notification on the connected iPhone, with a very low chance for synced special animations!
    public func sendMyMessage(_ rawMessage: String, optionalAction: PetAction? = nil) async {
        guard let cleaned = Self.cleanOptionalMessage(rawMessage) else { return }
        let now = Date().timeIntervalSince1970

        if let optionalAction {
            myAction = optionalAction
            storage.myAction = optionalAction
        }
        storage.setMyMessage(cleaned, sentAt: now)
        myMessage = cleaned
        myMessageSentAt = now
        scheduleNextMessageExpiry()
        if storage.isPaired {
            clearSoloQuirkLocally()
        }

        var candidateDuo: RarePetInteraction?
        if storage.isPaired, let connectedPet = partnerPet {
            let keywordMatches = Self.keywordTriggeredCandidates(for: cleaned)
            if !keywordMatches.isEmpty {
                candidateDuo = rollSyncedSpecialInteraction(
                    triggerChance: Self.keywordMessageTriggerChance,
                    preferredKinds: keywordMatches,
                    now: now
                )
            } else if let optionalAction, optionalAction == connectedPet.action {
                candidateDuo = rollSyncedSpecialInteraction(
                    triggerChance: Self.twinStatusTriggerChance,
                    preferredKinds: Self.twinStatusCandidates(for: optionalAction),
                    now: now
                )
            } else {
                candidateDuo = rollSyncedSpecialInteraction(
                    triggerChance: Self.normalMessageTriggerChance,
                    preferredKinds: [],
                    now: now
                )
            }
        } else if !storage.isPaired {
            maybeRollRareSoloQuirk(preferredAction: Self.keywordTriggeredSoloQuirk(for: cleaned), now: now)
        }

        if storage.isPaired {
            let ok = await broadcastMyPetState(
                isExplicitUpdate: true,
                notifyMessage: true,
                piggybackedRare: candidateDuo
            )
            if ok {
                if let candidateDuo {
                    await applyRareInteraction(candidateDuo, broadcastToPartner: false, pushIslandNow: true)
                } else {
                    await pushStateToActiveLiveActivities()
                    if let connectedPet = partnerPet {
                        showToast("💬 \(myPetProfile.name) → \(connectedPet.name): “\(cleaned)”")
                    } else {
                        showToast("💬 \(myPetProfile.name): “\(cleaned)”")
                    }
                }
            } else {
                await pushStateToActiveLiveActivities()
                showToast("Saved locally (couldn't reach sync relay)")
            }
        } else {
            await pushStateToActiveLiveActivities()
            showToast("💬 \(myPetProfile.name): “\(cleaned)”")
        }
    }

    public func clearMyMessage() async {
        storage.setMyMessage(nil)
        myMessage = nil
        myMessageSentAt = nil
        scheduleNextMessageExpiry()
        await pushStateToActiveLiveActivities()
        if storage.isPaired {
            _ = await broadcastMyPetState(isExplicitUpdate: false, notifyMessage: false)
        }
    }

    public func purgeExpiredMessagesAndRefreshIsland() async {
        if purgeExpiredMessagesIfNeeded() {
            await pushStateToActiveLiveActivities()
        }
    }

    public func handleDynamicIslandActionTap(_ action: PetAction) async {
        reloadFromStorage()
        if storage.isPaired {
            await pollLatestMessages()
        }
        await setMyPetAction(action)
    }

    // MARK: - Pairing Lifecycle

    public func joinPairRoom(code: String) async {
        let normalized = SharedStorage.normalizePairCode(code)
        guard !normalized.isEmpty else { return }

        NotificationManager.shared.configureAndRequestPermission()
        clearSoloQuirkLocally()

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
            partnerMessageSentAt = nil
            activeRareInteraction = nil
            scheduleNextMessageExpiry()
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
        endBackgroundStreamGracePeriod()
        _ = purgeExpiredMessagesIfNeeded()
        let didUpgradeSchema = storage.consumeDidUpgradeSchemaIfNeeded()
        if didUpgradeSchema {
            reloadFromStorage()
        }
        guard storage.isPaired else {
            await pushStateToActiveLiveActivities()
            return
        }
        clearSoloQuirkLocally()
        startRealtimeListeners()
        await pollLatestMessages()
        if didUpgradeSchema {
            _ = await broadcastMyPetState(isExplicitUpdate: false, notifyMessage: false)
        }
        await pushStateToActiveLiveActivities()
    }

    /// Keeps the lightweight SSE sync listener alive during iOS's ~30s Home Screen background grace window
    /// so swiping up to watch the Dynamic Island receives partner actions and special animations live!
    public func enterBackgroundStreamGracePeriod() {
        fallbackPollTask?.cancel()
        fallbackPollTask = nil
        rareRollTask?.cancel()
        rareRollTask = nil

        guard storage.isPaired,
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              let beginWork = beginBackgroundWork else {
            stopRealtimeListeners()
            return
        }

        backgroundStreamToken?.end()
        backgroundStreamToken = nil

        if streamTask == nil {
            startStreamSocketOnly()
        }

        let token = beginWork { [weak self] in
            self?.backgroundStreamToken = nil
            self?.stopRealtimeListeners()
        }
        if let token {
            backgroundStreamToken = token
        } else {
            stopRealtimeListeners()
        }
    }

    public func endBackgroundStreamGracePeriod() {
        backgroundStreamToken?.end()
        backgroundStreamToken = nil
    }

    public func leavePairRoom() async {
        endBackgroundStreamGracePeriod()
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
        partnerMessageSentAt = nil
        activeRareInteraction = nil
        connectionStatus = .unpaired
        scheduleNextMessageExpiry()
        await pushStateToActiveLiveActivities()
    }

    private func startStreamSocketOnly() {
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
    }

    public func startRealtimeListeners() {
        guard activeTopicURLString != nil else {
            connectionStatus = .unpaired
            return
        }

        startStreamSocketOnly()

        if fallbackPollTask == nil {
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
        }

        if rareRollTask == nil {
            // Very low-frequency spontaneous roller (every 5 minutes, paused in Low Power Mode).
            rareRollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    if Task.isCancelled { break }
                    await self?.maybeRollSpontaneousInteraction()
                }
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

    // MARK: - Synced Low-Probability Rarity Roller (Rare, Super Rare & Ultra Rare)

    private static func twinStatusCandidates(for action: PetAction) -> [RareInteractionKind] {
        switch action {
        case .sleeping:
            return [.cozyNapTruce, .blanketHog, .skitBlanketWarBurrito]
        case .eating:
            return [.doubleBegSquad, .stealingFood, .foodEnvyBeg, .skitKibbleHeist]
        case .walk:
            return [.zoomieChase, .zoomieCrash, .skitZoomieCrashWipeout]
        case .working:
            return [.sharedBraincell, .interruptWork, .skitWfhMeetingDisaster]
        case .review:
            return [.sharedBraincell, .doubleSideEye, .skitDetectiveWhodunnit]
        case .waiting:
            return [.doubleBegSquad, .sittingOnHead, .skitPersonalSpaceHeadSit]
        case .idle:
            return [.sittingOnHead, .buttSniff, .cozyNapTruce]
        case .happy:
            return [.tugOfWar, .biteyFace, .skitBiteyFaceToNap]
        case .celebrate:
            return [.zoomieChase, .spinIntoDizzy, .skitSadToPartyRescue]
        case .waving:
            return [.buttSniff, .tugOfWar, .cheerUpLove]
        case .love:
            return [.cheerUpLove, .cozyNapTruce, .skitSadToPartyRescue]
        case .sad:
            return [.cheerUpLove, .skitSadToPartyRescue]
        case .confused:
            return [.sharedBraincell, .blameEachOther, .skitDetectiveWhodunnit]
        case .grumpy:
            return [.barkArgument, .pawBonk, .blameEachOther, .skitAnnoyUntilBonk]
        case .zoomies:
            return [.zoomieCrash, .zoomieChase, .skitZoomieCrashWipeout]
        case .begging:
            return [.doubleBegSquad, .stealingFood, .foodEnvyBeg, .skitKibbleHeist]
        case .spinning, .dizzy:
            return [.spinIntoDizzy, .skitZoomieCrashWipeout]
        case .booping:
            return [.cheerUpLove, .pawBonk]
        case .splooting:
            return [.cozyNapTruce, .blanketHog, .skitBlanketWarBurrito]
        case .sideEye:
            return [.doubleSideEye, .blameEachOther, .skitDetectiveWhodunnit]
        case .blep:
            return [.sharedBraincell, .sittingOnHead, .skitPersonalSpaceHeadSit]
        }
    }

    private static func clashStatusCandidates(first: PetAction, second: PetAction) -> [RareInteractionKind] {
        guard first != second else { return [] }
        let pair: Set<PetAction> = [first, second]

        let focusSet: Set<PetAction> = [.working, .review]
        let energeticSet: Set<PetAction> = [.happy, .celebrate, .waving, .walk, .zoomies]
        if !pair.isDisjoint(with: focusSet) && !pair.isDisjoint(with: energeticSet) {
            return [.interruptWork, .sharedBraincell, .skitWfhMeetingDisaster]
        }

        if pair.contains(.eating) && !pair.isDisjoint(with: [.waiting, .sad, .begging, .grumpy, .confused]) {
            return [.foodEnvyBeg, .stealingFood, .doubleBegSquad, .skitKibbleHeist]
        }

        if pair.contains(.sleeping) && !pair.isDisjoint(with: [.happy, .celebrate, .walk, .grumpy, .waving]) {
            return [.earNibbleAnnoy, .sittingOnHead, .blanketHog, .skitPersonalSpaceHeadSit]
        }

        if pair.contains(.sad) && !pair.isDisjoint(with: [.love, .happy, .celebrate, .waving]) {
            return [.cheerUpLove, .skitSadToPartyRescue]
        }

        if pair.contains(.grumpy) && !pair.isDisjoint(with: [.confused, .waiting, .idle]) {
            return [.blameEachOther, .doubleSideEye, .barkArgument, .skitDetectiveWhodunnit]
        }

        if pair.contains(.grumpy) && !pair.isDisjoint(with: [.happy, .celebrate, .love]) {
            return [.pawBonk, .earNibbleAnnoy, .skitAnnoyUntilBonk]
        }

        return []
    }

    private static func keywordTriggeredCandidates(for message: String) -> [RareInteractionKind] {
        let lower = message.lowercased()

        if containsAny(lower, ["love", "miss u", "miss you", "hug", "kiss", "cuddle", "❤️", "💕", "🥰", "😘"]) {
            return [.cheerUpLove, .cozyNapTruce, .skitSadToPartyRescue]
        }
        if containsAny(lower, ["goodnight", "gn", "sleep", "nap", "bedtime", "cozy", "🌙", "💤"]) {
            return [.cozyNapTruce, .blanketHog, .skitBlanketWarBurrito]
        }
        if containsAny(lower, ["food", "hungry", "eat", "snack", "dinner", "lunch", "treat", "boba", "pizza", "🍖", "🍕", "🍔", "🍜"]) {
            return [.stealingFood, .doubleBegSquad, .foodEnvyBeg, .skitKibbleHeist]
        }
        if containsAny(lower, ["work", "busy", "meeting", "study", "focus", "coding", "wfh", "💻"]) {
            return [.interruptWork, .sharedBraincell, .skitWfhMeetingDisaster]
        }
        if containsAny(lower, ["sus", "side eye", "side-eye", "judge", "bruh", "👀", "😒"]) {
            return [.doubleSideEye, .blameEachOther, .skitDetectiveWhodunnit]
        }
        if containsAny(lower, ["fault", "blame", "wasn't me", "wasnt me", "who did"]) {
            return [.blameEachOther, .skitDetectiveWhodunnit]
        }
        if containsAny(lower, ["bonk", "mad", "hmph", "argue", "no!", "stop", "😤", "💢"]) {
            return [.pawBonk, .barkArgument, .earNibbleAnnoy, .skitAnnoyUntilBonk]
        }
        if containsAny(lower, ["zoom", "walk", "chase", "run", "play", "tug", "party", "🎉", "⚡"]) {
            return [.zoomieChase, .tugOfWar, .biteyFace, .zoomieCrash, .skitTugOfWarSaga, .skitBiteyFaceToNap]
        }
        if containsAny(lower, ["dizzy", "spin", "braincell", "confused", "🌀", "😵‍💫"]) {
            return [.spinIntoDizzy, .sharedBraincell, .skitZoomieCrashWipeout]
        }
        return []
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
        if containsAny(lower, ["spin", "dizzy", "crazy", "🌀", "😵‍💫"]) {
            return .spinning
        }
        return nil
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func timeWeightedPool(for rarity: InteractionRarity) -> [RareInteractionKind] {
        let basePool = RareInteractionKind.cases(for: rarity)
        guard !basePool.isEmpty else { return RareInteractionKind.allCases }

        let hour = Calendar.current.component(.hour, from: Date())
        let bonusCandidates: [RareInteractionKind]
        if hour >= 22 || hour < 7 {
            bonusCandidates = [.cozyNapTruce, .blanketHog, .earNibbleAnnoy, .skitBlanketWarBurrito, .skitBiteyFaceToNap]
        } else if (11...13).contains(hour) || (18...20).contains(hour) {
            bonusCandidates = [.stealingFood, .foodEnvyBeg, .doubleBegSquad, .skitKibbleHeist]
        } else if (9...17).contains(hour) {
            bonusCandidates = [.interruptWork, .sharedBraincell, .sittingOnHead, .tugOfWar, .skitWfhMeetingDisaster]
        } else {
            bonusCandidates = []
        }

        let matchingBonuses = bonusCandidates.filter { $0.rarity == rarity }
        return basePool + matchingBonuses
    }

    private func rollSyncedSpecialInteraction(
        triggerChance: Double,
        preferredKinds: [RareInteractionKind],
        now: TimeInterval
    ) -> RarePetInteraction? {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return nil }
        guard activeRareInteraction?.isActive(at: now) != true else { return nil }
        guard now - storage.lastRareInteractionAt >= Self.rareInteractionCooldown else { return nil }

        var rng = SystemRandomNumberGenerator()
        guard Double.random(in: 0..<1, using: &rng) < triggerChance else {
            return nil
        }

        let canRollUltra = (now - storage.lastUltraRareSkitAt >= Self.ultraRareCooldown)
        let canRollSuper = (now - storage.lastSuperRareInteractionAt >= Self.superRareCooldown)
        let tierRoll = Double.random(in: 0..<1, using: &rng)

        let targetRarity: InteractionRarity
        if tierRoll < Self.ultraRareTierWeight && canRollUltra {
            targetRarity = .ultraRare
        } else if tierRoll < (Self.ultraRareTierWeight + Self.superRareTierWeight) && canRollSuper {
            targetRarity = .superRare
        } else {
            targetRarity = .rare
        }

        var expandedPreferred: [RareInteractionKind] = []
        for candidate in preferredKinds {
            if !expandedPreferred.contains(candidate) {
                expandedPreferred.append(candidate)
            }
            let mappedSkit = candidate.matchingUltraRareSkit
            if !expandedPreferred.contains(mappedSkit) {
                expandedPreferred.append(mappedSkit)
            }
        }

        let lastKind = activeRareInteraction?.kind
        let themedTierPool = expandedPreferred.filter { $0.rarity == targetRarity && $0 != lastKind }
        let chosen: RareInteractionKind
        if let pickedThemed = themedTierPool.randomElement(using: &rng) {
            chosen = pickedThemed
        } else {
            let generalPool = Self.timeWeightedPool(for: targetRarity)
            let nonRepeating = generalPool.filter { $0 != lastKind }
            chosen = (nonRepeating.isEmpty ? generalPool : nonRepeating).randomElement(using: &rng) ?? .tugOfWar
        }

        return RarePetInteraction(
            kind: chosen,
            triggerBadge: chosen.rarity.badgeLabel,
            startedAt: now,
            duration: chosen.defaultDuration
        )
    }

    private func maybeRollSpontaneousInteraction() async {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        let now = Date().timeIntervalSince1970

        if storage.isPaired, partnerPet != nil {
            guard let event = rollSyncedSpecialInteraction(
                triggerChance: Self.spontaneousIdleTriggerChance,
                preferredKinds: [],
                now: now
            ) else {
                return
            }
            await applyRareInteraction(event, broadcastToPartner: true, pushIslandNow: true)
        } else if !storage.isPaired {
            maybeRollRareSoloQuirk(preferredAction: nil, now: now)
            if activeSoloQuirk?.startedAt == now {
                await pushStateToActiveLiveActivities()
            }
        }
    }

    private func maybeRollRareSoloQuirk(preferredAction: PetAction?, now: TimeInterval) {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        guard activeSoloQuirk?.isActive(at: now) != true else { return }
        guard now - storage.lastRareInteractionAt >= Self.rareInteractionCooldown else { return }

        var rng = SystemRandomNumberGenerator()
        guard Double.random(in: 0..<1, using: &rng) < Self.soloQuirkTriggerChance else {
            return
        }

        let allowedQuirks = PetAction.quirkActions.filter { $0 != .booping }
        let sanitizedPreferred = (preferredAction == .booping) ? nil : preferredAction
        guard let quirkAction = sanitizedPreferred ?? allowedQuirks.randomElement(using: &rng) else {
            return
        }

        storage.lastRareInteractionAt = now
        let quirk = SoloPetQuirk(
            action: quirkAction,
            triggerBadge: "✨ RARE QUIRK",
            startedAt: now,
            duration: 32
        )
        applySoloQuirk(quirk, toastText: "✨ \(myPetProfile.name) \(quirkAction.statusPhrase) \(quirkAction.emoji)")
    }

    /// Deterministic conflict resolution so if both phones roll a special animation simultaneously,
    /// both converge on the exact same winner (higher rarity -> earlier `startedAt` -> lexicographic `id`).
    private static func shouldAdoptIncomingInteraction(
        current: RarePetInteraction?,
        incoming: RarePetInteraction,
        now: TimeInterval
    ) -> Bool {
        guard incoming.isActive(at: now) else { return false }
        guard let current, current.isActive(at: now) else { return true }
        if current.id == incoming.id { return false }
        if incoming.kind.rarity != current.kind.rarity {
            return incoming.kind.rarity > current.kind.rarity
        }
        if abs(incoming.startedAt - current.startedAt) > 0.001 {
            return incoming.startedAt < current.startedAt
        }
        return incoming.id < current.id
    }

    private func applyRareInteraction(
        _ event: RarePetInteraction,
        broadcastToPartner: Bool,
        pushIslandNow: Bool
    ) async {
        let now = Date().timeIntervalSince1970
        guard event.isActive(at: now), let partnerPet else { return }

        if broadcastToPartner {
            _ = purgeExpiredMessagesIfNeeded()
            let wire = PairWireMessage(
                kind: .rareInteraction,
                senderDeviceId: storage.deviceId,
                senderOwnerName: "",
                petSnapshot: myPetSnapshot,
                message: myMessage,
                messageSentAt: myMessage != nil ? myMessageSentAt : nil,
                isExplicitUpdate: false,
                rareInteraction: event
            )
            // Confirm relay delivery first so neither phone plays an unsynced duo animation while offline.
            guard await postWireMessage(wire) else { return }
        }

        clearSoloQuirkLocally()
        storage.lastRareInteractionAt = max(storage.lastRareInteractionAt, event.startedAt)
        if event.kind.rarity >= .superRare {
            storage.lastSuperRareInteractionAt = max(storage.lastSuperRareInteractionAt, event.startedAt)
        }
        if event.kind.rarity == .ultraRare {
            storage.lastUltraRareSkitAt = max(storage.lastUltraRareSkitAt, event.startedAt)
        }
        storage.rareInteraction = event
        activeRareInteraction = event
        scheduleRareInteractionExpiry(event)

        let description = event.kind.descriptionText(
            myPetName: myPetProfile.name,
            partnerPetName: partnerPet.name
        )
        showToast("\(event.effectiveTriggerBadge) • \(description)")

        if pushIslandNow {
            await pushStateToActiveLiveActivities()
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

    @discardableResult
    private func purgeExpiredMessagesIfNeeded() -> Bool {
        var didPurge = false

        let storedMyMsg = storage.myMessage
        if myMessage != storedMyMsg {
            myMessage = storedMyMsg
            didPurge = true
        }
        myMessageSentAt = storedMyMsg != nil ? storage.myMessageSentAt : nil

        let storedPartnerMsg = storage.partnerMessage
        if partnerMessage != storedPartnerMsg {
            partnerMessage = storedPartnerMsg
            didPurge = true
        }
        partnerMessageSentAt = storedPartnerMsg != nil ? storage.partnerMessageSentAt : nil

        scheduleNextMessageExpiry()
        return didPurge
    }

    private func scheduleNextMessageExpiry() {
        messageExpiryTask?.cancel()
        messageExpiryTask = nil

        let now = Date().timeIntervalSince1970
        let candidates = [
            myMessage != nil ? myMessageSentAt.map { $0 + SharedStorage.messageTTL } : nil,
            partnerMessage != nil ? partnerMessageSentAt.map { $0 + SharedStorage.messageTTL } : nil
        ]
        .compactMap { $0 }

        guard let earliest = candidates.min() else { return }
        let remaining = max(0.5, earliest - now + 0.3)

        messageExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.purgeExpiredMessagesIfNeeded() {
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
        _ = purgeExpiredMessagesIfNeeded()
        let now = Date().timeIntervalSince1970
        let effectiveRare = piggybackedRare ?? (
            activeRareInteraction?.isActive(at: now) == true ? activeRareInteraction : nil
        )
        let wire = PairWireMessage(
            kind: .petState,
            senderDeviceId: storage.deviceId,
            senderOwnerName: "",
            petSnapshot: myPetSnapshot,
            message: myMessage,
            messageSentAt: myMessage != nil ? myMessageSentAt : nil,
            isExplicitUpdate: isExplicitUpdate,
            notifyMessage: notifyMessage,
            rareInteraction: effectiveRare
        )
        return await postWireMessage(wire)
    }

    public func pollLatestMessages() async {
        let prevMyMessage = myMessage
        let prevPartnerMessage = partnerMessage
        reloadFromStorage()
        let purgedOnReload = (prevMyMessage != myMessage) || (prevPartnerMessage != partnerMessage)
        let lastServerTime = storage.lastRelayEnvelopeTime
        let sinceParam = lastServerTime > 0 ? "\(max(1, lastServerTime - 2))" : "12h"
        guard let base = activeTopicURLString,
              let pollURL = URL(string: "\(base)/json?poll=1&since=\(sinceParam)") else {
            if purgedOnReload {
                await pushStateToActiveLiveActivities()
            }
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
                if purgedOnReload {
                    await pushStateToActiveLiveActivities()
                }
                return
            }

            let wasFirstPartnerLink = (partnerPet == nil)
            let lines = text.split(whereSeparator: \.isNewline)
            var latestAlertBody: String?
            var didChange = purgedOnReload

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

        let bgToken = beginBackgroundWork?({})
        defer { bgToken?.end() }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = encryptedBody

        for attempt in 0..<2 {
            do {
                let (_, response) = try await requestSession.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    return true
                }
            } catch {
                if Task.isCancelled { return false }
            }

            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return false }
            }
        }
        return false
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

        // Handle dedicated Rare Two-Dog Interaction packets (silent, synced across both phones)
        if wire.kind == .rareInteraction, let incomingRare = wire.rareInteraction, incomingRare.isActive(at: now) {
            let sanitizedPartner = Self.sanitizeIncomingSnapshot(wire.petSnapshot)
            partnerPet = sanitizedPartner
            storage.partnerPet = sanitizedPartner
            refreshConnectionBadge(connected: true)

            if Self.shouldAdoptIncomingInteraction(current: activeRareInteraction, incoming: incomingRare, now: now) {
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
        let rawCleanMessage = Self.cleanOptionalMessage(wire.message)

        let safeMessage: String?
        let resolvedMsgSentAt: TimeInterval?
        if let candidateMsg = rawCleanMessage {
            let inferredSentAt: TimeInterval
            if let explicitMsgAt = wire.messageSentAt, explicitMsgAt > 0 {
                inferredSentAt = min(explicitMsgAt, now + Self.maxFutureClockSkewSeconds)
            } else if wire.notifyMessage == true {
                inferredSentAt = wire.sentAt
            } else if candidateMsg == partnerMessage, let existingSentAt = partnerMessageSentAt {
                // Keep original creation timestamp on status-only packets from older app versions
                inferredSentAt = existingSentAt
            } else {
                inferredSentAt = wire.sentAt
            }

            if now - inferredSentAt < SharedStorage.messageTTL {
                safeMessage = candidateMsg
                resolvedMsgSentAt = inferredSentAt
            } else {
                safeMessage = nil
                resolvedMsgSentAt = nil
            }
        } else {
            safeMessage = nil
            resolvedMsgSentAt = nil
        }

        partnerOwnerName = nil
        partnerPet = safeSnapshot
        partnerMessage = safeMessage
        partnerMessageSentAt = resolvedMsgSentAt

        storage.partnerOwnerName = nil
        storage.partnerPet = safeSnapshot
        if let safeMessage, let resolvedMsgSentAt {
            storage.setPartnerMessage(safeMessage, sentAt: resolvedMsgSentAt)
        } else {
            storage.setPartnerMessage(nil)
        }
        scheduleNextMessageExpiry()

        refreshConnectionBadge(connected: true)

        var didApplyRare = false
        if let incomingRare = wire.rareInteraction,
           Self.shouldAdoptIncomingInteraction(current: activeRareInteraction, incoming: incomingRare, now: now) {
            await applyRareInteraction(incomingRare, broadcastToPartner: false, pushIslandNow: false)
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
        myMessageSentAt = storage.myMessageSentAt
        myName = storage.myName
        pairCode = storage.pairCode
        partnerOwnerName = storage.partnerOwnerName
        partnerPet = storage.partnerPet
        partnerMessage = storage.partnerMessage
        partnerMessageSentAt = storage.partnerMessageSentAt
        activeRareInteraction = storage.rareInteraction
        activeSoloQuirk = storage.soloQuirk
        scheduleNextMessageExpiry()
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
