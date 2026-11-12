import Foundation
import SwiftUI

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
        case .alfie: return "Chibi Terrier Pup"
        case .teddy: return "Scruffy Schnauzer Pup"
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
public enum PetColorPreset: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
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

/// User-selectable pet profile (either a renameable built-in pet or a user-imported custom spritesheet pet).
public struct PetProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var builtInCharacter: PetCharacter?
    public var customSheetID: String?
    public var colorPreset: PetColorPreset

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

/// Lightweight, self-contained pet state rendered in Dynamic Island, Lock Screen, and Partner stages.
public struct IslandPetSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var builtInCharacter: PetCharacter?
    public var customSheetID: String?
    public var colorPreset: PetColorPreset
    public var action: PetAction
    /// Present when rendering a custom spritesheet pet across Dynamic Island / remote partner sync.
    public var customMicroFrames: [Data]?

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

    public var themeColor: Color {
        colorPreset.color
    }

    public func withAction(_ newAction: PetAction) -> IslandPetSnapshot {
        var copy = self
        copy.action = newAction
        return copy
    }
}

/// Rare spontaneous interactions where both connected dogs play or cuddle together on the Dynamic Island.
public enum RareInteractionKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case noseBoop
    case zoomieChase
    case jumpParty
    case snuggleNap

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .noseBoop:    return "Nose Boop!"
        case .zoomieChase: return "Play Zoomies!"
        case .jumpParty:   return "Puppy Dance!"
        case .snuggleNap:  return "Snuggle Nap!"
        }
    }

    public var badgeEmoji: String {
        switch self {
        case .noseBoop:    return "💖"
        case .zoomieChase: return "🐾✨"
        case .jumpParty:   return "🎉✨"
        case .snuggleNap:  return "💕💤"
        }
    }

    public var centerIcon: String {
        switch self {
        case .noseBoop:    return "💖"
        case .zoomieChase: return "⚡"
        case .jumpParty:   return "✨"
        case .snuggleNap:  return "💕"
        }
    }

    public var myDogAction: PetAction {
        switch self {
        case .noseBoop:    return .waving
        case .zoomieChase: return .runRight
        case .jumpParty:   return .jumping
        case .snuggleNap:  return .sleeping
        }
    }

    public var partnerDogAction: PetAction {
        switch self {
        case .noseBoop:    return .waving
        case .zoomieChase: return .runLeft
        case .jumpParty:   return .jumping
        case .snuggleNap:  return .sleeping
        }
    }

    public func descriptionText(myPetName: String, partnerPetName: String) -> String {
        switch self {
        case .noseBoop:
            return "\(myPetName) & \(partnerPetName) booped noses!"
        case .zoomieChase:
            return "\(myPetName) & \(partnerPetName) got the zoomies together!"
        case .jumpParty:
            return "\(myPetName) & \(partnerPetName) are doing a happy dance!"
        case .snuggleNap:
            return "\(myPetName) & \(partnerPetName) curled up together!"
        }
    }
}

/// Active rare two-dog event synchronized across both paired iPhones.
public struct RarePetInteraction: Codable, Hashable, Sendable {
    public var id: String
    public var kind: RareInteractionKind
    public var startedAt: TimeInterval
    public var expiresAt: TimeInterval

    public init(
        id: String = UUID().uuidString,
        kind: RareInteractionKind,
        startedAt: TimeInterval = Date().timeIntervalSince1970,
        duration: TimeInterval = 36
    ) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.expiresAt = startedAt + duration
    }

    public func isActive(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        now <= expiresAt
    }
}

/// All 10 sprite animations derived from the spritesheet grid.
public enum PetAction: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case idle
    case sleeping
    case waving
    case jumping
    case runRight
    case runLeft
    case waiting
    case working
    case review
    case dizzy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .idle:     return "Idle"
        case .sleeping: return "Sleeping"
        case .waving:   return "Waving"
        case .jumping:  return "Jumping"
        case .runRight: return "Trot Right"
        case .runLeft:  return "Trot Left"
        case .waiting:  return "Waiting"
        case .working:  return "Working"
        case .review:   return "Reading"
        case .dizzy:    return "Dizzy"
        }
    }

    public var shortLabel: String {
        switch self {
        case .idle:     return "Chill"
        case .sleeping: return "Sleep"
        case .waving:   return "Wave"
        case .jumping:  return "Jump"
        case .runRight: return "Right"
        case .runLeft:  return "Left"
        case .waiting:  return "Wait?"
        case .working:  return "Work"
        case .review:   return "Read"
        case .dizzy:    return "Dizzy"
        }
    }

    public var statusPhrase: String {
        switch self {
        case .idle:     return "is hanging out"
        case .sleeping: return "is fast asleep"
        case .waving:   return "is waving hi!"
        case .jumping:  return "is jumping for joy!"
        case .runRight: return "is trotting along"
        case .runLeft:  return "is zoomie-running"
        case .waiting:  return "is waiting for you"
        case .working:  return "is locked in working"
        case .review:   return "is inspecting closely"
        case .dizzy:    return "did a dramatic sploot"
        }
    }

    public var emoji: String {
        switch self {
        case .idle:     return "😊"
        case .sleeping: return "💤"
        case .waving:   return "👋"
        case .jumping:  return "🎉"
        case .runRight: return "🐾"
        case .runLeft:  return "🐾"
        case .waiting:  return "❓"
        case .working:  return "💻"
        case .review:   return "🔍"
        case .dizzy:    return "😵‍💫"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .idle:     return "face.smiling.fill"
        case .sleeping: return "moon.zzz.fill"
        case .waving:   return "hand.wave.fill"
        case .jumping:  return "sparkles"
        case .runRight: return "arrow.right.circle.fill"
        case .runLeft:  return "arrow.left.circle.fill"
        case .waiting:  return "questionmark.bubble.fill"
        case .working:  return "laptopcomputer"
        case .review:   return "magnifyingglass"
        case .dizzy:    return "tornado"
        }
    }

    /// Number of sliced frames in Assets.xcassets for this action (even counts: 4, 6, or 8).
    public var frameCount: Int {
        switch self {
        case .idle:     return 6
        case .sleeping: return 4
        case .waving:   return 4
        case .jumping:  return 6
        case .runRight: return 8
        case .runLeft:  return 8
        case .waiting:  return 6
        case .working:  return 6
        case .review:   return 6
        case .dizzy:    return 8
        }
    }

    /// Frame rate used for smooth in-app TimelineView previews.
    public var inAppFPS: Double {
        switch self {
        case .sleeping: return 2.2
        case .idle, .waiting, .review: return 6.0
        case .waving: return 6.0
        case .jumping, .working, .dizzy: return 7.0
        case .runRight, .runLeft: return 8.0
        }
    }

    public var accentColor: Color {
        switch self {
        case .idle:     return Color(red: 0.40, green: 0.84, blue: 0.62)
        case .sleeping: return Color(red: 0.58, green: 0.52, blue: 0.98)
        case .waving:   return Color(red: 0.99, green: 0.62, blue: 0.32)
        case .jumping:  return Color(red: 0.99, green: 0.44, blue: 0.62)
        case .runRight, .runLeft: return Color(red: 0.35, green: 0.78, blue: 0.98)
        case .waiting:  return Color(red: 0.98, green: 0.80, blue: 0.28)
        case .working:  return Color(red: 0.42, green: 0.68, blue: 0.98)
        case .review:   return Color(red: 0.68, green: 0.84, blue: 0.42)
        case .dizzy:    return Color(red: 0.96, green: 0.42, blue: 0.42)
        }
    }

    /// Quick-access actions displayed inside the Expanded Dynamic Island & Lock Screen banner.
    public static let quickIslandActions: [PetAction] = [
        .sleeping, .waving, .jumping, .working
    ]
}

/// Exposes the stamped IPA semantic version, CI build number, and short commit SHA inside the app UI.
public enum AppBuildInfo {
    public static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.1.0"
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
