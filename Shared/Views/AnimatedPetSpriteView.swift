import CoreText
import Foundation
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
        /// Lightweight static single-frame render for Minimal bubble and idle cards.
        case widgetStatic
        /// Adaptive TimelineView loop for active in-app stages and previews.
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

    private let frames: [ResolvedFrame]
    private let restingFrame: ResolvedFrame

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase

    public init(
        pet: IslandPetSnapshot,
        size: CGFloat,
        driver: PlaybackDriver,
        showSleepBadge: Bool = false,
        flipHorizontally: Bool = false
    ) {
        if case .widgetTimerGate = driver {
            _ = PetFontRegistrar.registerOnce
        }
        self.pet = pet
        self.size = size
        self.driver = driver
        self.showSleepBadge = showSleepBadge
        self.flipHorizontally = flipHorizontally

        let resolved = Self.resolveFrames(for: pet, driver: driver)
        self.frames = resolved
        if pet.action == .sleeping, resolved.count > 2 {
            self.restingFrame = resolved[2]
        } else {
            self.restingFrame = resolved.first ?? .asset(PetCharacter.alfie.previewAssetName(), crispPixel: false)
        }
    }

    public init(
        profile: PetProfile,
        action: PetAction,
        size: CGFloat,
        driver: PlaybackDriver,
        showSleepBadge: Bool = false,
        flipHorizontally: Bool = false
    ) {
        let snapshot: IslandPetSnapshot
        if case .widgetTimerGate = driver {
            snapshot = CustomPetStore.shared.makeSnapshot(for: profile, action: action)
        } else {
            snapshot = IslandPetSnapshot(
                id: profile.id,
                name: profile.name,
                builtInCharacter: profile.builtInCharacter,
                customSheetID: profile.customSheetID,
                colorPreset: profile.colorPreset,
                action: action,
                customMicroFrames: nil
            )
        }
        self.init(
            pet: snapshot,
            size: size,
            driver: driver,
            showSleepBadge: showSleepBadge,
            flipHorizontally: flipHorizontally
        )
    }

    private static func resolveFrames(for pet: IslandPetSnapshot, driver: PlaybackDriver) -> [ResolvedFrame] {
        // 1. Built-in high-res bundled character
        if let builtIn = pet.builtInCharacter {
            let names = builtIn.frameAssetNames(for: pet.action)
            if case .widgetStatic = driver {
                if pet.action == .sleeping, names.count > 2 {
                    return names.map { .asset($0, crispPixel: false) }
                }
                if let first = names.first {
                    return [.asset(first, crispPixel: false)]
                }
            }
            return names.map { .asset($0, crispPixel: false) }
        }

        // 2. Local full-res custom spritesheet frames when animating inside the main app
        if case .liveTimeline = driver, let sheetID = pet.customSheetID {
            let localImages = CustomPetStore.shared.inAppFrames(for: sheetID, action: pet.action)
            if !localImages.isEmpty {
                return localImages.map { .uiImage($0, crispPixel: false) }
            }
        }

        // 3. Decoded compressed micro-frames (Dynamic Island / WidgetExtension / connected custom pet)
        if let blobs = pet.customMicroFrames, !blobs.isEmpty {
            let decoded = blobs.compactMap { MicroSpriteCodec.decodeUIImage(from: $0) }
            if !decoded.isEmpty {
                return decoded.map { .uiImage($0, crispPixel: true) }
            }
        }

        // 4. Static custom pet cards inside the main app (when micro-frames were omitted)
        if let sheetID = pet.customSheetID {
            let localImages = CustomPetStore.shared.inAppFrames(for: sheetID, action: pet.action)
            if !localImages.isEmpty {
                return localImages.map { .uiImage($0, crispPixel: false) }
            }
        }

        // 5. Safe guaranteed fallback so Dynamic Island is never empty
        return PetCharacter.alfie.frameAssetNames(for: pet.action).map { .asset($0, crispPixel: false) }
    }

    /// Downsamples widget sprite sequences so Compact Dynamic Island, sleeping pets, and Low Power Mode
    /// use a single 1 Hz whole-second timer mask (zero sub-second GPU wakeups), and Expanded / Lock Screen
    /// views cap at 4 frames (at most 3 masks instead of 7).
    private func sampledWidgetFrames(from source: [ResolvedFrame]) -> [ResolvedFrame] {
        let preferTwoFrameOneHertz = (size <= 30)
            || (pet.action == .sleeping)
            || ProcessInfo.processInfo.isLowPowerModeEnabled

        if preferTwoFrameOneHertz || source.count < 4 {
            let mid = source.count / 2
            return [source[0], source[mid]]
        }

        switch source.count {
        case 4, 5:
            return [source[0], source[1], source[2], source[3]]
        case 6, 7:
            return [source[0], source[1], source[3], source[4]]
        default:
            return [source[0], source[2], source[4], source[6]]
        }
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch driver {
                case .widgetStatic:
                    renderFrame(restingFrame)

                case .widgetTimerGate(let anchor):
                    if isLuminanceReduced || frames.count < 2 {
                        renderFrame(restingFrame)
                    } else {
                        widgetTwoStackLoop(frames: sampledWidgetFrames(from: frames), anchor: anchor)
                    }

                case .liveTimeline:
                    if isLuminanceReduced || scenePhase != .active || frames.count < 2 {
                        renderFrame(restingFrame)
                    } else {
                        let effectiveFPS = ProcessInfo.processInfo.isLowPowerModeEnabled
                            ? min(pet.action.inAppFPS, 3.0)
                            : pet.action.inAppFPS
                        TimelineView(.periodic(from: .now, by: 1.0 / max(effectiveFPS, 1.0))) { context in
                            let rawTick = Int(floor(context.date.timeIntervalSinceReferenceDate * effectiveFPS))
                            let idx = ((rawTick % frames.count) + frames.count) % frames.count
                            renderFrame(frames[idx])
                        }
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
