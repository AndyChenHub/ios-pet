import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct IslandPupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetActivityAttributes.self) { context in
            LockScreenPetBannerView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let myDisplayPet = state.displayMyPet
            let partnerDisplayPet = state.displayPartnerPet
            let interaction = state.activeInteraction

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(spacing: 3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.black)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(myDisplayPet.themeColor.opacity(0.6), lineWidth: 1.5)
                                )

                            AnimatedPetSpriteView(
                                pet: myDisplayPet,
                                size: 46,
                                driver: .widgetTimerGate(anchor: state.anchorDate),
                                showSleepBadge: true
                            )
                        }

                        Text("\(myDisplayPet.name) \(myDisplayPet.action.emoji)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let partner = partnerDisplayPet, state.hasTwoDogs {
                        VStack(spacing: 3) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.black)
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(partner.themeColor.opacity(0.6), lineWidth: 1.5)
                                    )

                                AnimatedPetSpriteView(
                                    pet: partner,
                                    size: 46,
                                    driver: .widgetTimerGate(anchor: state.anchorDate),
                                    showSleepBadge: true,
                                    flipHorizontally: shouldFlipRightDog(action: partner.action)
                                )
                            }

                            Text("\(partner.name) \(partner.action.emoji)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                        .padding(.trailing, 2)
                    } else {
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 4) {
                                Text(myDisplayPet.action.emoji)
                                    .font(.system(size: 13))
                                Text(myDisplayPet.action.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(myDisplayPet.action.accentColor.opacity(0.28))
                            )
                        }
                        .padding(.trailing, 2)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    expandedCenterView(state: state, myPet: myDisplayPet, partnerPet: partnerDisplayPet, interaction: interaction)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if interaction != nil,
                           let partnerMsg = state.partnerMessage,
                           !partnerMsg.isEmpty,
                           let partner = partnerDisplayPet {
                            HStack(spacing: 5) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(partner.themeColor)
                                Text("\(partner.name): “\(partnerMsg)”")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white.opacity(0.10))
                            )
                        }

                        HStack(spacing: 6) {
                            Text("SET \(state.myPet.name.uppercased())'S ACTION")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)

                            Spacer()

                            if state.isPaired {
                                Button(intent: SyncPartnerPetIntent()) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("Sync")
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(.white.opacity(0.82))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.white.opacity(0.13)))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 6) {
                            ForEach(PetAction.quickIslandActions) { item in
                                let isSelected = state.myPet.action == item
                                Button(intent: TriggerIslandPetActionIntent(action: item)) {
                                    HStack(spacing: 4) {
                                        Text(item.emoji)
                                            .font(.system(size: 12))
                                        Text(item.shortLabel)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
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
                    .padding(.top, 2)
                }
            } compactLeading: {
                ZStack(alignment: .topTrailing) {
                    AnimatedPetSpriteView(
                        pet: myDisplayPet,
                        size: 24,
                        driver: .widgetTimerGate(anchor: state.anchorDate)
                    )
                    if let interaction {
                        Text(interaction.kind.centerIcon)
                            .font(.system(size: 8))
                            .offset(x: 3, y: -2)
                    }
                }
            } compactTrailing: {
                if let partner = partnerDisplayPet, state.hasTwoDogs {
                    ZStack(alignment: .topLeading) {
                        AnimatedPetSpriteView(
                            pet: partner,
                            size: 24,
                            driver: .widgetTimerGate(anchor: state.anchorDate),
                            flipHorizontally: shouldFlipRightDog(action: partner.action)
                        )
                        if let interaction {
                            Text(interaction.kind.centerIcon)
                                .font(.system(size: 8))
                                .offset(x: -3, y: -2)
                        }
                    }
                } else {
                    Text(myDisplayPet.action.emoji)
                        .font(.system(size: 14))
                        .padding(.horizontal, 2)
                }
            } minimal: {
                AnimatedPetSpriteView(
                    pet: myDisplayPet,
                    size: 22,
                    driver: .widgetStatic
                )
            }
            .keylineTint(interaction != nil ? Color.pink : myDisplayPet.themeColor)
        }
    }

    @ViewBuilder
    private func expandedCenterView(
        state: PetActivityAttributes.ContentState,
        myPet: IslandPetSnapshot,
        partnerPet: IslandPetSnapshot?,
        interaction: RarePetInteraction?
    ) -> some View {
        if let interaction, let partnerPet {
            VStack(spacing: 2) {
                Text("\(interaction.kind.badgeEmoji) \(interaction.kind.title)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.88))
                    .lineLimit(1)

                Text(interaction.kind.descriptionText(myPetName: myPet.name, partnerPetName: partnerPet.name))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        } else if let partnerPet, state.hasTwoDogs {
            VStack(spacing: 3) {
                if let partnerMsg = state.partnerMessage, !partnerMsg.isEmpty {
                    Text("💬 \(partnerPet.name)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(partnerPet.themeColor)
                        .lineLimit(1)

                    Text("“\(partnerMsg)”")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("\(myPet.name) & \(partnerPet.name)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(partnerPet.name) \(partnerPet.action.statusPhrase)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(myPet.name) \(myPet.action.statusPhrase)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let myMsg = state.myMessage, !myMsg.isEmpty {
                    Text("“\(myMsg)”")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                } else {
                    Text("Solo mode • Pair to show both dogs")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func shouldFlipRightDog(action: PetAction) -> Bool {
    switch action {
    case .runLeft, .runRight:
        return false
    default:
        return true
    }
}

private struct LockScreenPetBannerView: View {
    let state: PetActivityAttributes.ContentState

    var body: some View {
        let myPet = state.displayMyPet
        let partnerPet = state.displayPartnerPet
        let interaction = state.activeInteraction

        VStack(alignment: .leading, spacing: 10) {
            if let partner = partnerPet, state.hasTwoDogs {
                twoDogsStageHeader(myPet: myPet, partnerPet: partner, interaction: interaction)

                if let partnerMessage = state.partnerMessage, !partnerMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(partner.themeColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(partnerMessageSenderLabel(partnerPet: partner))
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(partner.themeColor)
                            Text("“\(partnerMessage)”")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(partner.themeColor.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(partner.themeColor.opacity(0.45), lineWidth: 1)
                            )
                    )
                }
            } else {
                soloStageHeader(myPet: myPet)
            }

            HStack(spacing: 6) {
                ForEach(PetAction.quickIslandActions) { item in
                    let isSelected = state.myPet.action == item
                    Button(intent: TriggerIslandPetActionIntent(action: item)) {
                        HStack(spacing: 4) {
                            Text(item.emoji)
                                .font(.system(size: 12))
                            Text(item.shortLabel)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? item.accentColor.opacity(0.42) : Color.white.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }

                if state.isPaired {
                    Button(intent: SyncPartnerPetIntent()) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.16))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }

    private func partnerMessageSenderLabel(partnerPet: IslandPetSnapshot) -> String {
        if let owner = state.partnerOwnerName, !owner.isEmpty {
            return "\(partnerPet.name) (\(owner))'S MESSAGE"
        }
        return "\(partnerPet.name.uppercased())'S MESSAGE"
    }

    @ViewBuilder
    private func twoDogsStageHeader(
        myPet: IslandPetSnapshot,
        partnerPet: IslandPetSnapshot,
        interaction: RarePetInteraction?
    ) -> some View {
        if let interaction {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    AnimatedPetSpriteView(
                        pet: myPet,
                        size: 50,
                        driver: .widgetTimerGate(anchor: state.anchorDate)
                    )
                    Text(interaction.kind.centerIcon)
                        .font(.system(size: 16))
                    AnimatedPetSpriteView(
                        pet: partnerPet,
                        size: 50,
                        driver: .widgetTimerGate(anchor: state.anchorDate),
                        flipHorizontally: true
                    )
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.pink.opacity(0.65), lineWidth: 1.5)
                        )
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("✨ RARE INTERACTION")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.86))
                    Text(interaction.kind.descriptionText(myPetName: myPet.name, partnerPetName: partnerPet.name))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 10) {
                dogPill(pet: myPet, flip: false, roleTag: "MY PET")
                Spacer(minLength: 4)
                dogPill(
                    pet: partnerPet,
                    flip: shouldFlipRightDog(action: partnerPet.action),
                    roleTag: state.partnerOwnerName.map { "\($0.uppercased())'S PET" } ?? "PARTNER"
                )
            }
        }
    }

    @ViewBuilder
    private func dogPill(pet: IslandPetSnapshot, flip: Bool, roleTag: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black)
                    .frame(width: 54, height: 54)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(pet.themeColor.opacity(0.55), lineWidth: 1.5)
                    )

                AnimatedPetSpriteView(
                    pet: pet,
                    size: 48,
                    driver: .widgetTimerGate(anchor: state.anchorDate),
                    showSleepBadge: true,
                    flipHorizontally: flip
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(roleTag)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Text(pet.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(pet.action.emoji) \(pet.action.title)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(pet.themeColor)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func soloStageHeader(myPet: IslandPetSnapshot) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black)
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(myPet.themeColor.opacity(0.5), lineWidth: 1.5)
                    )

                AnimatedPetSpriteView(
                    pet: myPet,
                    size: 54,
                    driver: .widgetTimerGate(anchor: state.anchorDate),
                    showSleepBadge: true
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
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
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                } else {
                    Text("Pair with another iPhone to bring both dogs onto the Dynamic Island!")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            }
        }
    }
}
