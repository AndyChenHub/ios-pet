import SwiftUI
import UIKit

/// Interactive in-app Dynamic Island preview showing 1 dog when solo and BOTH dogs
/// when connected (including messages, solo quirks, and synced Rare / Super Rare / Ultra Rare scenes).
struct DynamicIslandPreviewBar: View {
    enum IslandMode: String, CaseIterable, Identifiable {
        case compact = "Compact"
        case expanded = "Expanded"
        case minimal = "Minimal"

        var id: String { rawValue }
    }

    let state: PetActivityAttributes.ContentState
    let isLiveOnDeviceIsland: Bool
    var onSelectAction: ((PetAction) -> Void)? = nil
    var onSyncPartner: (() -> Void)? = nil

    @State private var mode: IslandMode = .expanded

    private var myPet: IslandPetSnapshot { state.displayMyPet }
    private var partnerPet: IslandPetSnapshot? { state.displayPartnerPet }
    private var interaction: RarePetInteraction? { state.activeInteraction }

    private var interactionAccentColor: Color {
        guard let interaction else { return myPet.themeColor }
        return interaction.kind.rarity.accentColor
    }

    private var interactionBadgeTextColor: Color {
        guard let interaction else {
            return Color(red: 1.0, green: 0.76, blue: 0.88)
        }
        return interaction.kind.rarity.badgeTextColor
    }

    private func shouldFlipPartner(_ action: PetAction) -> Bool {
        action != .confused && action != .sideEye
    }

    private func selectMode(_ newMode: IslandMode) {
        guard mode != newMode else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
            mode = newMode
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isLiveOnDeviceIsland ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(isLiveOnDeviceIsland ? "LIVE ON ISLAND" : "ISLAND PREVIEW")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                modeSwitcher
            }

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                interactionAccentColor.opacity(0.22),
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
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectMode(.expanded)
                            }
                    case .minimal:
                        minimalCapsule
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectMode(.expanded)
                            }
                    case .expanded:
                        expandedCapsule
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 14)
            }
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(IslandMode.allCases) { item in
                let isSelected = (mode == item)
                Button {
                    selectMode(item)
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.10))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
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
            .padding(.leading, 1)

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
                        flipHorizontally: shouldFlipPartner(partner.action)
                    )
                    if let interaction {
                        Text(interaction.kind.centerIcon)
                            .font(.system(size: 10))
                            .offset(x: -4, y: -2)
                    }
                }
                .padding(.trailing, 4)
            } else {
                Text(myPet.action.emoji)
                    .font(.system(size: 16))
                    .padding(.trailing, 2)
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
                        .strokeBorder(interactionAccentColor.opacity(0.5), lineWidth: 1)
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
        VStack(spacing: 10) {
            Group {
                if let partner = partnerPet, state.hasTwoDogs {
                    expandedTwoDogsHeader(partner: partner)
                } else {
                    expandedSoloHeader
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectMode(.compact)
            }

            if onSelectAction != nil {
                expandedQuickActionsSection
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
                        .strokeBorder(interactionAccentColor.opacity(0.45), lineWidth: 1.2)
                )
        )
    }

    @ViewBuilder
    private func expandedTwoDogsHeader(partner: IslandPetSnapshot) -> some View {
        VStack(spacing: 10) {
            if let interaction, state.canRenderCombinedDuoArtwork {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(myPet.themeColor)
                            .frame(width: 6, height: 6)
                        Text(myPet.name)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.10)))

                    Spacer(minLength: 4)

                    Text(interaction.effectiveTriggerBadge)
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(interactionBadgeTextColor)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Text(partner.name)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Circle()
                            .fill(partner.themeColor)
                            .frame(width: 6, height: 6)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.10)))
                }

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 108, height: 78)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(interactionAccentColor.opacity(0.62), lineWidth: 1.2)
                            )

                        AnimatedDuoSpriteView(
                            kind: interaction.kind,
                            height: 72,
                            driver: .liveTimeline,
                            startedAt: interaction.startedAt
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(interaction.kind.badgeEmoji) \(interaction.kind.title)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(interaction.kind.descriptionText(myPetName: myPet.name, partnerPetName: partner.name))
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(3)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 8) {
                    VStack(spacing: 3) {
                        AnimatedPetSpriteView(
                            pet: myPet,
                            size: 54,
                            driver: .liveTimeline,
                            showSleepBadge: true
                        )
                        Text("\(myPet.name) \(myPet.action.emoji)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(width: 64)
                    .padding(.leading, 2)

                    VStack(spacing: 4) {
                        if let interaction {
                            Text(interaction.effectiveTriggerBadge)
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(interactionBadgeTextColor)
                                .lineLimit(1)
                            Text("\(interaction.kind.badgeEmoji) \(interaction.kind.title)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(interaction.kind.descriptionText(myPetName: myPet.name, partnerPetName: partner.name))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        } else if let partnerMsg = state.activePartnerMessage, !partnerMsg.isEmpty {
                            Text("💬 \(partner.name)'s message")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(partner.themeColor)
                            Text("“\(partnerMsg)”")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        } else {
                            Text("\(myPet.name) & \(partner.name) 🐾")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(partner.name) \(partner.action.statusPhrase)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 3) {
                        AnimatedPetSpriteView(
                            pet: partner,
                            size: 54,
                            driver: .liveTimeline,
                            showSleepBadge: true,
                            flipHorizontally: shouldFlipPartner(partner.action)
                        )
                        Text("\(partner.name) \(partner.action.emoji)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(width: 64)
                    .padding(.trailing, 4)
                }
            }
        }
    }

    private var expandedSoloHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(myPet.themeColor.opacity(0.20))
                    .frame(width: 66, height: 66)

                AnimatedPetSpriteView(
                    pet: myPet,
                    size: 60,
                    driver: .liveTimeline,
                    showSleepBadge: true
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                if let quirk = state.activeSoloQuirk {
                    Text(quirk.triggerBadge)
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(myPet.action.accentColor)
                        .lineLimit(1)
                }

                HStack {
                    Text("\(myPet.name) \(myPet.action.statusPhrase)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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

                if let myMsg = state.activeMyMessage, !myMsg.isEmpty {
                    Text("“\(myMsg)”")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                } else {
                    Text("Connect two iPhones to bring both dogs onto the Dynamic Island!")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                }
            }
        }
    }

    private var expandedQuickActionsSection: some View {
        VStack(spacing: 6) {
            Divider()
                .overlay(Color.white.opacity(0.10))

            HStack(spacing: 6) {
                Text("SET \(state.myPet.name.uppercased())'S STATUS")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)

                Spacer()

                if state.isPaired, let onSyncPartner {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSyncPartner()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9, weight: .bold))
                            Text("Sync")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 5) {
                ForEach(PetAction.quickIslandActions) { item in
                    let isSelected = state.myPet.action == item
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onSelectAction?(item)
                    } label: {
                        HStack(spacing: 3) {
                            Text(item.emoji)
                                .font(.system(size: 11))
                            Text(item.shortLabel)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? item.accentColor.opacity(0.45) : Color.white.opacity(0.13))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
