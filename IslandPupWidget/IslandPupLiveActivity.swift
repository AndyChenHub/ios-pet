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
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.black)
                            .frame(width: 60, height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(context.state.action.accentColor.opacity(0.45), lineWidth: 1.5)
                            )

                        AnimatedPetSpriteView(
                            character: context.state.character,
                            action: context.state.action,
                            size: 54,
                            driver: .widgetTimerGate(anchor: context.state.anchorDate),
                            showSleepBadge: true
                        )
                    }
                    .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 4) {
                            Text(context.state.action.emoji)
                                .font(.system(size: 13))
                            Text(context.state.action.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(context.state.action.accentColor.opacity(0.28))
                        )

                        if context.state.isPaired {
                            Button(intent: SyncPartnerPetIntent()) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Sync")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                }
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.white.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 2)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(context.state.character.displayName) \(context.state.action.statusPhrase)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(subtitleText(for: context.state))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Text(context.state.isPaired ? "SEND TO PARTNER" : "MY PET ACTION")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(.white.opacity(0.5))

                            Spacer()

                            if let partnerPet = context.state.partnerCharacter {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 5, height: 5)
                                    Text("\(partnerPet.displayName) \(context.state.partnerAction?.emoji ?? "🐾")")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                            }
                        }

                        HStack(spacing: 6) {
                            ForEach(PetAction.quickIslandActions) { item in
                                let isSelected = !context.state.isPaired && context.state.action == item
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
                                            .fill(isSelected ? item.accentColor.opacity(0.45) : .white.opacity(0.13))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                AnimatedPetSpriteView(
                    character: context.state.character,
                    action: context.state.action,
                    size: 24,
                    driver: .widgetTimerGate(anchor: context.state.anchorDate)
                )
            } compactTrailing: {
                Text(context.state.action.emoji)
                    .font(.system(size: 14))
                    .padding(.horizontal, 2)
            } minimal: {
                AnimatedPetSpriteView(
                    character: context.state.character,
                    action: context.state.action,
                    size: 22,
                    driver: .widgetStatic
                )
            }
            .keylineTint(context.state.character.themeColor)
        }
    }

    private func subtitleText(for state: PetActivityAttributes.ContentState) -> String {
        if let sender = state.senderName, let note = state.note, !note.isEmpty {
            return "\(sender): “\(note)”"
        } else if let sender = state.senderName {
            return "Set by \(sender)"
        } else if let note = state.note, !note.isEmpty {
            return "“\(note)”"
        } else {
            return state.character.breedSubtitle
        }
    }
}

private struct LockScreenPetBannerView: View {
    let state: PetActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.black)
                        .frame(width: 68, height: 68)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(state.action.accentColor.opacity(0.45), lineWidth: 1.5)
                        )

                    AnimatedPetSpriteView(
                        character: state.character,
                        action: state.action,
                        size: 60,
                        driver: .widgetTimerGate(anchor: state.anchorDate),
                        showSleepBadge: true
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(state.character.displayName) \(state.action.statusPhrase)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text("\(state.action.emoji) \(state.action.title)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(state.action.accentColor.opacity(0.32))
                            )
                    }

                    if let sender = state.senderName {
                        if let note = state.note, !note.isEmpty {
                            Text("From \(sender): “\(note)”")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        } else {
                            Text("Action set by \(sender)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    } else if let note = state.note, !note.isEmpty {
                        Text("“\(note)”")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    } else {
                        Text(state.character.breedSubtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    if state.isPaired {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            if let pPet = state.partnerCharacter {
                                Text("Paired with \(pPet.displayName) \(state.partnerAction?.emoji ?? "🐾")")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.68))
                            } else {
                                Text("Paired — tap below to change partner's pet")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(PetAction.quickIslandActions) { item in
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
                                .fill(.white.opacity(0.12))
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
}
