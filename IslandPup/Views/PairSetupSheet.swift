import SwiftUI
import UIKit

struct PairSetupSheet: View {
    @ObservedObject var syncService: PairSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var nameInput: String = ""
    @State private var joinCodeInput: String = ""
    @State private var relayInput: String = ""
    @State private var showAdvancedRelay: Bool = false
    @State private var copiedFeedback: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileSection
                    if syncService.pairCode.isEmpty {
                        createOrJoinSection
                    } else {
                        activeRoomSection
                    }
                    advancedRelaySection
                }
                .padding(20)
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.11).ignoresSafeArea())
            .navigationTitle("Phone Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitProfileFields()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                nameInput = syncService.myName
                joinCodeInput = syncService.pairCode
                relayInput = syncService.relayBaseURL
            }
        }
        .preferredColorScheme(.dark)
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR DISPLAY NAME")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))

            TextField("Your nickname (shown on partner's Island)", text: $nameInput)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .onSubmit {
                    commitProfileFields()
                }

            Text("Shown when you set the other phone's pet action (e.g. “Set by \(nameInput.isEmpty ? "Friend" : nameInput)”).")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var createOrJoinSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("START A NEW PAIR ROOM")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))

                Button {
                    commitProfileFields()
                    let generated = SharedStorage.generatePairCode()
                    joinCodeInput = generated
                    Task {
                        await syncService.joinPairRoom(code: generated)
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                        Text("Generate 6-Digit Pair Code")
                            .fontWeight(.bold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(15)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.48, blue: 0.32),
                                        Color(red: 0.88, green: 0.34, blue: 0.56)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
            }

            Divider().background(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 10) {
                Text("OR JOIN PARTNER'S CODE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))

                HStack(spacing: 10) {
                    TextField("Enter code (e.g. PAWS42)", text: $joinCodeInput)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.08))
                        )

                    Button {
                        commitProfileFields()
                        let cleaned = SharedStorage.normalizePairCode(joinCodeInput)
                        guard !cleaned.isEmpty else { return }
                        Task {
                            await syncService.joinPairRoom(code: cleaned)
                        }
                    } label: {
                        Text("Link")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .disabled(SharedStorage.normalizePairCode(joinCodeInput).isEmpty)
                }
            }
        }
    }

    private var activeRoomSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ACTIVE PAIR CODE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))

            VStack(spacing: 14) {
                Text(syncService.pairCode)
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                            )
                    )

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = syncService.pairCode
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        copiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            copiedFeedback = false
                        }
                    } label: {
                        Label(copiedFeedback ? "Copied!" : "Copy Code", systemImage: copiedFeedback ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.12))
                            )
                    }

                    ShareLink(
                        item: "Join my IslandPup Dynamic Island pet room! Enter pair code: \(syncService.pairCode)"
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.12))
                            )
                    }
                }
                .foregroundStyle(.white)

                Text("Enter this exact code on the second iPhone so you can control each other's Dynamic Island pet.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                Button(role: .destructive) {
                    Task {
                        await syncService.leavePairRoom()
                        joinCodeInput = ""
                    }
                } label: {
                    Label("Unpair This Phone", systemImage: "link.badge.plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .padding(.top, 4)
                }
            }
        }
    }

    private var advancedRelaySection: some View {
        DisclosureGroup("Advanced Relay Server", isExpanded: $showAdvancedRelay) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("https://ntfy.sh", text: $relayInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )

                Text("Uses encrypted SHA-256 room topics over HTTPS/SSE (`https://ntfy.sh` by default, zero signup needed, or point to your own self-hosted ntfy instance).")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 8)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.top, 8)
    }

    private func commitProfileFields() {
        syncService.myName = nameInput
        syncService.relayBaseURL = relayInput
        Task {
            await syncService.publishStatus()
        }
    }
}
