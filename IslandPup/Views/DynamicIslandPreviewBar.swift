import SwiftUI

/// Interactive in-app Dynamic Island preview showing 1 dog when solo and BOTH dogs
/// when connected (including partner messages and rare spontaneous 2-dog interactions!).
struct DynamicIslandPreviewBar: View {
    enum IslandMode: String, CaseIterable {
        case compact = "Compact"
        case expanded = "Expanded"
        case minimal = "Minimal"
    }

    let state: PetActivityAttributes.ContentState
    let isLiveOnDeviceIsland: Bool

    @State private var mode: IslandMode = .expanded

    private var myPet: IslandPetSnapshot { state.displayMyPet }
    private var partnerPet: IslandPetSnapshot? { state.displayPartnerPet }
    private var interaction: RarePetInteraction? { state.activeInteraction }

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
                                (interaction != nil ? Color.pink : myPet.themeColor).opacity(0.22),
                                (partnerPet?.themeColor ?? myPet.action.accentColor).opacity(0.15),
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
            ZStack(alignment: .topTrailing) {
                AnimatedPetSpriteView(
                    pet: myPet,
                    size: 30,
                    driver: .liveTimeline
                )
                if let interaction {
                    Text(interaction.kind.centerIcon)
                        .font(.system(size: 10))
                        .offset(x: 4, y: -2)
                }
            }

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

            if let partner = partnerPet, state.hasTwoDogs {
                ZStack(alignment: .topLeading) {
                    AnimatedPetSpriteView(
                        pet: partner,
                        size: 30,
                        driver: .liveTimeline,
                        flipHorizontally: partner.action != .runLeft && partner.action != .runRight
                    )
                    if let interaction {
                        Text(interaction.kind.centerIcon)
                            .font(.system(size: 10))
                            .offset(x: -4, y: -2)
                    }
                }
            } else {
                Text(myPet.action.emoji)
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.black)
                .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 8)
                .overlay(
                    Capsule()
                        .strokeBorder((interaction != nil ? Color.pink : myPet.themeColor).opacity(0.5), lineWidth: 1)
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
                        Circle().strokeBorder(myPet.themeColor.opacity(0.5), lineWidth: 1)
                    )

                AnimatedPetSpriteView(
                    pet: myPet,
                    size: 28,
                    driver: .widgetStatic
                )
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var expandedCapsule: some View {
        if let partner = partnerPet, state.hasTwoDogs {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    VStack(spacing: 3) {
                        AnimatedPetSpriteView(
                            pet: myPet,
                            size: 56,
                            driver: .liveTimeline,
                            showSleepBadge: true
                        )
                        Text("\(myPet.name) \(myPet.action.emoji)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    VStack(spacing: 4) {
                        if let interaction {
                            Text("\(interaction.kind.badgeEmoji) \(interaction.kind.title)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.88))
                            Text(interaction.kind.descriptionText(myPetName: myPet.name, partnerPetName: partner.name))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        } else if let partnerMsg = state.partnerMessage, !partnerMsg.isEmpty {
                            Text("💬 \(partner.name)'s message")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(partner.themeColor)
                            Text("“\(partnerMsg)”")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        } else {
                            Text("Both Dogs Live 🐾")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("\(partner.name) \(partner.action.statusPhrase)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 4)

                    VStack(spacing: 3) {
                        AnimatedPetSpriteView(
                            pet: partner,
                            size: 56,
                            driver: .liveTimeline,
                            showSleepBadge: true,
                            flipHorizontally: partner.action != .runLeft && partner.action != .runRight
                        )
                        Text("\(partner.name) \(partner.action.emoji)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
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
                            .strokeBorder((interaction != nil ? Color.pink : myPet.themeColor).opacity(0.45), lineWidth: 1.2)
                    )
            )
        } else {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(myPet.themeColor.opacity(0.20))
                        .frame(width: 68, height: 68)

                    AnimatedPetSpriteView(
                        pet: myPet,
                        size: 62,
                        driver: .liveTimeline,
                        showSleepBadge: true
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(myPet.name) \(myPet.action.statusPhrase)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text("\(myPet.action.emoji) \(myPet.action.title)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(myPet.action.accentColor.opacity(0.32)))
                    }

                    if let myMsg = state.myMessage, !myMsg.isEmpty {
                        Text("“\(myMsg)”")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    } else {
                        Text("Connect two iPhones to bring both dogs onto the Dynamic Island!")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
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
                            .strokeBorder(myPet.themeColor.opacity(0.38), lineWidth: 1)
                    )
            )
        }
    }
}
