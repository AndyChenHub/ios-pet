import Foundation

/// Persists pet selection and phone-to-phone pairing state across both the App Group
/// container (when available) and standard UserDefaults (for unsigned/free sideloading).
public final class SharedStorage: @unchecked Sendable {
    public static let shared = SharedStorage()
    public static let appGroupIdentifier = "group.com.islandpup.shared"

    private let groupDefaults: UserDefaults?
    private let standardDefaults: UserDefaults

    private enum Keys {
        static let deviceId = "islandpup.deviceId"
        static let myName = "islandpup.myName"
        static let myCharacter = "islandpup.myCharacter"
        static let myAction = "islandpup.myAction"
        static let lastSenderName = "islandpup.lastSenderName"
        static let lastNote = "islandpup.lastNote"
        static let pairCode = "islandpup.pairCode"
        static let relayBaseURL = "islandpup.relayBaseURL"
        static let partnerName = "islandpup.partnerName"
        static let partnerCharacter = "islandpup.partnerCharacter"
        static let partnerAction = "islandpup.partnerAction"
        static let lastAppliedRemoteSentAt = "islandpup.lastAppliedRemoteSentAt"
    }

    private init() {
        self.groupDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        self.standardDefaults = .standard
    }

    private func string(forKey key: String) -> String? {
        if let val = groupDefaults?.string(forKey: key), !val.isEmpty {
            return val
        }
        return standardDefaults.string(forKey: key)
    }

    private func setString(_ value: String?, forKey key: String) {
        if let value {
            groupDefaults?.set(value, forKey: key)
            standardDefaults.set(value, forKey: key)
        } else {
            groupDefaults?.removeObject(forKey: key)
            standardDefaults.removeObject(forKey: key)
        }
    }

    private func double(forKey key: String) -> Double {
        let g = groupDefaults?.double(forKey: key) ?? 0
        let s = standardDefaults.double(forKey: key)
        return max(g, s)
    }

    private func setDouble(_ value: Double, forKey key: String) {
        groupDefaults?.set(value, forKey: key)
        standardDefaults.set(value, forKey: key)
    }

    public var deviceId: String {
        if let existing = string(forKey: Keys.deviceId), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        setString(fresh, forKey: Keys.deviceId)
        return fresh
    }

    public var myName: String {
        get { string(forKey: Keys.myName) ?? "Friend" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            setString(trimmed.isEmpty ? "Friend" : String(trimmed.prefix(20)), forKey: Keys.myName)
        }
    }

    public var myCharacter: PetCharacter {
        get {
            guard let raw = string(forKey: Keys.myCharacter),
                  let pet = PetCharacter(rawValue: raw) else {
                return .alfie
            }
            return pet
        }
        set { setString(newValue.rawValue, forKey: Keys.myCharacter) }
    }

    public var myAction: PetAction {
        get {
            guard let raw = string(forKey: Keys.myAction),
                  let act = PetAction(rawValue: raw) else {
                return .idle
            }
            return act
        }
        set { setString(newValue.rawValue, forKey: Keys.myAction) }
    }

    public var lastSenderName: String? {
        get { string(forKey: Keys.lastSenderName) }
        set { setString(newValue, forKey: Keys.lastSenderName) }
    }

    public var lastNote: String? {
        get { string(forKey: Keys.lastNote) }
        set { setString(newValue, forKey: Keys.lastNote) }
    }

    public var pairCode: String {
        get { Self.normalizePairCode(string(forKey: Keys.pairCode) ?? "") }
        set { setString(Self.normalizePairCode(newValue), forKey: Keys.pairCode) }
    }

    public var isPaired: Bool {
        !pairCode.isEmpty
    }

    public var relayBaseURL: String {
        get {
            let url = string(forKey: Keys.relayBaseURL) ?? "https://ntfy.sh"
            let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return cleaned.isEmpty ? "https://ntfy.sh" : cleaned
        }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            setString(cleaned.isEmpty ? "https://ntfy.sh" : cleaned, forKey: Keys.relayBaseURL)
        }
    }

    public var partnerName: String? {
        get { string(forKey: Keys.partnerName) }
        set { setString(newValue, forKey: Keys.partnerName) }
    }

    public var partnerCharacter: PetCharacter? {
        get {
            guard let raw = string(forKey: Keys.partnerCharacter) else { return nil }
            return PetCharacter(rawValue: raw)
        }
        set { setString(newValue?.rawValue, forKey: Keys.partnerCharacter) }
    }

    public var partnerAction: PetAction? {
        get {
            guard let raw = string(forKey: Keys.partnerAction) else { return nil }
            return PetAction(rawValue: raw)
        }
        set { setString(newValue?.rawValue, forKey: Keys.partnerAction) }
    }

    public var lastAppliedRemoteSentAt: TimeInterval {
        get { double(forKey: Keys.lastAppliedRemoteSentAt) }
        set { setDouble(newValue, forKey: Keys.lastAppliedRemoteSentAt) }
    }

    public func clearPartnerMetadata() {
        partnerName = nil
        partnerCharacter = nil
        partnerAction = nil
    }

    /// Generates a friendly 6-character alphanumeric pair code (excluding ambiguous 0/O/1/I).
    public static func generatePairCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in alphabet.randomElement() })
    }

    public static func normalizePairCode(_ raw: String) -> String {
        let allowed = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(allowed.prefix(12))
    }

    /// Builds a current `PetActivityAttributes.ContentState` snapshot from stored state.
    public func currentContentState() -> PetActivityAttributes.ContentState {
        PetActivityAttributes.ContentState(
            character: myCharacter,
            action: myAction,
            senderName: lastSenderName,
            note: lastNote,
            isPaired: isPaired,
            partnerCharacter: partnerCharacter,
            partnerAction: partnerAction
        )
    }
}
