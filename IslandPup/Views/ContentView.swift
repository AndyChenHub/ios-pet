import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var syncService: PairSyncService
    @ObservedObject var islandController: LiveActivityController

    @State private var messageInput: String = ""
    @State private var showPairSheet: Bool = false
    @State private var petSheetMode: AddPetSheet.Mode?
    @State private var didAutoLaunchIsland: Bool = false

    private let quickMoodChips: [(String, PetAction)] = [
        ("Goodnight! 🌙", .sleeping),
        ("Thinking of u 👋", .waving),
        ("Yay!! 🎉", .jumping),
        ("Deep focus 💻", .working),
        ("Waiting for u 💕", .waiting)
    ]

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var liveSnapshotState: PetActivityAttributes.ContentState {
        SharedStorage.shared.currentContentState()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(red: 0.05, green: 0.06, blue: 0.10)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        DynamicIslandPreviewBar(
                            state: liveSnapshotState,
                            isLiveOnDeviceIsland: islandController.isRunningOnIsland
                        )

                        if let rare = syncService.activeRareInteraction,
                           let partnerPet = syncService.partnerPet {
                            rareInteractionCard(rare: rare, partnerPet: partnerPet)
                        }

                        islandLaunchCard
                        myPetRosterSection
                        partnerStatusAndMessageCard
                        myPetActionDeckSection
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
                messageInput = syncService.myMessage ?? ""
                islandController.refreshActiveStatus()
                if !didAutoLaunchIsland {
                    didAutoLaunchIsland = true
                    if !islandController.isRunningOnIsland {
                        let state = SharedStorage.shared.currentContentState()
                        Task {
                            await islandController.startIsland(with: state)
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

    // MARK: - Rare Two-Dog Interaction Banner

    private func rareInteractionCard(rare: RarePetInteraction, partnerPet: IslandPetSnapshot) -> some View {
        HStack(spacing: 12) {
            Text(rare.kind.badgeEmoji)
                .font(.system(size: 26))

            VStack(alignment: .leading, spacing: 3) {
                Text("✨ RARE INTERACTION HAPPENING NOW!")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Color(red: 1.0, green: 0.75, blue: 0.88))

                Text(rare.kind.descriptionText(myPetName: syncService.myPetProfile.name, partnerPetName: partnerPet.name))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.pink.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.pink.opacity(0.6), lineWidth: 1.5)
                )
        )
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

    // MARK: - Select Pet, Rename Pet, or Add Spritesheet

    private var myPetRosterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MY PET (SELECT, RENAME OR IMPORT)")
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(syncService.roster) { pet in
                        let isSelected = syncService.myPetProfile.id == pet.id
                        Button {
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
                                        driver: .liveTimeline
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
                            .frame(width: 128)
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

                    // Add New Spritesheet Pet Card
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
            }
        }
    }

    // MARK: - Partner Connection & Incoming Partner Message Card

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
                        Text("\(partnerPet.name.uppercased())'S MESSAGE")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
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
            return "Connect with Partner's iPhone"
        case .connecting:
            return "Connecting Room \(syncService.pairCode)…"
        case .listening:
            return "Room \(syncService.pairCode) Ready"
        case .partnerLinked(let petName):
            if let owner = syncService.partnerOwnerName, !owner.isEmpty {
                return "\(petName) (\(owner)) is Here!"
            }
            return "\(petName) is Connected!"
        case .error(let msg):
            return msg
        }
    }

    private var pairingSubheadline: String {
        switch syncService.connectionStatus {
        case .unpaired:
            return "When connected, both dogs live together on the Dynamic Island & occasionally play together!"
        case .connecting, .listening:
            return "Enter code \(syncService.pairCode) on your partner's iPhone so both dogs appear on the Island."
        case .partnerLinked(let petName):
            if let act = syncService.partnerPet?.action {
                return "\(petName) \(act.statusPhrase) \(act.emoji) alongside \(syncService.myPetProfile.name)"
            }
            return "Both dogs are sharing the Dynamic Island!"
        case .error:
            return "Tap Manage to verify network or pair code."
        }
    }

    // MARK: - My Pet's Action & Message Deck (Changes My Phone + Partner's Phone)

    private var myPetActionDeckSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SET \(syncService.myPetProfile.name.uppercased())'S ACTION & MESSAGE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.55))

                Text(syncService.pairCode.isEmpty
                     ? "Updates \(syncService.myPetProfile.name) on your Dynamic Island."
                     : "Updates \(syncService.myPetProfile.name) on BOTH your Dynamic Island and your partner's phone & notification!")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Message input + 1-tap mood chips
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))

                    TextField(
                        syncService.pairCode.isEmpty
                            ? "Status note for \(syncService.myPetProfile.name)…"
                            : "Message for your partner's notification…",
                        text: $messageInput
                    )
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)
                    .onSubmit {
                        triggerMyAction(syncService.myAction)
                    }

                    if !messageInput.isEmpty {
                        Button {
                            messageInput = ""
                            Task {
                                await syncService.clearMyMessage()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.07))
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickMoodChips, id: \.0) { phrase, suggestedAction in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                messageInput = phrase
                                triggerMyAction(suggestedAction)
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

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(PetAction.allCases) { item in
                    let isActive = syncService.myAction == item

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        triggerMyAction(item)
                    } label: {
                        HStack(spacing: 10) {
                            AnimatedPetSpriteView(
                                profile: syncService.myPetProfile,
                                action: item,
                                size: 48,
                                driver: .liveTimeline
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(item.emoji)
                                        .font(.system(size: 13))
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                                Text(syncService.pairCode.isEmpty ? "Update My Island" : "Sync Both Phones")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.52))
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(isActive ? item.accentColor.opacity(0.22) : Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(
                                            isActive ? item.accentColor.opacity(0.85) : Color.white.opacity(0.09),
                                            lineWidth: isActive ? 1.8 : 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func triggerMyAction(_ action: PetAction) {
        let noteToSend = messageInput
        Task {
            await syncService.setMyPetAction(action, message: noteToSend)
            if !islandController.isRunningOnIsland {
                let state = SharedStorage.shared.currentContentState()
                await islandController.startIsland(with: state)
            }
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
