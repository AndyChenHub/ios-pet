import SwiftUI
import UIKit

struct ContentView: View {
    enum ControlTarget: String, CaseIterable {
        case partner = "Partner's Phone"
        case mine = "My Phone"
    }

    @ObservedObject var syncService: PairSyncService
    @ObservedObject var islandController: LiveActivityController

    @State private var controlTarget: ControlTarget = .partner
    @State private var noteText: String = ""
    @State private var showPairSheet: Bool = false

    private let quickNoteChips: [(String, PetAction)] = [
        ("Time for sleep! 🌙", .sleeping),
        ("Thinking of u 👋", .waving),
        ("Yay!! 🎉", .jumping),
        ("Deep focus 💻", .working),
        ("Where are u? ❓", .waiting)
    ]

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(red: 0.05, green: 0.06, blue: 0.10)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        DynamicIslandPreviewBar(
                            character: syncService.myCharacter,
                            action: syncService.myAction,
                            senderName: syncService.lastSenderName,
                            note: syncService.lastNote,
                            isLiveOnDeviceIsland: islandController.isRunningOnIsland
                        )

                        islandLaunchCard
                        petPickerSection
                        pairingStatusCard
                        actionDeckSection
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
            .onAppear {
                controlTarget = syncService.pairCode.isEmpty ? .mine : .partner
                islandController.refreshActiveStatus()
            }
            .onChange(of: syncService.pairCode) { _, newCode in
                if !newCode.isEmpty {
                    controlTarget = .partner
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

    // MARK: - Start / Stop Dynamic Island Card

    private var islandLaunchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(islandController.isRunningOnIsland
                         ? "\(syncService.myCharacter.displayName) is on your Dynamic Island"
                         : "Send \(syncService.myCharacter.displayName) to Dynamic Island")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Swipe home or lock your iPhone to see \(syncService.myCharacter.displayName) animate on the Island.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
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

    // MARK: - 1 Active Pet Selector (Alfie vs Teddy)

    private var petPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MY ISLAND PET (1 ACTIVE)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("Tap to switch")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 12) {
                ForEach(PetCharacter.allCases) { pet in
                    let isSelected = syncService.myCharacter == pet
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task {
                            await syncService.selectCharacter(pet)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(pet.themeColor.opacity(isSelected ? 0.26 : 0.10))
                                    .frame(width: 78, height: 78)

                                AnimatedPetSpriteView(
                                    character: pet,
                                    action: isSelected ? syncService.myAction : .idle,
                                    size: 72,
                                    driver: .liveTimeline
                                )
                            }

                            VStack(spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(pet.displayName)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(pet.themeColor)
                                    }
                                }
                                Text(pet.breedSubtitle)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(isSelected ? pet.themeColor.opacity(0.14) : Color.white.opacity(0.05))
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
                }
            }
        }
    }

    // MARK: - Phone-to-Phone Pairing Card

    private var pairingStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusDotColor.opacity(0.18))
                        .frame(width: 44, height: 44)

                    if let partnerPet = syncService.partnerCharacter {
                        AnimatedPetSpriteView(
                            character: partnerPet,
                            action: syncService.partnerAction ?? .idle,
                            size: 40,
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
            return "Connect with Another iPhone"
        case .connecting:
            return "Connecting Room \(syncService.pairCode)…"
        case .listening:
            return "Room \(syncService.pairCode) Ready"
        case .partnerLinked(let name):
            if let pet = syncService.partnerCharacter {
                return "Linked with \(name)'s \(pet.displayName)"
            }
            return "Linked with \(name)"
        case .error(let msg):
            return msg
        }
    }

    private var pairingSubheadline: String {
        switch syncService.connectionStatus {
        case .unpaired:
            return "Link two phones so you can set each other's pet to sleeping, waving, working & more."
        case .connecting, .listening:
            return "Enter code \(syncService.pairCode) on the second phone to control each other's Island."
        case .partnerLinked:
            if let act = syncService.partnerAction, let pet = syncService.partnerCharacter {
                return "\(pet.displayName) on their Island \(act.statusPhrase) \(act.emoji)"
            }
            return "Tap any action below to update their Dynamic Island!"
        case .error:
            return "Tap Manage to verify network or pair code."
        }
    }

    // MARK: - Remote & Local Action Deck

    private var actionDeckSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SET PET ACTION")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Picker("Target", selection: $controlTarget) {
                    ForEach(ControlTarget.allCases, id: \.self) { target in
                        Text(target.rawValue).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if controlTarget == .partner && syncService.pairCode.isEmpty {
                Button {
                    showPairSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 16, weight: .bold))
                        Text("Pair with another iPhone first to control their pet — or switch to “My Phone” to test!")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.orange.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.orange.opacity(0.45), lineWidth: 1)
                            )
                    )
                }
            }

            // Optional note + 1-tap mood chips
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))

                    TextField(
                        controlTarget == .partner
                            ? "Optional note for partner's Island (e.g. Goodnight! 🌙)"
                            : "Optional status note on your Island",
                        text: $noteText
                    )
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)

                    if !noteText.isEmpty {
                        Button {
                            noteText = ""
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
                        ForEach(quickNoteChips, id: \.0) { phrase, suggestedAction in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                noteText = phrase
                                triggerAction(suggestedAction)
                            } label: {
                                Text(phrase)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(.white.opacity(0.10))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            let previewCharacter: PetCharacter = (controlTarget == .partner)
                ? (syncService.partnerCharacter ?? (syncService.myCharacter == .alfie ? .teddy : .alfie))
                : syncService.myCharacter

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(PetAction.allCases) { item in
                    let isActive = (controlTarget == .partner)
                        ? (syncService.partnerAction == item)
                        : (syncService.myAction == item)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        triggerAction(item)
                    } label: {
                        HStack(spacing: 10) {
                            AnimatedPetSpriteView(
                                character: previewCharacter,
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
                                Text(controlTarget == .partner ? "Send to Partner" : "Set My Pet")
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

    private func triggerAction(_ action: PetAction) {
        let currentNote = noteText
        Task {
            if controlTarget == .partner {
                if syncService.pairCode.isEmpty {
                    showPairSheet = true
                } else {
                    await syncService.sendActionToPartner(action, note: currentNote)
                }
            } else {
                await syncService.setMyOwnAction(action, note: currentNote)
                if !islandController.isRunningOnIsland {
                    let state = SharedStorage.shared.currentContentState()
                    await islandController.startIsland(with: state)
                }
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
