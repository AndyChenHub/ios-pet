import SwiftUI
import UIKit

struct ContentView: View {
    enum ActionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case emotions = "😄 Emotions"
        case tasks = "💼 Tasks"

        var id: String { rawValue }
    }

    @ObservedObject var syncService: PairSyncService
    @ObservedObject var islandController: LiveActivityController

    @State private var selectedFilter: ActionFilter = .all
    @State private var messageInput: String = ""
    @State private var showPairSheet: Bool = false
    @State private var petSheetMode: AddPetSheet.Mode?
    @State private var didAutoLaunchIsland: Bool = false

    private let quickMoodChips: [(String, PetAction)] = [
        ("Love u! 🥰", .love),
        ("Snack time 🍖", .eating),
        ("Locked in 💻", .working),
        ("On a walk 🦮", .walk),
        ("Need a hug 😢", .sad),
        ("Goodnight! 🌙", .sleeping)
    ]

    private let actionGridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var liveSnapshotState: PetActivityAttributes.ContentState {
        syncService.inAppPreviewState
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(red: 0.05, green: 0.06, blue: 0.10)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        DynamicIslandPreviewBar(
                            state: liveSnapshotState,
                            isLiveOnDeviceIsland: islandController.isRunningOnIsland,
                            onSelectAction: { action in
                                triggerMyAction(action)
                            },
                            onSyncPartner: {
                                Task {
                                    await syncService.pollLatestMessages()
                                    await syncService.pushStateToActiveLiveActivities()
                                }
                            }
                        )

                        specialMomentBanner

                        emotionsAndTasksCard

                        islandLaunchCard

                        partnerStatusAndMessageCard

                        messageComposerCard

                        myPetRosterSection

                        Text(AppBuildInfo.displayLabel)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.36))
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                }

                if let toast = syncService.toastMessage {
                    toastBanner(text: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 14)
                }
            }
            .navigationTitle("IslandPup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if FeatureFlags.enableCustomPetCreation {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            petSheetMode = .createNew
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("New Pet")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPairSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: syncService.pairCode.isEmpty ? "iphone.radiowaves.left.and.right" : "checkmark.icloud.fill")
                            Text(syncService.pairCode.isEmpty ? "Pair" : syncService.pairCode)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.12)))
                    }
                }
            }
            .sheet(isPresented: $showPairSheet) {
                PairSetupSheet(syncService: syncService)
            }
            .sheet(item: $petSheetMode) { sheetMode in
                AddPetSheet(mode: sheetMode, syncService: syncService)
            }
            .onAppear {
                islandController.refreshActiveStatus()
                if !didAutoLaunchIsland {
                    didAutoLaunchIsland = true
                    if !islandController.isRunningOnIsland {
                        let state = SharedStorage.shared.currentContentState()
                        Task {
                            await islandController.startIsland(with: state)
                        }
                    } else {
                        Task {
                            await syncService.pushStateToActiveLiveActivities()
                        }
                    }
                }
            }
            .onChange(of: syncService.toastMessage) { _, newValue in
                guard newValue != nil else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    if syncService.toastMessage == newValue {
                        withAnimation {
                            syncService.toastMessage = nil
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Special Moment Banner (Combined Duo Scene or Solo Quirk)

    @ViewBuilder
    private var specialMomentBanner: some View {
        if let rare = syncService.activeRareInteraction,
           let partnerPet = syncService.partnerPet,
           rare.isActive() {
            rareInteractionCard(rare: rare, partnerPet: partnerPet)
        } else if let quirk = syncService.activeSoloQuirk,
                  quirk.isActive() {
            soloQuirkCard(quirk: quirk)
        }
    }

    private func rareInteractionCard(rare: RarePetInteraction, partnerPet: IslandPetSnapshot) -> some View {
        let useCombinedArt = (syncService.myPetProfile.builtInCharacter != nil) && (partnerPet.builtInCharacter != nil)
        let rarity = rare.kind.rarity
        let accentColor = rarity.accentColor
        let badgeTextColor = rarity.badgeTextColor
        let isElevatedTier = rarity >= .superRare

        return HStack(spacing: 12) {
            if useCombinedArt {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 96, height: 68)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(accentColor.opacity(isElevatedTier ? 0.65 : 0.35), lineWidth: 1.2)
                        )

                    AnimatedDuoSpriteView(
                        kind: rare.kind,
                        height: 62,
                        driver: .liveTimeline,
                        startedAt: rare.startedAt
                    )
                }
            } else {
                Text(rare.kind.badgeEmoji)
                    .font(.system(size: 28))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(rare.effectiveTriggerBadge)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(badgeTextColor)

                Text("\(rare.kind.badgeEmoji) \(rare.kind.title)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(rare.kind.descriptionText(myPetName: syncService.myPetProfile.name, partnerPetName: partnerPet.name))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accentColor.opacity(rarity == .ultraRare ? 0.22 : 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(accentColor.opacity(isElevatedTier ? 0.72 : 0.58), lineWidth: 1.5)
                )
        )
    }

    private func soloQuirkCard(quirk: SoloPetQuirk) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 58, height: 58)

                AnimatedPetSpriteView(
                    profile: syncService.myPetProfile,
                    action: quirk.action,
                    size: 52,
                    driver: .liveTimeline
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(quirk.triggerBadge)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(quirk.action.accentColor)

                Text("\(syncService.myPetProfile.name) \(quirk.action.statusPhrase) \(quirk.action.emoji)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text("Resumes \(syncService.myAction.title) \(syncService.myAction.emoji) automatically")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(quirk.action.accentColor.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(quirk.action.accentColor.opacity(0.52), lineWidth: 1.4)
                )
        )
    }

    // MARK: - Effortless Emotions & Tasks Switcher Card

    private var emotionsAndTasksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(syncService.myPetProfile.name.uppercased())'S EMOTIONS & TASKS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.62))

                Text(syncService.pairCode.isEmpty
                     ? "Tap to switch \(syncService.myPetProfile.name)'s status on the Dynamic Island"
                     : "Silent Island sync • Never sends push notifications")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            }

            // Category Filter Pills
            HStack(spacing: 8) {
                ForEach(ActionFilter.allCases) { filter in
                    let selected = selectedFilter == filter
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.86))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selected ? Color.white : Color.white.opacity(0.09))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            switch selectedFilter {
            case .all:
                VStack(alignment: .leading, spacing: 8) {
                    categorySubheader(title: "😄 EMOTIONS")
                    actionTileGrid(actions: PetAction.emotionActions)
                }

                VStack(alignment: .leading, spacing: 8) {
                    categorySubheader(title: "💼 TASKS")
                    actionTileGrid(actions: PetAction.taskActions)
                }

            case .emotions:
                actionTileGrid(actions: PetAction.emotionActions)

            case .tasks:
                actionTileGrid(actions: PetAction.taskActions)
            }
        }
        .padding(15)
        .background(cardBackground)
    }

    private func categorySubheader(title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.48))
            .padding(.leading, 2)
    }

    private func actionTileGrid(actions: [PetAction]) -> some View {
        LazyVGrid(columns: actionGridColumns, spacing: 10) {
            ForEach(actions) { item in
                actionGridTile(for: item)
            }
        }
    }

    private func actionGridTile(for item: PetAction) -> some View {
        let isActive = syncService.myAction == item
        let isTwinMatch = !syncService.pairCode.isEmpty && (syncService.partnerPet?.action == item)

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            triggerMyAction(item)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AnimatedPetSpriteView(
                        profile: syncService.myPetProfile,
                        action: item,
                        size: 46,
                        driver: isActive ? .liveTimeline : .widgetStatic
                    )

                    if isTwinMatch {
                        Text("⚡")
                            .font(.system(size: 10))
                            .padding(3)
                            .background(Circle().fill(Color.pink.opacity(0.85)))
                            .offset(x: 8, y: -4)
                    }
                }

                HStack(spacing: 3) {
                    Text(item.emoji)
                        .font(.system(size: 11.5))
                    Text(item.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? item.accentColor.opacity(0.24) : Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isActive
                                    ? item.accentColor.opacity(0.90)
                                    : (isTwinMatch ? Color.pink.opacity(0.48) : Color.white.opacity(0.09)),
                                lineWidth: isActive ? 1.8 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Start / Stop Dynamic Island Card

    private var islandLaunchCard: some View {
        let islandTitle: String = {
            if let partnerPet = syncService.partnerPet, !syncService.pairCode.isEmpty {
                return islandController.isRunningOnIsland
                    ? "\(syncService.myPetProfile.name) & \(partnerPet.name) are on your Dynamic Island"
                    : "Send \(syncService.myPetProfile.name) & \(partnerPet.name) to Dynamic Island"
            }
            return islandController.isRunningOnIsland
                ? "\(syncService.myPetProfile.name) is on your Dynamic Island"
                : "Send \(syncService.myPetProfile.name) to Dynamic Island"
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(islandTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(islandController.isRunningOnIsland
                         ? "Swipe up to the Home Screen to see your Island pets (iOS hides an app's Live Activity while the app itself is open)."
                         : "Tap Start, then swipe up to the Home Screen or lock your iPhone to see your pet on the Island.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let state = SharedStorage.shared.currentContentState()
                    Task {
                        await islandController.toggleIsland(with: state)
                    }
                } label: {
                    Text(islandController.isRunningOnIsland ? "Stop" : "Start")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(islandController.isRunningOnIsland ? .white : .black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(islandController.isRunningOnIsland
                                      ? Color.red.opacity(0.85)
                                      : Color.white)
                        )
                }
            }

            if let err = islandController.statusError {
                Text(err)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Connected Pet Status & Incoming Message Card

    private var partnerStatusAndMessageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusDotColor.opacity(0.18))
                        .frame(width: 48, height: 48)

                    if let partnerPet = syncService.partnerPet {
                        AnimatedPetSpriteView(
                            pet: partnerPet,
                            size: 42,
                            driver: .liveTimeline
                        )
                    } else {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(statusDotColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 7, height: 7)
                        Text(pairingHeadline)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Text(pairingSubheadline)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                Button {
                    showPairSheet = true
                } label: {
                    Text(syncService.pairCode.isEmpty ? "Connect" : "Manage")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.13))
                        )
                }
            }

            if let partnerPet = syncService.partnerPet,
               let partnerMsg = syncService.partnerMessage,
               !partnerMsg.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "message.badge.filled.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(partnerPet.themeColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(partnerPet.name)'s message")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(partnerPet.themeColor)
                        Text("“\(partnerMsg)”")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(partnerPet.themeColor.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(partnerPet.themeColor.opacity(0.42), lineWidth: 1)
                        )
                )
            }
        }
        .padding(15)
        .background(cardBackground)
    }

    private var statusDotColor: Color {
        switch syncService.connectionStatus {
        case .unpaired: return .gray
        case .connecting: return .yellow
        case .listening: return .cyan
        case .partnerLinked: return .green
        case .error: return .red
        }
    }

    private var pairingHeadline: String {
        switch syncService.connectionStatus {
        case .unpaired:
            return "Connect Two iPhones"
        case .connecting:
            return "Connecting Room \(syncService.pairCode)…"
        case .listening:
            return "Room \(syncService.pairCode) Ready"
        case .partnerLinked(let petName):
            return "\(petName) is Connected!"
        case .error(let msg):
            return msg
        }
    }

    private var pairingSubheadline: String {
        switch syncService.connectionStatus {
        case .unpaired:
            return "When connected, both dogs live together on the Dynamic Island & unlock special duo scenes!"
        case .connecting, .listening:
            return "Enter code \(syncService.pairCode) on the second iPhone so both pets appear on the Island."
        case .partnerLinked(let petName):
            if let act = syncService.partnerPet?.action {
                return "\(petName) \(act.statusPhrase) \(act.emoji) alongside \(syncService.myPetProfile.name)"
            }
            return "\(syncService.myPetProfile.name) & \(petName) are sharing the Dynamic Island!"
        case .error:
            return "Tap Manage to verify network or pair code."
        }
    }

    // MARK: - Message Composer Card (Only Place That Pushes Notifications)

    private var messageSectionHeader: String {
        if syncService.pairCode.isEmpty {
            return "\(syncService.myPetProfile.name.uppercased())'S MESSAGE"
        }
        if let connectedPet = syncService.partnerPet {
            return "SEND \(syncService.myPetProfile.name.uppercased())'S MESSAGE TO \(connectedPet.name.uppercased())"
        }
        return "SEND \(syncService.myPetProfile.name.uppercased())'S MESSAGE (PUSHES NOTIFICATION)"
    }

    private var messagePlaceholder: String {
        if syncService.pairCode.isEmpty {
            return "Write a note for \(syncService.myPetProfile.name)…"
        }
        if let connectedPet = syncService.partnerPet {
            return "Message from \(syncService.myPetProfile.name) to \(connectedPet.name)…"
        }
        return "Send a message from \(syncService.myPetProfile.name)…"
    }

    private var messageComposerCard: some View {
        let canSendMessage = !messageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(messageSectionHeader)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.58))

                Spacer()

                if !syncService.pairCode.isEmpty {
                    Text("🔔 Pushes Notification")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                TextField(messagePlaceholder, text: $messageInput)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)
                    .submitLabel(.send)
                    .onSubmit {
                        sendComposedMessage()
                    }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    sendComposedMessage()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Send")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(canSendMessage ? Color.black : Color.white.opacity(0.45))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(canSendMessage ? Color.white : Color.white.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.07))
            )

            if let activeMsg = syncService.myMessage, !activeMsg.isEmpty {
                HStack(spacing: 6) {
                    Text("Showing on Island: “\(activeMsg)”")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        Task {
                            await syncService.clearMyMessage()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Clear")
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickMoodChips, id: \.0) { phrase, suggestedAction in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            sendQuickMessageChip(phrase: phrase, action: suggestedAction)
                        } label: {
                            Text(phrase)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(.white.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(15)
        .background(cardBackground)
    }

    // MARK: - Select & Customize Pet Roster

    private var myPetRosterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(
                    FeatureFlags.enableCustomPetCreation
                        ? "\(syncService.myPetProfile.name.uppercased()) • SELECT OR IMPORT PET"
                        : "\(syncService.myPetProfile.name.uppercased()) • CHOOSE PET"
                )
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Button {
                    petSheetMode = .editExisting(syncService.myPetProfile)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Rename \(syncService.myPetProfile.name)")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(syncService.myPetProfile.themeColor)
                }
            }

            if FeatureFlags.enableCustomPetCreation {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(syncService.roster) { pet in
                            petRosterCard(for: pet, expandWidth: false)
                        }

                        addCustomSpritesheetCard
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(syncService.roster) { pet in
                        petRosterCard(for: pet, expandWidth: true)
                    }
                }
            }
        }
    }

    private func petRosterCard(for pet: PetProfile, expandWidth: Bool) -> some View {
        let isSelected = syncService.myPetProfile.id == pet.id

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await syncService.selectPet(pet)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(pet.themeColor.opacity(isSelected ? 0.26 : 0.10))
                        .frame(width: 74, height: 74)

                    AnimatedPetSpriteView(
                        profile: pet,
                        action: isSelected ? syncService.myAction : .idle,
                        size: 68,
                        driver: isSelected ? .liveTimeline : .widgetStatic
                    )
                }

                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(pet.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(pet.themeColor)
                        }
                    }
                    Text(pet.isCustom ? "Custom Sheet" : pet.subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(width: expandWidth ? nil : 128)
            .frame(maxWidth: expandWidth ? .infinity : nil)
            .padding(.vertical, 13)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? pet.themeColor.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                isSelected ? pet.themeColor.opacity(0.85) : Color.white.opacity(0.09),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                petSheetMode = .editExisting(pet)
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.88), Color.black.opacity(0.55))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var addCustomSpritesheetCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            petSheetMode = .createNew
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 74, height: 74)
                        .overlay(
                            Circle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(.white.opacity(0.35))
                        )

                    Image(systemName: "plus.viewfinder")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }

                VStack(spacing: 2) {
                    Text("Add Sheet")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Create New Pet")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 124)
            .padding(.vertical, 13)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func sendComposedMessage() {
        let text = messageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageInput = ""
        Task {
            await syncService.sendMyMessage(text)
            await ensureIslandStarted()
        }
    }

    private func sendQuickMessageChip(phrase: String, action: PetAction) {
        messageInput = ""
        Task {
            await syncService.sendMyMessage(phrase, optionalAction: action)
            await ensureIslandStarted()
        }
    }

    private func triggerMyAction(_ action: PetAction) {
        Task {
            await syncService.setMyPetAction(action)
            await ensureIslandStarted()
        }
    }

    private func ensureIslandStarted() async {
        if !islandController.isRunningOnIsland {
            let state = SharedStorage.shared.currentContentState()
            await islandController.startIsland(with: state)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func toastBanner(text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color(red: 0.16, green: 0.18, blue: 0.26).opacity(0.96))
                    .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 4)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            )
    }
}
