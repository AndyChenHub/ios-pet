import Foundation
import Security

/// Persists pet roster selection, custom pet state, partner pet snapshot, partner message,
/// and rare interaction state across UserDefaults.
public final class SharedStorage: @unchecked Sendable {
    public static let shared = SharedStorage()
    public static let defaultRelayURL = "https://ntfy.sh"

    private let defaults = UserDefaults.standard
    private let stateLock = NSLock()
    private var hasCachedPartnerPet = false
    private var cachedPartnerPet: IslandPetSnapshot?
    private var cachedAnchorTimestamp: TimeInterval = 0

    private enum Keys {
        static let deviceId = "islandpup.v3.deviceId"
        static let myName = "islandpup.v3.myName"
        static let selectedPetID = "islandpup.v3.selectedPetID"
        static let myAction = "islandpup.v3.myAction"
        static let myMessage = "islandpup.v3.myMessage"
        static let pairCode = "islandpup.v3.pairCode"
        static let relayBaseURL = "islandpup.v3.relayBaseURL"
        static let partnerOwnerName = "islandpup.v3.partnerOwnerName"
        static let partnerPetData = "islandpup.v3.partnerPetData"
        static let partnerMessage = "islandpup.v3.partnerMessage"
        static let rareInteractionData = "islandpup.v3.rareInteractionData"
        static let soloQuirkData = "islandpup.v3.soloQuirkData"
        static let lastAppliedRemoteSentAt = "islandpup.v3.lastAppliedRemoteSentAt"
        static let lastNotifiedRemoteSentAt = "islandpup.v3.lastNotifiedRemoteSentAt"
        static let lastRareInteractionAt = "islandpup.v3.lastRareInteractionAt"
        static let lastUltraRareSkitAt = "islandpup.v3.lastUltraRareSkitAt"
        static let lastRelayEnvelopeTime = "islandpup.v3.lastRelayEnvelopeTime"
        static let schemaVersion = "islandpup.v3.schemaVersion"
    }

    public static let currentSchemaVersion = 2

    private init() {}

    public var deviceId: String {
        if let existing = defaults.string(forKey: Keys.deviceId), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Keys.deviceId)
        return fresh
    }

    public var myName: String {
        get { defaults.string(forKey: Keys.myName) ?? "" }
        set {
            let sanitized = Self.sanitizeDisplayText(newValue, maxLength: 20)
            defaults.set(sanitized, forKey: Keys.myName)
        }
    }

    public var selectedPetID: String {
        get { defaults.string(forKey: Keys.selectedPetID) ?? PetProfile.defaultAlfie.id }
        set { defaults.set(newValue, forKey: Keys.selectedPetID) }
    }

    public var selectedPetProfile: PetProfile {
        let roster = CustomPetStore.shared.loadRoster()
        if let match = roster.first(where: { $0.id == selectedPetID }) {
            return match
        }
        let fallback = roster.first ?? .defaultAlfie
        selectedPetID = fallback.id
        return fallback
    }

    public var myAction: PetAction {
        get {
            guard let raw = defaults.string(forKey: Keys.myAction) else {
                return .idle
            }
            return PetAction.decodeResilient(from: raw)
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.myAction) }
    }

    public var myMessage: String? {
        get { defaults.string(forKey: Keys.myMessage) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Keys.myMessage)
            } else {
                defaults.removeObject(forKey: Keys.myMessage)
            }
        }
    }

    public var pairCode: String {
        get { Self.normalizePairCode(defaults.string(forKey: Keys.pairCode) ?? "") }
        set { defaults.set(Self.normalizePairCode(newValue), forKey: Keys.pairCode) }
    }

    public var isPaired: Bool {
        !pairCode.isEmpty
    }

    public var relayBaseURL: String {
        get { Self.sanitizeRelayBaseURL(defaults.string(forKey: Keys.relayBaseURL) ?? Self.defaultRelayURL) }
        set {
            let clean = Self.sanitizeRelayBaseURL(newValue)
            if clean != relayBaseURL {
                lastRelayEnvelopeTime = 0
            }
            defaults.set(clean, forKey: Keys.relayBaseURL)
        }
    }

    public var partnerOwnerName: String? {
        get { defaults.string(forKey: Keys.partnerOwnerName) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Keys.partnerOwnerName)
            } else {
                defaults.removeObject(forKey: Keys.partnerOwnerName)
            }
        }
    }

    public var partnerPet: IslandPetSnapshot? {
        get {
            stateLock.lock()
            if hasCachedPartnerPet {
                let value = cachedPartnerPet
                stateLock.unlock()
                return value
            }
            stateLock.unlock()

            let decoded: IslandPetSnapshot?
            if let data = defaults.data(forKey: Keys.partnerPetData) {
                decoded = try? JSONDecoder().decode(IslandPetSnapshot.self, from: data)
            } else {
                decoded = nil
            }

            stateLock.lock()
            cachedPartnerPet = decoded
            hasCachedPartnerPet = true
            stateLock.unlock()
            return decoded
        }
        set {
            stateLock.lock()
            cachedPartnerPet = newValue
            hasCachedPartnerPet = true
            stateLock.unlock()

            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.partnerPetData)
            } else {
                defaults.removeObject(forKey: Keys.partnerPetData)
            }
        }
    }

    public var partnerMessage: String? {
        get { defaults.string(forKey: Keys.partnerMessage) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Keys.partnerMessage)
            } else {
                defaults.removeObject(forKey: Keys.partnerMessage)
            }
        }
    }

    public var rareInteraction: RarePetInteraction? {
        get {
            guard let data = defaults.data(forKey: Keys.rareInteractionData),
                  let decoded = try? JSONDecoder().decode(RarePetInteraction.self, from: data),
                  decoded.isActive() else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue, newValue.isActive(), let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.rareInteractionData)
            } else {
                defaults.removeObject(forKey: Keys.rareInteractionData)
            }
        }
    }

    public var soloQuirk: SoloPetQuirk? {
        get {
            guard let data = defaults.data(forKey: Keys.soloQuirkData),
                  let decoded = try? JSONDecoder().decode(SoloPetQuirk.self, from: data),
                  decoded.isActive() else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue, newValue.isActive(), let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.soloQuirkData)
            } else {
                defaults.removeObject(forKey: Keys.soloQuirkData)
            }
        }
    }

    public var lastAppliedRemoteSentAt: TimeInterval {
        get { defaults.double(forKey: Keys.lastAppliedRemoteSentAt) }
        set { defaults.set(newValue, forKey: Keys.lastAppliedRemoteSentAt) }
    }

    public var lastNotifiedRemoteSentAt: TimeInterval {
        get { defaults.double(forKey: Keys.lastNotifiedRemoteSentAt) }
        set { defaults.set(newValue, forKey: Keys.lastNotifiedRemoteSentAt) }
    }

    public var lastRareInteractionAt: TimeInterval {
        get { defaults.double(forKey: Keys.lastRareInteractionAt) }
        set { defaults.set(newValue, forKey: Keys.lastRareInteractionAt) }
    }

    public var lastUltraRareSkitAt: TimeInterval {
        get { defaults.double(forKey: Keys.lastUltraRareSkitAt) }
        set { defaults.set(newValue, forKey: Keys.lastUltraRareSkitAt) }
    }

    public var lastRelayEnvelopeTime: Int {
        get { defaults.integer(forKey: Keys.lastRelayEnvelopeTime) }
        set { defaults.set(newValue, forKey: Keys.lastRelayEnvelopeTime) }
    }

    /// Returns `true` once after upgrading from an earlier schema, resetting the relay poll cursor
    /// (`lastRelayEnvelopeTime = 0`) while keeping notification dedupe timestamps intact so the paired
    /// room re-hydrates the last 12h cleanly without replaying old push alerts.
    public func consumeDidUpgradeSchemaIfNeeded() -> Bool {
        let saved = defaults.integer(forKey: Keys.schemaVersion)
        guard saved < Self.currentSchemaVersion else { return false }
        defaults.set(Self.currentSchemaVersion, forKey: Keys.schemaVersion)
        lastRelayEnvelopeTime = 0
        stateLock.lock()
        hasCachedPartnerPet = false
        cachedPartnerPet = nil
        cachedAnchorTimestamp = 0
        stateLock.unlock()
        return true
    }

    public func clearPartnerMetadata() {
        partnerOwnerName = nil
        partnerPet = nil
        partnerMessage = nil
        rareInteraction = nil
        lastAppliedRemoteSentAt = 0
        lastNotifiedRemoteSentAt = 0
        lastRelayEnvelopeTime = 0
    }

    /// Generates an 8-character cryptographically random pair code (`SecRandomCopyBytes`).
    public static func generatePairCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var randomBytes = [UInt8](repeating: 0, count: 8)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if status == errSecSuccess {
            return String(randomBytes.map { alphabet[Int($0) % alphabet.count] })
        }
        var rng = SystemRandomNumberGenerator()
        return String((0..<8).map { _ in alphabet.randomElement(using: &rng)! })
    }

    public static func normalizePairCode(_ raw: String) -> String {
        let allowed = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return String(allowed.prefix(16))
    }

    public static func sanitizeDisplayText(_ raw: String, maxLength: Int) -> String {
        let filtered = raw.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        let cleaned = String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxLength))
    }

    public static func sanitizeRelayBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return defaultRelayURL
        }

        let isLocalhost = (host == "localhost" || host == "127.0.0.1")
        guard scheme == "https" || (scheme == "http" && isLocalhost) else {
            return defaultRelayURL
        }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = cleanPath.isEmpty ? "" : "/\(cleanPath)"

        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? defaultRelayURL
    }

    /// Returns a stable even-second aligned timestamp (refreshed at most once every 6 hours)
    /// so `PetTimerGate-Regular` stays < 7 chars (`H:MM:SS`) while keeping `ContentState` equatable
    /// across updates to prevent redundant `Activity.update` XPC wakeups.
    public func stableAnchorTimestamp() -> TimeInterval {
        let now = Date().timeIntervalSince1970
        stateLock.lock()
        defer { stateLock.unlock() }
        if cachedAnchorTimestamp == 0
            || now < cachedAnchorTimestamp + 6.0
            || now - cachedAnchorTimestamp > 21_600 {
            cachedAnchorTimestamp = floor(now / 6.0) * 6.0 - 60.0
        }
        return cachedAnchorTimestamp
    }

    /// Builds a safe, `< 4 KB` `PetActivityAttributes.ContentState` snapshot for Dynamic Island & Lock Screen.
    public func currentContentState() -> PetActivityAttributes.ContentState {
        let profile = selectedPetProfile
        let currentPartner = partnerPet
        let paired = isPaired
        let activeRare = paired && currentPartner != nil ? rareInteraction : nil
        let activeQuirk = activeRare == nil ? soloQuirk : nil
        let effectiveMyAction = activeRare?.kind.myDogAction ?? activeQuirk?.action ?? myAction
        var mySnapshot = CustomPetStore.shared.makeSnapshot(for: profile, action: effectiveMyAction)
        mySnapshot.action = myAction

        return PetActivityAttributes.ContentState(
            myPet: mySnapshot,
            myMessage: myMessage,
            isPaired: paired,
            partnerPet: currentPartner,
            partnerOwnerName: partnerOwnerName,
            partnerMessage: partnerMessage,
            rareInteraction: activeRare,
            soloQuirk: activeQuirk,
            anchorTimestamp: stableAnchorTimestamp()
        ).fittingActivityKitBudget()
    }
}
