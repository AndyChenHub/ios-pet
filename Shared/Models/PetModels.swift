import Foundation
import SwiftUI

/// Centralized feature toggles for backlogged or staged capabilities (see `BACKLOG.md`).
public enum FeatureFlags {
    /// Temporarily disabled (moved to `BACKLOG.md`). Flip to `true` to re-enable custom spritesheet pet creation.
    public static let enableCustomPetCreation: Bool = false
}

/// Built-in high-resolution bundled pet spritesheets in `Assets.xcassets`.
public enum PetCharacter: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case alfie
    case teddy

    public var id: String { rawValue }

    public var defaultName: String {
        switch self {
        case .alfie: return "Alfie"
        case .teddy: return "Teddy"
        }
    }

    public var breedSubtitle: String {
        switch self {
        case .alfie: return "Fox Terrier Mix"
        case .teddy: return "Scruffy Schnauzer Mix"
        }
    }

    public var defaultColorPreset: PetColorPreset {
        switch self {
        case .alfie: return .sunsetOrange
        case .teddy: return .periwinkleBlue
        }
    }

    /// Asset catalog image names for every frame of the given action.
    public func frameAssetNames(for action: PetAction) -> [String] {
        (0..<action.frameCount).map { index in
            "\(rawValue)_\(action.rawValue)_\(index)"
        }
    }

    /// Static preview frame asset name (first frame of idle or given action).
    public func previewAssetName(for action: PetAction = .idle) -> String {
        "\(rawValue)_\(action.rawValue)_0"
    }
}

/// Selectable accent color themes for built-in and custom spritesheet pets.
public enum PetColorPreset: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sunsetOrange
    case periwinkleBlue
    case mintGreen
    case berryPink
    case goldenHoney
    case lavenderPurple

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sunsetOrange:   return "Sunset"
        case .periwinkleBlue: return "Sky"
        case .mintGreen:      return "Mint"
        case .berryPink:      return "Berry"
        case .goldenHoney:    return "Honey"
        case .lavenderPurple: return "Lavender"
        }
    }

    public var color: Color {
        switch self {
        case .sunsetOrange:   return Color(red: 0.96, green: 0.49, blue: 0.29)
        case .periwinkleBlue: return Color(red: 0.56, green: 0.65, blue: 0.96)
        case .mintGreen:      return Color(red: 0.34, green: 0.85, blue: 0.66)
        case .berryPink:      return Color(red: 0.96, green: 0.43, blue: 0.68)
        case .goldenHoney:    return Color(red: 0.98, green: 0.76, blue: 0.28)
        case .lavenderPurple: return Color(red: 0.72, green: 0.54, blue: 0.98)
        }
    }
}

extension PetColorPreset: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = PetColorPreset(rawValue: raw) ?? .sunsetOrange
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// User-selectable pet profile (either a renameable built-in pet or a user-imported custom spritesheet pet).
public struct PetProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var builtInCharacter: PetCharacter?
    public var customSheetID: String?
    public var colorPreset: PetColorPreset

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtitle
        case builtInCharacter
        case customSheetID
        case colorPreset
    }

    public init(
        id: String,
        name: String,
        subtitle: String,
        builtInCharacter: PetCharacter? = nil,
        customSheetID: String? = nil,
        colorPreset: PetColorPreset
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.builtInCharacter = builtInCharacter
        self.customSheetID = customSheetID
        self.colorPreset = colorPreset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Alfie"
        self.subtitle = (try? container.decode(String.self, forKey: .subtitle)) ?? ""
        let builtInRaw = try? container.decodeIfPresent(String.self, forKey: .builtInCharacter)
        self.builtInCharacter = builtInRaw.flatMap { PetCharacter(rawValue: $0) }
        self.customSheetID = try? container.decodeIfPresent(String.self, forKey: .customSheetID)
        self.colorPreset = (try? container.decode(PetColorPreset.self, forKey: .colorPreset)) ?? .sunsetOrange
    }

    public var isCustom: Bool {
        customSheetID != nil && builtInCharacter == nil
    }

    public var themeColor: Color {
        colorPreset.color
    }

    public static let defaultAlfie = PetProfile(
        id: "builtin-alfie",
        name: "Alfie",
        subtitle: PetCharacter.alfie.breedSubtitle,
        builtInCharacter: .alfie,
        customSheetID: nil,
        colorPreset: .sunsetOrange
    )

    public static let defaultTeddy = PetProfile(
        id: "builtin-teddy",
        name: "Teddy",
        subtitle: PetCharacter.teddy.breedSubtitle,
        builtInCharacter: .teddy,
        customSheetID: nil,
        colorPreset: .periwinkleBlue
    )
}

/// Lightweight, self-contained pet state rendered in Dynamic Island, Lock Screen, and connected stages.
/// Dual-encodes `action` (v1-compatible 10-action string) + `v2Action` (full 22-action string) so an updated
/// iPhone and an un-updated v1 iPhone stay 100% connected without ever failing JSON decoding.
public struct IslandPetSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var builtInCharacter: PetCharacter?
    public var customSheetID: String?
    public var colorPreset: PetColorPreset
    public var action: PetAction
    /// Present when rendering a custom spritesheet pet across Dynamic Island / remote sync.
    public var customMicroFrames: [Data]?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case builtInCharacter
        case customSheetID
        case colorPreset
        case action
        case v2Action
        case customMicroFrames
    }

    public init(
        id: String,
        name: String,
        builtInCharacter: PetCharacter? = nil,
        customSheetID: String? = nil,
        colorPreset: PetColorPreset = .sunsetOrange,
        action: PetAction = .idle,
        customMicroFrames: [Data]? = nil
    ) {
        self.id = id
        self.name = name
        self.builtInCharacter = builtInCharacter
        self.customSheetID = customSheetID
        self.colorPreset = colorPreset
        self.action = action
        self.customMicroFrames = customMicroFrames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? "remote-pet"
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Buddy"
        let builtInRaw = try? container.decodeIfPresent(String.self, forKey: .builtInCharacter)
        self.builtInCharacter = builtInRaw.flatMap { PetCharacter(rawValue: $0) }
        self.customSheetID = try? container.decodeIfPresent(String.self, forKey: .customSheetID)
        self.colorPreset = (try? container.decode(PetColorPreset.self, forKey: .colorPreset)) ?? .sunsetOrange

        let v2Raw = try? container.decodeIfPresent(String.self, forKey: .v2Action)
        let legacyRaw = try? container.decodeIfPresent(String.self, forKey: .action)
        if let v2Raw, let exactV2 = PetAction.decodeKnown(from: v2Raw) {
            self.action = exactV2
        } else if let legacyRaw {
            self.action = PetAction.decodeResilient(from: legacyRaw)
        } else {
            self.action = .idle
        }

        self.customMicroFrames = try? container.decodeIfPresent([Data].self, forKey: .customMicroFrames)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(builtInCharacter?.rawValue, forKey: .builtInCharacter)
        try container.encodeIfPresent(customSheetID, forKey: .customSheetID)
        try container.encode(colorPreset, forKey: .colorPreset)
        try container.encode(action.legacyV1WireRawValue, forKey: .action)
        try container.encode(action.rawValue, forKey: .v2Action)
        try container.encodeIfPresent(customMicroFrames, forKey: .customMicroFrames)
    }

    public var themeColor: Color {
        colorPreset.color
    }

    public func withAction(_ newAction: PetAction) -> IslandPetSnapshot {
        var copy = self
        copy.action = newAction
        return copy
    }
}

/// Groups solo animations into everyday Emotions, everyday Tasks, and special-triggered Quirks.
public enum PetActionCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case emotion
    case task
    case quirk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .emotion: return "Emotions"
        case .task:    return "Tasks"
        case .quirk:   return "Special Quirks"
        }
    }
}

/// All 22 sprite animations across Emotions, Tasks, and Special Solo Quirks.
public enum PetAction: String, CaseIterable, Identifiable, Hashable, Sendable {
    // Everyday Emotions (7)
    case happy
    case love
    case waving
    case celebrate
    case sad
    case confused
    case grumpy

    // Everyday Tasks (7)
    case idle
    case working
    case sleeping
    case eating
    case walk
    case review
    case waiting

    // Special-Case Solo Quirks (8)
    case zoomies
    case begging
    case spinning
    case dizzy
    case booping
    case splooting
    case sideEye
    case blep

    public var id: String { rawValue }

    public var category: PetActionCategory {
        switch self {
        case .happy, .love, .waving, .celebrate, .sad, .confused, .grumpy:
            return .emotion
        case .idle, .working, .sleeping, .eating, .walk, .review, .waiting:
            return .task
        case .zoomies, .begging, .spinning, .dizzy, .booping, .splooting, .sideEye, .blep:
            return .quirk
        }
    }

    public var isEverydaySelectable: Bool {
        category != .quirk
    }

    public static let emotionActions: [PetAction] = [
        .happy, .love, .waving, .celebrate, .sad, .confused, .grumpy
    ]

    public static let taskActions: [PetAction] = [
        .idle, .working, .sleeping, .eating, .walk, .review, .waiting
    ]

    public static let everydayActions: [PetAction] = emotionActions + taskActions

    public static let quirkActions: [PetAction] = [
        .booping, .zoomies, .begging, .spinning, .dizzy, .splooting, .sideEye, .blep
    ]

    /// Quick-access buttons displayed inside the Expanded Dynamic Island & Lock Screen banner.
    public static let quickIslandActions: [PetAction] = [
        .happy, .love, .working, .eating, .sleeping
    ]

    public var title: String {
        switch self {
        case .happy:     return "Happy"
        case .love:      return "In Love"
        case .waving:    return "Wave Hi"
        case .celebrate: return "Celebrate"
        case .sad:       return "Sad"
        case .confused:  return "Confused"
        case .grumpy:    return "Grumpy"
        case .idle:      return "Chilling"
        case .working:   return "Working"
        case .sleeping:  return "Sleeping"
        case .eating:    return "Eating"
        case .walk:      return "On a Walk"
        case .review:    return "Studying"
        case .waiting:   return "Waiting"
        case .zoomies:   return "Zoomies!!"
        case .begging:   return "Begging"
        case .spinning:  return "Spinning"
        case .dizzy:     return "Dizzy"
        case .booping:   return "Snoot Boop"
        case .splooting: return "Splooting"
        case .sideEye:   return "Side-Eye"
        case .blep:      return "Derpy Blep"
        }
    }

    public var shortLabel: String {
        switch self {
        case .happy:     return "Happy"
        case .love:      return "Love"
        case .waving:    return "Wave"
        case .celebrate: return "Party"
        case .sad:       return "Sad"
        case .confused:  return "Huh?"
        case .grumpy:    return "Grumpy"
        case .idle:      return "Chill"
        case .working:   return "Work"
        case .sleeping:  return "Sleep"
        case .eating:    return "Eat"
        case .walk:      return "Walk"
        case .review:    return "Study"
        case .waiting:   return "Wait"
        case .zoomies:   return "Zoom"
        case .begging:   return "Beg"
        case .spinning:  return "Spin"
        case .dizzy:     return "Dizzy"
        case .booping:   return "Boop"
        case .splooting: return "Sploot"
        case .sideEye:   return "Judge"
        case .blep:      return "Blep"
        }
    }

    public var statusPhrase: String {
        switch self {
        case .happy:     return "is beaming with joy!"
        case .love:      return "is sending lots of love"
        case .waving:    return "is waving hi!"
        case .celebrate: return "is celebrating!!"
        case .sad:       return "needs a warm hug"
        case .confused:  return "is tilting head confused"
        case .grumpy:    return "is feeling grumpy"
        case .idle:      return "is chilling out"
        case .working:   return "is locked in working"
        case .sleeping:  return "is fast asleep"
        case .eating:    return "is munching snacks"
        case .walk:      return "is out on a walk"
        case .review:    return "is studying closely"
        case .waiting:   return "is waiting patiently"
        case .zoomies:   return "got the turbo zoomies!!"
        case .begging:   return "is begging for treats!"
        case .spinning:  return "is spinning in circles!"
        case .dizzy:     return "spun right into dizzy stars"
        case .booping:   return "got snoot-booped!"
        case .splooting: return "melted into a full sploot"
        case .sideEye:   return "is giving judgey side-eye"
        case .blep:      return "is doing a derpy blep"
        }
    }

    public var emoji: String {
        switch self {
        case .happy:     return "😄"
        case .love:      return "🥰"
        case .waving:    return "👋"
        case .celebrate: return "🎉"
        case .sad:       return "😢"
        case .confused:  return "❓"
        case .grumpy:    return "😤"
        case .idle:      return "😊"
        case .working:   return "💻"
        case .sleeping:  return "💤"
        case .eating:    return "🍖"
        case .walk:      return "🦮"
        case .review:    return "🔍"
        case .waiting:   return "🥺"
        case .zoomies:   return "💨"
        case .begging:   return "🦴"
        case .spinning:  return "🌀"
        case .dizzy:     return "😵‍💫"
        case .booping:   return "🐽"
        case .splooting: return "🫠"
        case .sideEye:   return "👀"
        case .blep:      return "😋"
        }
    }

    /// Number of sliced frames in `Assets.xcassets` for this action (even counts: 4 or 6).
    public var frameCount: Int {
        switch self {
        case .idle, .waiting, .review, .zoomies, .spinning:
            return 6
        default:
            return 4
        }
    }

    /// Frame rate used for smooth in-app `TimelineView` previews.
    public var inAppFPS: Double {
        switch self {
        case .sleeping: return 4.5
        case .sideEye, .blep: return 5.0
        case .sad, .confused, .splooting, .booping: return 5.8
        case .grumpy, .idle, .waiting, .review: return 6.2
        case .love, .dizzy: return 6.8
        case .walk, .working, .eating, .celebrate, .waving: return 7.5
        case .happy, .begging: return 8.0
        case .spinning: return 9.5
        case .zoomies: return 11.0
        }
    }

    public var accentColor: Color {
        switch self {
        case .happy:     return Color(red: 0.99, green: 0.76, blue: 0.26)
        case .love:      return Color(red: 0.98, green: 0.44, blue: 0.68)
        case .waving:    return Color(red: 0.99, green: 0.62, blue: 0.32)
        case .celebrate: return Color(red: 0.99, green: 0.48, blue: 0.56)
        case .sad:       return Color(red: 0.48, green: 0.66, blue: 0.96)
        case .confused:  return Color(red: 0.96, green: 0.78, blue: 0.34)
        case .grumpy:    return Color(red: 0.96, green: 0.40, blue: 0.38)
        case .idle:      return Color(red: 0.40, green: 0.84, blue: 0.62)
        case .working:   return Color(red: 0.42, green: 0.68, blue: 0.98)
        case .sleeping:  return Color(red: 0.62, green: 0.54, blue: 0.98)
        case .eating:    return Color(red: 0.96, green: 0.62, blue: 0.28)
        case .walk:      return Color(red: 0.36, green: 0.84, blue: 0.78)
        case .review:    return Color(red: 0.68, green: 0.84, blue: 0.42)
        case .waiting:   return Color(red: 0.86, green: 0.72, blue: 0.98)
        case .zoomies:   return Color(red: 0.30, green: 0.86, blue: 0.98)
        case .begging:   return Color(red: 0.98, green: 0.68, blue: 0.40)
        case .spinning:  return Color(red: 0.74, green: 0.56, blue: 0.98)
        case .dizzy:     return Color(red: 0.96, green: 0.46, blue: 0.46)
        case .booping:   return Color(red: 0.98, green: 0.56, blue: 0.78)
        case .splooting: return Color(red: 0.54, green: 0.82, blue: 0.72)
        case .sideEye:   return Color(red: 0.88, green: 0.74, blue: 0.38)
        case .blep:      return Color(red: 0.98, green: 0.58, blue: 0.68)
        }
    }
}

extension PetAction: Codable {
    /// Decodes a known v2 or legacy v1 `PetAction` identifier, returning `nil` if unrecognized.
    public static func decodeKnown(from raw: String) -> PetAction? {
        if let exact = PetAction(rawValue: raw) {
            return exact
        }
        switch raw {
        case "jumping": return .celebrate
        case "runRight", "runLeft": return .walk
        case "side_eye": return .sideEye
        default: return nil
        }
    }

    /// Decodes any `PetAction` string resiliently, falling back to `.idle` on unknown future values.
    public static func decodeResilient(from raw: String) -> PetAction {
        decodeKnown(from: raw) ?? .idle
    }

    /// Maps all 22 v2 actions to the 10 legacy v1 `PetAction` strings so un-updated v1 phones decode every packet cleanly.
    public var legacyV1WireRawValue: String {
        switch self {
        case .idle, .eating, .blep:
            return "idle"
        case .sleeping, .splooting:
            return "sleeping"
        case .waving, .booping:
            return "waving"
        case .happy, .love, .celebrate:
            return "jumping"
        case .walk:
            return "runRight"
        case .zoomies:
            return "runLeft"
        case .waiting, .sad, .confused, .begging:
            return "waiting"
        case .working:
            return "working"
        case .review, .sideEye:
            return "review"
        case .dizzy, .grumpy, .spinning:
            return "dizzy"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = Self.decodeResilient(from: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Temporary special-triggered solo animation that plays briefly without overwriting your chosen Emotion/Task.
public struct SoloPetQuirk: Codable, Hashable, Sendable {
    public var id: String
    public var action: PetAction
    public var triggerBadge: String
    public var startedAt: TimeInterval
    public var expiresAt: TimeInterval

    public init(
        id: String = UUID().uuidString,
        action: PetAction,
        triggerBadge: String,
        startedAt: TimeInterval = Date().timeIntervalSince1970,
        duration: TimeInterval = 32
    ) {
        self.id = id
        self.action = action
        self.triggerBadge = triggerBadge
        self.startedAt = startedAt
        self.expiresAt = startedAt + duration
    }

    public func isActive(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        now <= expiresAt
    }
}

/// Rarity tiers for synchronized special two-dog interactions.
public enum InteractionRarity: String, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case rare = "rare"
    case superRare = "super_rare"
    case ultraRare = "ultra_rare"

    public var rank: Int {
        switch self {
        case .rare:      return 1
        case .superRare: return 2
        case .ultraRare: return 3
        }
    }

    public static func < (lhs: InteractionRarity, rhs: InteractionRarity) -> Bool {
        lhs.rank < rhs.rank
    }

    public var title: String {
        switch self {
        case .rare:      return "Rare"
        case .superRare: return "Super Rare"
        case .ultraRare: return "Ultra Rare"
        }
    }

    public var badgeLabel: String {
        switch self {
        case .rare:      return "✨ RARE"
        case .superRare: return "💎 SUPER RARE"
        case .ultraRare: return "👑 ULTRA RARE"
        }
    }

    public var accentColor: Color {
        switch self {
        case .rare:      return Color(red: 0.98, green: 0.45, blue: 0.68)
        case .superRare: return Color(red: 0.62, green: 0.46, blue: 1.00)
        case .ultraRare: return Color(red: 1.00, green: 0.80, blue: 0.28)
        }
    }

    public var badgeTextColor: Color {
        switch self {
        case .rare:      return Color(red: 1.00, green: 0.76, blue: 0.88)
        case .superRare: return Color(red: 0.84, green: 0.78, blue: 1.00)
        case .ultraRare: return Color(red: 1.00, green: 0.90, blue: 0.52)
        }
    }
}

/// Thematic grouping for the 20 standard duo scenes and 10 long story skits.
public enum DuoInteractionCategory: String, Codable, CaseIterable, Sendable {
    case sweet
    case funny
    case chaos
    case mythicSkit

    public var title: String {
        switch self {
        case .sweet:      return "Sweet & Cozy"
        case .funny:      return "Funny & Sassy"
        case .chaos:      return "Sibling Chaos"
        case .mythicSkit: return "Story Skit"
        }
    }
}

/// All 20 combined two-dog animations (`duo_*`) plus 10 3-act long story skits (`skit_*`),
/// curated into Rare, Super Rare, and Ultra Rare (cutest & funniest) tiers.
public enum RareInteractionKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    // 20 Standard Combined Duo Scenes
    case tugOfWar = "tug_of_war"
    case stealingFood = "stealing_food"
    case zoomieCrash = "zoomie_crash"
    case pawBonk = "paw_bonk"
    case sittingOnHead = "sitting_on_head"
    case buttSniff = "butt_sniff"
    case blanketHog = "blanket_hog"
    case biteyFace = "bitey_face"
    case blameEachOther = "blame_each_other"
    case earNibbleAnnoy = "ear_nibble_annoy"
    case barkArgument = "bark_argument"
    case foodEnvyBeg = "food_envy_beg"
    case zoomieChase = "zoomie_chase"
    case spinIntoDizzy = "spin_into_dizzy"
    case interruptWork = "interrupt_work"
    case doubleSideEye = "double_side_eye"
    case sharedBraincell = "shared_braincell"
    case doubleBegSquad = "double_beg_squad"
    case cheerUpLove = "cheer_up_love"
    case cozyNapTruce = "cozy_nap_truce"

    // 10 Long 3-Act Story Skits (~6.5s-7.0s each)
    case skitKibbleHeist = "skit_kibble_heist_chase"
    case skitAnnoyUntilBonk = "skit_annoy_until_bonk"
    case skitTugOfWarSaga = "skit_tug_of_war_saga"
    case skitZoomieCrashWipeout = "skit_zoomie_crash_wipeout"
    case skitDetectiveWhodunnit = "skit_detective_whodunnit"
    case skitBlanketWarBurrito = "skit_blanket_war_burrito"
    case skitPersonalSpaceHeadSit = "skit_personal_space_head_sit"
    case skitWfhMeetingDisaster = "skit_wfh_meeting_disaster"
    case skitBiteyFaceToNap = "skit_bitey_face_to_nap"
    case skitSadToPartyRescue = "skit_sad_to_party_rescue"

    public var id: String { rawValue }

    /// True for the 10 full-length 3-act story skits (6-beat Dynamic Island loop + animated WebP dataset).
    public var isLongSkit: Bool {
        category == .mythicSkit
    }

    /// Curated rarity tier: Rare (playful antics), Super Rare (sweetest/sassiest), Ultra Rare (cutest & funniest 3-act stories).
    public var rarity: InteractionRarity {
        switch self {
        case .skitBlanketWarBurrito,
             .skitSadToPartyRescue,
             .skitBiteyFaceToNap,
             .skitPersonalSpaceHeadSit,
             .skitDetectiveWhodunnit,
             .skitWfhMeetingDisaster,
             .skitAnnoyUntilBonk,
             .skitKibbleHeist:
            return .ultraRare

        case .cheerUpLove,
             .cozyNapTruce,
             .doubleBegSquad,
             .sittingOnHead,
             .buttSniff,
             .blameEachOther,
             .doubleSideEye,
             .sharedBraincell,
             .skitTugOfWarSaga,
             .skitZoomieCrashWipeout:
            return .superRare

        case .tugOfWar,
             .stealingFood,
             .zoomieCrash,
             .pawBonk,
             .blanketHog,
             .biteyFace,
             .earNibbleAnnoy,
             .barkArgument,
             .foodEnvyBeg,
             .zoomieChase,
             .spinIntoDizzy,
             .interruptWork:
            return .rare
        }
    }

    public static let rareCases: [RareInteractionKind] = allCases.filter { $0.rarity == .rare }
    public static let superRareCases: [RareInteractionKind] = allCases.filter { $0.rarity == .superRare }
    public static let ultraRareCases: [RareInteractionKind] = allCases.filter { $0.rarity == .ultraRare }

    public static func cases(for rarity: InteractionRarity) -> [RareInteractionKind] {
        switch rarity {
        case .rare:      return rareCases
        case .superRare: return superRareCases
        case .ultraRare: return ultraRareCases
        }
    }

    /// Asset catalog image names (`duo_<key>_0..3` for standard scenes, `duo_<key>_0..5` 6-beat frames for skits).
    public var frameAssetNames: [String] {
        let count = isLongSkit ? 6 : 4
        return (0..<count).map { "duo_\(rawValue)_\($0)" }
    }

    /// Name of the full 50-80 frame animated WebP `.dataset` in `Assets.xcassets/LongSkits` for in-app playback.
    public var longSkitDatasetName: String? {
        isLongSkit ? rawValue : nil
    }

    public var defaultDuration: TimeInterval {
        isLongSkit ? 66 : 44
    }

    /// Maps a standard duo interaction to its matching ultra-rare 3-act story skit when a rare jackpot rolls!
    public var matchingUltraRareSkit: RareInteractionKind {
        switch self {
        case .stealingFood, .foodEnvyBeg, .doubleBegSquad:
            return .skitKibbleHeist
        case .pawBonk, .earNibbleAnnoy, .barkArgument:
            return .skitAnnoyUntilBonk
        case .tugOfWar:
            return .skitTugOfWarSaga
        case .zoomieCrash, .zoomieChase, .spinIntoDizzy:
            return .skitZoomieCrashWipeout
        case .blameEachOther, .doubleSideEye, .buttSniff, .sharedBraincell:
            return .skitDetectiveWhodunnit
        case .blanketHog, .cozyNapTruce:
            return .skitBlanketWarBurrito
        case .sittingOnHead:
            return .skitPersonalSpaceHeadSit
        case .interruptWork:
            return .skitWfhMeetingDisaster
        case .biteyFace:
            return .skitBiteyFaceToNap
        case .cheerUpLove:
            return .skitSadToPartyRescue
        default:
            return self
        }
    }

    public var category: DuoInteractionCategory {
        switch self {
        case .doubleBegSquad, .cheerUpLove, .cozyNapTruce:
            return .sweet
        case .sittingOnHead, .buttSniff, .blameEachOther, .foodEnvyBeg,
             .interruptWork, .doubleSideEye, .sharedBraincell:
            return .funny
        case .tugOfWar, .stealingFood, .zoomieCrash, .pawBonk, .blanketHog,
             .biteyFace, .earNibbleAnnoy, .barkArgument, .zoomieChase, .spinIntoDizzy:
            return .chaos
        case .skitKibbleHeist, .skitAnnoyUntilBonk, .skitTugOfWarSaga, .skitZoomieCrashWipeout,
             .skitDetectiveWhodunnit, .skitBlanketWarBurrito, .skitPersonalSpaceHeadSit,
             .skitWfhMeetingDisaster, .skitBiteyFaceToNap, .skitSadToPartyRescue:
            return .mythicSkit
        }
    }

    public var title: String {
        switch self {
        case .tugOfWar:                 return "Tug-of-War!"
        case .stealingFood:             return "Kibble Heist!"
        case .zoomieCrash:              return "Zoomie Crash!"
        case .pawBonk:                  return "Sibling BONK!"
        case .sittingOnHead:            return "Sitting on Head"
        case .buttSniff:                return "Butt-Sniff Ambush"
        case .blanketHog:               return "Blanket Hog!"
        case .biteyFace:                return "Bitey-Face!"
        case .blameEachOther:           return "He Did It!!"
        case .earNibbleAnnoy:           return "Pester & Ear Nom"
        case .barkArgument:             return "Yap-Off & Hmph!"
        case .foodEnvyBeg:              return "Eating vs Begging"
        case .zoomieChase:              return "Turbo Zoomie Chase"
        case .spinIntoDizzy:            return "Spin Into Dizzy"
        case .interruptWork:            return "Interrupting WFH"
        case .doubleSideEye:            return "Double Side-Eye"
        case .sharedBraincell:          return "One Shared Braincell"
        case .doubleBegSquad:           return "Double Beg Squad"
        case .cheerUpLove:              return "Cheer Up Cuddle"
        case .cozyNapTruce:             return "Cozy Nap Truce"
        case .skitKibbleHeist:          return "The Great Kibble Heist"
        case .skitAnnoyUntilBonk:       return "Pester Until MEGA BONK!"
        case .skitTugOfWarSaga:         return "Epic Tug-of-War Showdown"
        case .skitZoomieCrashWipeout:   return "Double Zoomie Wipeout"
        case .skitDetectiveWhodunnit:   return "Detective Dog Whodunnit"
        case .skitBlanketWarBurrito:    return "Blanket War & Burrito"
        case .skitPersonalSpaceHeadSit: return "Head-Sit Personal Space"
        case .skitWfhMeetingDisaster:   return "WFH Webcam Photobomb"
        case .skitBiteyFaceToNap:       return "Bitey-Face Into Nap Crash"
        case .skitSadToPartyRescue:     return "Surprise Cheer-Up Party!"
        }
    }

    public var badgeEmoji: String {
        switch self {
        case .tugOfWar:                 return "🪢🐾"
        case .stealingFood:             return "🍖💨"
        case .zoomieCrash:              return "💥🐾"
        case .pawBonk:                  return "🐾💢"
        case .sittingOnHead:            return "🐶👑"
        case .buttSniff:                return "🍑👀"
        case .blanketHog:               return "🛌😤"
        case .biteyFace:                return "😆🦷"
        case .blameEachOther:           return "👉🐶"
        case .earNibbleAnnoy:           return "👂😈"
        case .barkArgument:             return "🗣️💢"
        case .foodEnvyBeg:              return "🍖🥺"
        case .zoomieChase:              return "⚡💨"
        case .spinIntoDizzy:            return "🌀😵‍💫"
        case .interruptWork:            return "💻🐾"
        case .doubleSideEye:            return "👀😒"
        case .sharedBraincell:          return "🧠✨"
        case .doubleBegSquad:           return "🥺🦴"
        case .cheerUpLove:              return "💖🥰"
        case .cozyNapTruce:             return "💕💤"
        case .skitKibbleHeist:          return "🌟🍖"
        case .skitAnnoyUntilBonk:       return "🌟💥"
        case .skitTugOfWarSaga:         return "🌟🪢"
        case .skitZoomieCrashWipeout:   return "🌟💨"
        case .skitDetectiveWhodunnit:   return "🌟🔍"
        case .skitBlanketWarBurrito:    return "🌟🌯"
        case .skitPersonalSpaceHeadSit: return "🌟👑"
        case .skitWfhMeetingDisaster:   return "🌟💻"
        case .skitBiteyFaceToNap:       return "🌟💤"
        case .skitSadToPartyRescue:     return "🌟🎉"
        }
    }

    public var centerIcon: String {
        switch self {
        case .tugOfWar, .skitTugOfWarSaga:           return "🪢"
        case .stealingFood, .skitKibbleHeist:        return "🍖"
        case .zoomieCrash, .skitZoomieCrashWipeout:  return "💥"
        case .pawBonk, .skitAnnoyUntilBonk:          return "💢"
        case .sittingOnHead, .skitPersonalSpaceHeadSit: return "👑"
        case .buttSniff:                             return "👀"
        case .blanketHog, .skitBlanketWarBurrito:    return "🛌"
        case .biteyFace, .skitBiteyFaceToNap:        return "😆"
        case .blameEachOther:                        return "👉"
        case .earNibbleAnnoy:                        return "😈"
        case .barkArgument:                          return "🗣️"
        case .foodEnvyBeg:                           return "🥺"
        case .zoomieChase:                           return "⚡"
        case .spinIntoDizzy:                         return "🌀"
        case .interruptWork, .skitWfhMeetingDisaster: return "💻"
        case .doubleSideEye:                         return "👀"
        case .sharedBraincell:                       return "🧠"
        case .doubleBegSquad:                        return "🦴"
        case .cheerUpLove, .skitSadToPartyRescue:    return "💖"
        case .cozyNapTruce:                          return "💤"
        case .skitDetectiveWhodunnit:                return "🔍"
        }
    }

    public var inAppFPS: Double {
        if isLongSkit {
            return 11.76 // 85ms native skit tick rate
        }
        switch self {
        case .zoomieChase: return 9.5
        case .tugOfWar, .biteyFace, .doubleBegSquad: return 8.0
        case .foodEnvyBeg, .spinIntoDizzy, .zoomieCrash: return 7.0
        case .barkArgument, .earNibbleAnnoy, .interruptWork, .cheerUpLove: return 6.4
        case .pawBonk, .stealingFood, .buttSniff, .sittingOnHead, .blanketHog, .blameEachOther: return 5.5
        case .doubleSideEye, .sharedBraincell: return 5.0
        case .cozyNapTruce: return 4.5
        default: return 6.0
        }
    }

    /// Fallback / Compact Dynamic Island pose for my pet during this duo interaction.
    public var myDogAction: PetAction {
        switch self {
        case .tugOfWar, .skitTugOfWarSaga:               return .happy
        case .stealingFood, .skitKibbleHeist:            return .eating
        case .zoomieCrash, .skitZoomieCrashWipeout:      return .dizzy
        case .pawBonk, .skitAnnoyUntilBonk:              return .booping
        case .sittingOnHead, .skitPersonalSpaceHeadSit:  return .blep
        case .buttSniff:                                 return .confused
        case .blanketHog, .skitBlanketWarBurrito:        return .sleeping
        case .biteyFace, .skitBiteyFaceToNap:            return .celebrate
        case .blameEachOther:                            return .grumpy
        case .earNibbleAnnoy:                            return .happy
        case .barkArgument:                              return .grumpy
        case .foodEnvyBeg:                               return .eating
        case .zoomieChase:                               return .zoomies
        case .spinIntoDizzy:                             return .spinning
        case .interruptWork, .skitWfhMeetingDisaster:    return .working
        case .doubleSideEye:                             return .sideEye
        case .sharedBraincell:                           return .confused
        case .doubleBegSquad:                            return .begging
        case .cheerUpLove, .skitSadToPartyRescue:        return .celebrate
        case .cozyNapTruce:                              return .sleeping
        case .skitDetectiveWhodunnit:                    return .review
        }
    }

    /// Fallback / Compact Dynamic Island pose for the connected pet during this duo interaction.
    public var partnerDogAction: PetAction {
        switch self {
        case .tugOfWar, .skitTugOfWarSaga:               return .grumpy
        case .stealingFood, .skitKibbleHeist:            return .zoomies
        case .zoomieCrash, .skitZoomieCrashWipeout:      return .dizzy
        case .pawBonk, .skitAnnoyUntilBonk:              return .dizzy
        case .sittingOnHead, .skitPersonalSpaceHeadSit:  return .grumpy
        case .buttSniff:                                 return .sideEye
        case .blanketHog, .skitBlanketWarBurrito:        return .sleeping
        case .biteyFace, .skitBiteyFaceToNap:            return .sleeping
        case .blameEachOther:                            return .sideEye
        case .earNibbleAnnoy:                            return .sleeping
        case .barkArgument:                              return .grumpy
        case .foodEnvyBeg:                               return .begging
        case .zoomieChase:                               return .zoomies
        case .spinIntoDizzy:                             return .dizzy
        case .interruptWork, .skitWfhMeetingDisaster:    return .booping
        case .doubleSideEye:                             return .sideEye
        case .sharedBraincell:                           return .blep
        case .doubleBegSquad:                            return .begging
        case .cheerUpLove, .skitSadToPartyRescue:        return .love
        case .cozyNapTruce:                              return .sleeping
        case .skitDetectiveWhodunnit:                    return .sideEye
        }
    }

    public func descriptionText(myPetName: String, partnerPetName: String) -> String {
        switch self {
        case .tugOfWar:
            return "\(myPetName) & \(partnerPetName) started a fierce Tug-of-War!"
        case .stealingFood:
            return "Kibble Heist! \(myPetName) & \(partnerPetName) are raiding the bowl!"
        case .zoomieCrash:
            return "\(myPetName) & \(partnerPetName) bonked mid-zoomie!"
        case .pawBonk:
            return "BONK! \(myPetName) & \(partnerPetName) threw a sassy paw!"
        case .sittingOnHead:
            return "\(myPetName) & \(partnerPetName) forgot personal space exists!"
        case .buttSniff:
            return "Surprise butt-sniff ambush between \(myPetName) & \(partnerPetName)!"
        case .blanketHog:
            return "\(myPetName) & \(partnerPetName) are fighting over the blanket!"
        case .biteyFace:
            return "\(myPetName) & \(partnerPetName) broke into playful Bitey-Face!"
        case .blameEachOther:
            return "“They did it!!” \(myPetName) & \(partnerPetName) are pointing paws!"
        case .earNibbleAnnoy:
            return "Ear nom! \(myPetName) & \(partnerPetName) won't let each other rest!"
        case .barkArgument:
            return "\(myPetName) & \(partnerPetName) are having a dramatic Yap-Off!"
        case .foodEnvyBeg:
            return "One feasts while the other begs — \(myPetName) & \(partnerPetName)!"
        case .zoomieChase:
            return "\(myPetName) & \(partnerPetName) hit maximum Turbo Zoomies!"
        case .spinIntoDizzy:
            return "\(myPetName) & \(partnerPetName) spun right into dizzy stars!"
        case .interruptWork:
            return "No working allowed! \(myPetName) & \(partnerPetName) crashed WFH!"
        case .doubleSideEye:
            return "\(myPetName) & \(partnerPetName) are giving synchronized side-eye!"
        case .sharedBraincell:
            return "\(myPetName) & \(partnerPetName) are sharing one single braincell!"
        case .doubleBegSquad:
            return "Double puppy eyes! \(myPetName) & \(partnerPetName) formed a Beg Squad!"
        case .cheerUpLove:
            return "\(myPetName) & \(partnerPetName) huddled up for sweet cuddles!"
        case .cozyNapTruce:
            return "\(myPetName) & \(partnerPetName) called a truce and curled up to nap!"
        case .skitKibbleHeist:
            return "\(myPetName) & \(partnerPetName) staged a full 3-act Great Kibble Heist chase!"
        case .skitAnnoyUntilBonk:
            return "Nonstop pestering between \(myPetName) & \(partnerPetName) ended in a MEGA BONK!"
        case .skitTugOfWarSaga:
            return "\(myPetName) & \(partnerPetName) went all-out in an epic Tug-of-War saga!"
        case .skitZoomieCrashWipeout:
            return "\(myPetName) & \(partnerPetName) hit supersonic zoomies into a wipeout!"
        case .skitDetectiveWhodunnit:
            return "Detective \(myPetName) & \(partnerPetName) are solving a mystery whodunnit!"
        case .skitBlanketWarBurrito:
            return "\(myPetName) & \(partnerPetName) fought a blanket war into one cozy pup burrito!"
        case .skitPersonalSpaceHeadSit:
            return "Zero personal space! \(myPetName) & \(partnerPetName) pulled a legendary head-sit!"
        case .skitWfhMeetingDisaster:
            return "\(myPetName) & \(partnerPetName) photobombed the WFH meeting on live webcam!"
        case .skitBiteyFaceToNap:
            return "\(myPetName) & \(partnerPetName) wrestled until crashing straight into a nap!"
        case .skitSadToPartyRescue:
            return "\(myPetName) & \(partnerPetName) turned a sad moment into a surprise party!"
        }
    }
}

extension RareInteractionKind: Codable {
    /// Decodes a known v2 or legacy v1 `RareInteractionKind`, returning `nil` if unrecognized.
    public static func decodeKnown(from raw: String) -> RareInteractionKind? {
        if let exact = RareInteractionKind(rawValue: raw) {
            return exact
        }
        switch raw {
        case "noseBoop":    return .cheerUpLove
        case "zoomieChase": return .zoomieChase
        case "jumpParty":   return .tugOfWar
        case "snuggleNap":  return .cozyNapTruce
        default:            return nil
        }
    }

    public static func decodeResilient(from raw: String) -> RareInteractionKind {
        decodeKnown(from: raw) ?? .cheerUpLove
    }

    /// Maps all 30 v2 duo interactions & skits onto the 4 legacy v1 `RareInteractionKind` strings
    /// so an un-updated v1 iPhone decodes and plays every duo event without dropping packets.
    public var legacyV1WireRawValue: String {
        switch self {
        case .cheerUpLove, .sittingOnHead, .buttSniff, .foodEnvyBeg,
             .interruptWork, .doubleBegSquad, .skitPersonalSpaceHeadSit,
             .skitWfhMeetingDisaster, .skitSadToPartyRescue:
            return "noseBoop"
        case .zoomieChase, .zoomieCrash, .stealingFood, .spinIntoDizzy,
             .skitKibbleHeist, .skitZoomieCrashWipeout:
            return "zoomieChase"
        case .tugOfWar, .pawBonk, .biteyFace, .blameEachOther, .earNibbleAnnoy,
             .barkArgument, .doubleSideEye, .sharedBraincell,
             .skitAnnoyUntilBonk, .skitTugOfWarSaga, .skitDetectiveWhodunnit:
            return "jumpParty"
        case .blanketHog, .cozyNapTruce, .skitBlanketWarBurrito, .skitBiteyFaceToNap:
            return "snuggleNap"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = Self.decodeResilient(from: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Active combined two-dog event synchronized across both paired iPhones.
/// Dual-encodes `kind` (v1-compatible 4-kind string) + `v2Kind` (full 30-kind string) for seamless cross-version sync.
public struct RarePetInteraction: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RareInteractionKind
    public var triggerBadge: String?
    public var startedAt: TimeInterval
    public var expiresAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case v2Kind
        case triggerBadge
        case startedAt
        case expiresAt
    }

    public init(
        id: String = UUID().uuidString,
        kind: RareInteractionKind,
        triggerBadge: String? = nil,
        startedAt: TimeInterval = Date().timeIntervalSince1970,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.triggerBadge = triggerBadge
        self.startedAt = startedAt
        self.expiresAt = startedAt + (duration ?? kind.defaultDuration)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString

        let v2Raw = try? container.decodeIfPresent(String.self, forKey: .v2Kind)
        let legacyRaw = try? container.decodeIfPresent(String.self, forKey: .kind)
        if let v2Raw, let exactV2 = RareInteractionKind.decodeKnown(from: v2Raw) {
            self.kind = exactV2
        } else if let legacyRaw {
            self.kind = RareInteractionKind.decodeResilient(from: legacyRaw)
        } else {
            self.kind = .cheerUpLove
        }

        self.triggerBadge = try? container.decodeIfPresent(String.self, forKey: .triggerBadge)
        let now = Date().timeIntervalSince1970
        let decodedStart = (try? container.decode(TimeInterval.self, forKey: .startedAt)) ?? now
        self.startedAt = decodedStart
        self.expiresAt = (try? container.decode(TimeInterval.self, forKey: .expiresAt)) ?? (decodedStart + self.kind.defaultDuration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind.legacyV1WireRawValue, forKey: .kind)
        try container.encode(kind.rawValue, forKey: .v2Kind)
        try container.encodeIfPresent(triggerBadge, forKey: .triggerBadge)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(expiresAt, forKey: .expiresAt)
    }

    public var effectiveTriggerBadge: String {
        if let triggerBadge, !triggerBadge.isEmpty {
            return triggerBadge
        }
        return kind.rarity.badgeLabel
    }

    public func isActive(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        now <= expiresAt
    }
}

/// Exposes the stamped IPA semantic version, CI build number, and short commit SHA inside the app UI.
public enum AppBuildInfo {
    public static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.2.2"
    }

    public static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }

    public static var gitSHA: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "IslandPupGitSHA") as? String) ?? ""
        if raw.isEmpty || raw == "local" || raw.contains("$(") {
            return ""
        }
        return raw
    }

    public static var displayLabel: String {
        if gitSHA.isEmpty {
            return "IslandPup v\(version) • Build \(build)"
        }
        return "IslandPup v\(version) • Build \(build) (\(gitSHA))"
    }
}
