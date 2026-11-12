import Foundation
import SwiftUI

/// Represents the single active pet character displayed on the Dynamic Island.
public enum PetCharacter: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case alfie
    case teddy

    public var id: String { rawValue }

    public var displayName: String {
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

    public var tagline: String {
        switch self {
        case .alfie: return "Playful brown & white terrier with a bright red collar"
        case .teddy: return "Fluffy charcoal schnauzer with soulful puppy eyes"
        }
    }

    public var themeColor: Color {
        switch self {
        case .alfie:
            return Color(red: 0.96, green: 0.49, blue: 0.29)
        case .teddy:
            return Color(red: 0.56, green: 0.65, blue: 0.96)
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

/// All 10 sprite animations derived from the Alfie & Teddy spritesheets.
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

    /// Number of sliced frames in Assets.xcassets for this action.
    public var frameCount: Int {
        switch self {
        case .idle:     return 6
        case .sleeping: return 4
        case .waving:   return 4
        case .jumping:  return 5
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
