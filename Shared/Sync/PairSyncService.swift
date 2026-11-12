import ActivityKit
import Combine
import CryptoKit
import Foundation

/// Wire payload exchanged between two paired iPhones over the relay topic.
public struct PairWireMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case setAction = "set_action"
        case status = "status"
    }

    public var kind: Kind
    public var senderDeviceId: String
    public var senderName: String
    public var senderCharacter: PetCharacter
    public var senderCurrentAction: PetAction
    public var targetAction: PetAction?
    public var note: String?
    public var sentAt: TimeInterval

    public init(
        kind: Kind,
        senderDeviceId: String,
        senderName: String,
        senderCharacter: PetCharacter,
        senderCurrentAction: PetAction,
        targetAction: PetAction? = nil,
        note: String? = nil,
        sentAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.kind = kind
        self.senderDeviceId = senderDeviceId
        self.senderName = senderName
        self.senderCharacter = senderCharacter
        self.senderCurrentAction = senderCurrentAction
        self.targetAction = targetAction
        self.note = note
        self.sentAt = sentAt
    }
}

private struct NtfyEnvelope: Decodable {
    let id: String?
    let time: Int?
    let event: String
    let message: String?
}

/// Coordinates real-time & background pairing between two iPhones so Phone 1 can set
/// Phone 2's Dynamic Island pet animation (e.g. Sleeping) and vice versa.
@MainActor
public final class PairSyncService: ObservableObject {
    public static let shared = PairSyncService()

    public enum ConnectionStatus: Equatable, Sendable {
        case unpaired
        case connecting
        case listening
        case partnerLinked(name: String)
        case error(String)
    }

    @Published public private(set) var myCharacter: PetCharacter
    @Published public private(set) var myAction: PetAction
    @Published public var myName: String {
        didSet { storage.myName = myName }
    }
    @Published public private(set) var lastSenderName: String?
    @Published public private(set) var lastNote: String?

    @Published public private(set) var pairCode: String
    @Published public var relayBaseURL: String {
        didSet { storage.relayBaseURL = relayBaseURL }
    }

    @Published public private(set) var partnerName: String?
    @Published public private(set) var partnerCharacter: PetCharacter?
    @Published public private(set) var partnerAction: PetAction?
    @Published public private(set) var connectionStatus: ConnectionStatus = .unpaired
    @Published public var toastMessage: String?

    private let storage = SharedStorage.shared
    private var streamTask: Task<Void, Never>?
    private var heartbeatPollTask: Task<Void, Never>?

    private init() {
        self.myCharacter = storage.myCharacter
        self.myAction = storage.myAction
        self.myName = storage.myName
        self.lastSenderName = storage.lastSenderName
        self.lastNote = storage.lastNote
        self.pairCode = storage.pairCode
        self.relayBaseURL = storage.relayBaseURL
        self.partnerName = storage.partnerName
        self.partnerCharacter = storage.partnerCharacter
        self.partnerAction = storage.partnerAction

        refreshConnectionBadge()
    }

    // MARK: - Topic Derivation

    /// Derives a private SHA-256 topic name from the human-friendly pair code.
    public static func topicName(forPairCode code: String) -> String {
        let normalized = SharedStorage.normalizePairCode(code)
        let input = Data("islandpup-v1:\(normalized)".utf8)
        let digest = SHA256.hash(data: input)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "islandpup-\(hex.prefix(20))"
    }

    private var activeTopicURLString: String? {
        guard !pairCode.isEmpty else { return nil }
        let topic = Self.topicName(forPairCode: pairCode)
        return "\(storage.relayBaseURL)/\(topic)"
    }

    // MARK: - Local Pet Selection & Actions

    /// Selects which 1 pet runs on this iPhone's Dynamic Island (Alfie or Teddy).
    public func selectCharacter(_ character: PetCharacter) async {
        myCharacter = character
        storage.myCharacter = character
        await pushStateToActiveLiveActivities()
        if storage.isPaired {
            await publishStatus()
        }
    }

    /// Sets this phone's own pet animation directly.
    public func setMyOwnAction(_ action: PetAction, note: String? = nil) async {
        myAction = action
        lastSenderName = nil
        let cleanNote = Self.cleanOptionalNote(note)
        lastNote = cleanNote

        storage.myAction = action
        storage.lastSenderName = nil
        storage.lastNote = cleanNote

        await pushStateToActiveLiveActivities()
        if storage.isPaired {
            await publishStatus()
        }
    }

    // MARK: - Pairing Lifecycle

    public func joinPairRoom(code: String) async {
        let normalized = SharedStorage.normalizePairCode(code)
        guard !normalized.isEmpty else { return }

        let isNewRoom = normalized != pairCode
        pairCode = normalized
        storage.pairCode = normalized

        if isNewRoom {
            storage.clearPartnerMetadata()
            partnerName = nil
            partnerCharacter = nil
            partnerAction = nil
        }

        connectionStatus = .connecting
        startRealtimeListeners()
        await publishStatus()
        await pollLatestMessages()
        await pushStateToActiveLiveActivities()
    }

    public func leavePairRoom() async {
        stopRealtimeListeners()
        pairCode = ""
        storage.pairCode = ""
        storage.clearPartnerMetadata()
        partnerName = nil
        partnerCharacter = nil
        partnerAction = nil
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
    }

    public func stopRealtimeListeners() {
        streamTask?.cancel()
        streamTask = nil
        heartbeatPollTask?.cancel()
        heartbeatPollTask = nil
    }

    // MARK: - Sending Actions to Partner's iPhone

    /// Sends a pet animation command to the paired iPhone so its Dynamic Island pet switches
    /// to `action` (e.g. `.sleeping`, `.waving`, `.jumping`, `.working`).
    @discardableResult
    public func sendActionToPartner(_ action: PetAction, note: String? = nil) async -> Bool {
        guard storage.isPaired else {
            showToast("Pair with another phone first!")
            return false
        }

        let cleanNote = Self.cleanOptionalNote(note)
        let msg = PairWireMessage(
            kind: .setAction,
            senderDeviceId: storage.deviceId,
            senderName: storage.myName,
            senderCharacter: myCharacter,
            senderCurrentAction: myAction,
            targetAction: action,
            note: cleanNote
        )

        let ok = await postWireMessage(msg)
        if ok {
            partnerAction = action
            storage.partnerAction = action
            let targetPetName = partnerCharacter?.displayName ?? "Partner's pet"
            showToast("Set \(targetPetName) to \(action.title) \(action.emoji)")
            await pushStateToActiveLiveActivities()
        } else {
            showToast("Couldn't reach relay — check connection")
        }
        return ok
    }

    /// Invoked from `LiveActivityIntent` buttons directly on the Dynamic Island or Lock Screen.
    public func handleDynamicIslandActionTap(_ action: PetAction) async {
        reloadFromStorage()
        if storage.isPaired {
            _ = await sendActionToPartner(action)
            await pollLatestMessages()
        } else {
            await setMyOwnAction(action)
        }
    }

    public func publishStatus() async {
        guard storage.isPaired else { return }
        let msg = PairWireMessage(
            kind: .status,
            senderDeviceId: storage.deviceId,
            senderName: storage.myName,
            senderCharacter: myCharacter,
            senderCurrentAction: myAction
        )
        _ = await postWireMessage(msg)
    }

    // MARK: - Catch-up Polling (Foreground, BGAppRefresh, LiveActivityIntent)

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
                  let text = String(data: data, encoding: .utf8) else {
                return
            }

            let lines = text.split(whereSeparator: \.isNewline)
            var didApplyNewRemoteAction = false

            for sub in lines {
                let applied = await processEnvelopeJSONLine(String(sub), notifyAckImmediately: false)
                if applied {
                    didApplyNewRemoteAction = true
                }
            }

            refreshConnectionBadge(connected: true)

            if didApplyNewRemoteAction {
                await pushStateToActiveLiveActivities()
                await publishStatus()
            }
        } catch {
            // Keep existing state quietly during transient network drops
        }
    }

    // MARK: - Internal Networking & Decoding

    private func postWireMessage(_ message: PairWireMessage) async -> Bool {
        guard let base = activeTopicURLString,
              let url = URL(string: base),
              let encoded = try? JSONEncoder().encode(message) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = encoded

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
        let applied = await processEnvelopeJSONLine(line, notifyAckImmediately: true)
        if applied {
            await pushStateToActiveLiveActivities()
        }
    }

    @discardableResult
    private func processEnvelopeJSONLine(_ line: String, notifyAckImmediately: Bool) async -> Bool {
        guard let lineData = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(NtfyEnvelope.self, from: lineData),
              envelope.event == "message",
              let inner = envelope.message,
              let innerData = inner.data(using: .utf8),
              let wire = try? JSONDecoder().decode(PairWireMessage.self, from: innerData) else {
            return false
        }

        // Ignore our own outbound messages
        guard wire.senderDeviceId != storage.deviceId else {
            return false
        }

        // Update partner profile metadata
        partnerName = wire.senderName
        partnerCharacter = wire.senderCharacter
        storage.partnerName = wire.senderName
        storage.partnerCharacter = wire.senderCharacter

        if wire.kind == .status {
            partnerAction = wire.senderCurrentAction
            storage.partnerAction = wire.senderCurrentAction
            refreshConnectionBadge(connected: true)
            await pushStateToActiveLiveActivities()
            return false
        }

        if wire.kind == .setAction,
           let incomingAction = wire.targetAction,
           wire.sentAt > storage.lastAppliedRemoteSentAt {
            storage.lastAppliedRemoteSentAt = wire.sentAt

            myAction = incomingAction
            lastSenderName = wire.senderName
            let cleanNote = Self.cleanOptionalNote(wire.note)
            lastNote = cleanNote

            storage.myAction = incomingAction
            storage.lastSenderName = wire.senderName
            storage.lastNote = cleanNote

            refreshConnectionBadge(connected: true)
            showToast("\(wire.senderName) set \(myCharacter.displayName) to \(incomingAction.title) \(incomingAction.emoji)")

            if notifyAckImmediately {
                await publishStatus()
            }
            return true
        }

        return false
    }

    private func reloadFromStorage() {
        myCharacter = storage.myCharacter
        myAction = storage.myAction
        myName = storage.myName
        lastSenderName = storage.lastSenderName
        lastNote = storage.lastNote
        pairCode = storage.pairCode
        partnerName = storage.partnerName
        partnerCharacter = storage.partnerCharacter
        partnerAction = storage.partnerAction
    }

    private func refreshConnectionBadge(connected: Bool = false) {
        guard !pairCode.isEmpty else {
            connectionStatus = .unpaired
            return
        }
        if let partnerName, !partnerName.isEmpty {
            connectionStatus = .partnerLinked(name: partnerName)
        } else {
            connectionStatus = connected ? .listening : .connecting
        }
    }

    private func showToast(_ text: String) {
        toastMessage = text
    }

    private static func cleanOptionalNote(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(32))
    }

    // MARK: - Live Activity Sync

    public func pushStateToActiveLiveActivities() async {
        let state = PetActivityAttributes.ContentState(
            character: myCharacter,
            action: myAction,
            senderName: lastSenderName,
            note: lastNote,
            isPaired: !pairCode.isEmpty,
            partnerCharacter: partnerCharacter,
            partnerAction: partnerAction
        )
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<PetActivityAttributes>.activities {
            await activity.update(content)
        }
    }
}
