import Foundation
import Security

/// Persists pet selection and phone-to-phone pairing state across both the App Group
/// container (when available) and standard UserDefaults (for unsigned/free sideloading).
public final class SharedStorage: @unchecked Sendable {
    public static let shared = SharedStorage()
    public static let appGroupIdentifier = "group.com.islandpup.shared"
    public static let defaultRelayURL = "https://ntfy.sh"

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
            let sanitized = Self.sanitizeDisplayText(newValue, maxLength: 20)
            setString(sanitized.isEmpty ? "Friend" : sanitized, forKey: Keys.myName)
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
        get { Self.sanitizeRelayBaseURL(string(forKey: Keys.relayBaseURL) ?? Self.defaultRelayURL) }
        set { setString(Self.sanitizeRelayBaseURL(newValue), forKey: Keys.relayBaseURL) }
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
        lastAppliedRemoteSentAt = 0
    }

    /// Generates an 8-character cryptographically random pair code (40 bits of entropy,
    /// using unambiguous uppercase characters and `SecRandomCopyBytes`).
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

    /// Strips control characters and enforces a strict character cap on untrusted display strings.
    public static func sanitizeDisplayText(_ raw: String, maxLength: Int) -> String {
        let filtered = raw.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        let cleaned = String(String.UnicodeScalarView(filtered))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maxLength))
    }

    /// Enforces HTTPS (allowing HTTP only for localhost loopback testing) and strips credentials/queries.
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
