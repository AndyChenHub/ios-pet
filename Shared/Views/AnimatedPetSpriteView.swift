import CoreText
import SwiftUI
import UIKit

private enum PetFontRegistrar {
    static let registerOnce: Void = {
        if let url = Bundle.main.url(forResource: "PetTimerGate-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

/// Drives frame-by-frame animation for built-in pets (Alfie & Teddy) and user-imported custom
/// spritesheet pets across both the Dynamic Island (2-stack Painter's Algorithm) and in-app views.
public struct AnimatedPetSpriteView: View {
    public enum PlaybackDriver: Sendable {
        /// Zero-CPU WidgetKit / Dynamic Island continuous loop with guaranteed visible base frame.
        case widgetTimerGate(anchor: Date)
        /// Lightweight static single-frame render for the tiny Dynamic Island Minimal bubble.
        case widgetStatic
        /// High-FPS TimelineView loop for interactive in-app stages and previews.
        case liveTimeline
    }

    private enum ResolvedFrame {
        case asset(String, crispPixel: Bool)
        case uiImage(UIImage, crispPixel: Bool)
    }

    public let pet: IslandPetSnapshot
    public let size: CGFloat
    public let driver: PlaybackDriver
    public var showSleepBadge: Bool
    public var flipHorizontally: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(
        pet: IslandPetSnapshot,
        size: CGFloat,
        driver: PlaybackDriver,
        showSleepBadge: Bool = false,
        flipHorizontally: Bool = false
    ) {
        _ = PetFontRegistrar.registerOnce
        self.pet = pet
        self.size = size
        self.driver = driver
        self.showSleepBadge = showSleepBadge
        self.flipHorizontally = flipHorizontally
    }

    public init(
        profile: PetProfile,
        action: PetAction,
        size: CGFloat,
        driver: PlaybackDriver,
        showSleepBadge: Bool = false,
        flipHorizontally: Bool = false
    ) {
        self.init(
            pet: CustomPetStore.shared.makeSnapshot(for: profile, action: action),
            size: size,
            driver: driver,
            showSleepBadge: showSleepBadge,
            flipHorizontally: flipHorizontally
        )
    }

    private var resolvedFrames: [ResolvedFrame] {
        // 1. Built-in high-res bundled character
        if let builtIn = pet.builtInCharacter {
            return builtIn.frameAssetNames(for: pet.action).map { .asset($0, crispPixel: false) }
        }

        // 2. Local full-res custom spritesheet frames when running inside the main app
        if case .liveTimeline = driver, let sheetID = pet.customSheetID {
            let localImages = CustomPetStore.shared.inAppFrames(for: sheetID, action: pet.action)
            if !localImages.isEmpty {
                return localImages.map { .uiImage($0, crispPixel: false) }
            }
        }

        // 3. Decoded compressed micro-frames (Dynamic Island / WidgetExtension / Partner's custom pet)
        if let blobs = pet.customMicroFrames, !blobs.isEmpty {
            let decoded = blobs.compactMap { MicroSpriteCodec.decodeUIImage(from: $0) }
            if !decoded.isEmpty {
                return decoded.map { .uiImage($0, crispPixel: true) }
            }
        }

        // 4. Safe guaranteed fallback so Dynamic Island is never empty
        return PetCharacter.alfie.frameAssetNames(for: pet.action).map { .asset($0, crispPixel: false) }
    }

    private var restingFrame: ResolvedFrame {
        let list = resolvedFrames
        if pet.action == .sleeping, list.count > 2 {
            return list[2]
        }
        return list.first ?? .asset(PetCharacter.alfie.previewAssetName(), crispPixel: false)
    }

    public var body: some View {
        let list = resolvedFrames
        ZStack(alignment: .topTrailing) {
            Group {
                switch driver {
                case .widgetStatic:
                    renderFrame(restingFrame)

                case .widgetTimerGate(let anchor):
                    if isLuminanceReduced || list.count < 2 {
                        renderFrame(restingFrame)
                    } else {
                        widgetTwoStackLoop(frames: list, anchor: anchor)
                    }

                case .liveTimeline:
                    TimelineView(.periodic(from: .now, by: 1.0 / max(pet.action.inAppFPS, 1.0))) { context in
                        let rawTick = Int(floor(context.date.timeIntervalSinceReferenceDate * pet.action.inAppFPS))
                        let idx = ((rawTick % list.count) + list.count) % list.count
                        renderFrame(list[idx])
                    }
                }
            }
            .scaleEffect(x: flipHorizontally ? -1 : 1, y: 1)

            if showSleepBadge && pet.action == .sleeping && size >= 42 {
                Text("zZz")
                    .font(.system(size: max(9, size * 0.17), weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.76, green: 0.72, blue: 1.0))
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    .offset(x: size * 0.04, y: -size * 0.02)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func widgetTwoStackLoop(frames: [ResolvedFrame], anchor: Date) -> some View {
        let evenCount = frames.count - (frames.count % 2)
        let count = max(2, evenCount)
        let half = max(1, count / 2)
        let frameDuration = 2.0 / Double(count)

        ZStack {
            // Stack 1: Frame 0 sits completely UNMASKED at the bottom so the dog is ALWAYS visible!
            ZStack {
                opaqueBlackBackedFrame(frames[0])

                if half > 1 {
                    ForEach(1..<half, id: \.self) { i in
                        opaqueBlackBackedFrame(frames[i])
                            .mask(
                                TimerBlinkMask(
                                    anchorDate: anchor,
                                    deltaSeconds: Double(i) * frameDuration,
                                    size: size
                                )
                            )
                    }
                }
            }

            // Stack 2: Second half of loop, revealed during [1.0s, 2.0s)
            if count > half {
                ZStack {
                    opaqueBlackBackedFrame(frames[half])

                    if count > half + 1 {
                        ForEach((half + 1)..<count, id: \.self) { i in
                            opaqueBlackBackedFrame(frames[i])
                                .mask(
                                    TimerBlinkMask(
                                        anchorDate: anchor,
                                        deltaSeconds: Double(i) * frameDuration,
                                        size: size
                                    )
                                )
                        }
                    }
                }
                .mask(
                    TimerBlinkMask(
                        anchorDate: anchor,
                        deltaSeconds: 1.0,
                        size: size
                    )
                )
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    @ViewBuilder
    private func opaqueBlackBackedFrame(_ frame: ResolvedFrame) -> some View {
        ZStack {
            Color.black
            renderFrame(frame)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func renderFrame(_ frame: ResolvedFrame) -> some View {
        switch frame {
        case .asset(let name, let crispPixel):
            Image(name)
                .renderingMode(.original)
                .interpolation(crispPixel ? .none : .high)
                .resizable()
                .antialiased(!crispPixel)
                .scaledToFit()
                .frame(width: size, height: size)

        case .uiImage(let uiImg, let crispPixel):
            Image(uiImage: uiImg)
                .renderingMode(.original)
                .interpolation(crispPixel ? .none : .high)
                .resizable()
                .antialiased(!crispPixel)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

private struct TimerBlinkMask: View {
    let anchorDate: Date
    let deltaSeconds: TimeInterval
    let size: CGFloat

    var body: some View {
        Text(anchorDate.addingTimeInterval(deltaSeconds), style: .timer)
            .font(.custom("PetTimerGate-Regular", fixedSize: size))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(width: size * 9, height: size, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .offset(x: -size * 4)
            .frame(width: size, height: size)
            .clipped()
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.layoutDirection, .leftToRight)
    }
}
