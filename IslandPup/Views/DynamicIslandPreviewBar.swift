import SwiftUI

/// Interactive in-app Dynamic Island mockup so users can preview Compact, Minimal,
/// and Expanded Dynamic Island modes right inside the app (and tap to switch!).
struct DynamicIslandPreviewBar: View {
    enum IslandMode: String, CaseIterable {
        case compact = "Compact"
        case expanded = "Expanded"
        case minimal = "Minimal"
    }

    let character: PetCharacter
    let action: PetAction
    let senderName: String?
    let note: String?
    let isLiveOnDeviceIsland: Bool

    @State private var mode: IslandMode = .expanded

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isLiveOnDeviceIsland ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(isLiveOnDeviceIsland ? "LIVE ON DYNAMIC ISLAND" : "ISLAND PREVIEW (TAP PILL)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                Picker("Island Mode", selection: $mode.animation(.spring(response: 0.36, dampingFraction: 0.78))) {
                    ForEach(IslandMode.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                character.themeColor.opacity(0.22),
                                action.accentColor.opacity(0.14),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    )

                Group {
                    switch mode {
                    case .compact:
                        compactCapsule
                    case .minimal:
                        minimalCapsule
                    case .expanded:
                        expandedCapsule
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 14)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                    switch mode {
                    case .expanded: mode = .compact
                    case .compact: mode = .minimal
                    case .minimal: mode = .expanded
                    }
                }
            }
        }
    }

    private var compactCapsule: some View {
        HStack(spacing: 14) {
            AnimatedPetSpriteView(
                character: character,
                action: action,
                size: 30,
                driver: .liveTimeline
            )

            // Simulated TrueDepth camera pill area
            Capsule()
                .fill(Color(red: 0.09, green: 0.10, blue: 0.15))
                .frame(width: 78, height: 18)
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.24, blue: 0.45))
                        .frame(width: 9, height: 9)
                        .padding(.trailing, 5)
                }

            Text(action.emoji)
                .font(.system(size: 16))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.black)
                .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 8)
                .overlay(
                    Capsule()
                        .strokeBorder(character.themeColor.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private var minimalCapsule: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(.black)
                .frame(width: 112, height: 36)
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.24, blue: 0.45))
                        .frame(width: 10, height: 10)
                        .padding(.trailing, 12)
                }

            ZStack {
                Circle()
                    .fill(.black)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle().strokeBorder(character.themeColor.opacity(0.5), lineWidth: 1)
                    )

                AnimatedPetSpriteView(
                    character: character,
                    action: action,
                    size: 28,
                    driver: .liveTimeline
                )
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
    }

    private var expandedCapsule: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(action.accentColor.opacity(0.20))
                    .frame(width: 74, height: 74)

                AnimatedPetSpriteView(
                    character: character,
                    action: action,
                    size: 70,
                    driver: .liveTimeline,
                    showSleepBadge: true
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(character.displayName) \(action.statusPhrase)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Text("\(action.emoji) \(action.title)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(action.accentColor.opacity(0.32)))
                }

                if let senderName, let note, !note.isEmpty {
                    Text("\(senderName): “\(note)”")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                } else if let senderName {
                    Text("Set by \(senderName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                } else if let note, !note.isEmpty {
                    Text("“\(note)”")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                } else {
                    Text(character.breedSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.black)
                .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(character.themeColor.opacity(0.38), lineWidth: 1)
                )
        )
    }
}
