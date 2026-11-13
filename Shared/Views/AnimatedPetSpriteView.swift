import CoreText
import Foundation
import ImageIO
import SwiftUI
import UIKit

private enum PetFontRegistrar {
    static let registerOnce: Void = {
        for fontFile in ["PetTimerGate-Regular", "PetTimerGate6s-Regular"] {
            if let url = Bundle.main.url(forResource: fontFile, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
}

private final class DecodedSkitSequence: NSObject {
    let frames: [UIImage]
    let cumulativeEnds: [TimeInterval]
    let totalDuration: TimeInterval

    init(frames: [UIImage], cumulativeEnds: [TimeInterval], totalDuration: TimeInterval) {
        self.frames = frames
        self.cumulativeEnds = cumulativeEnds
        self.totalDuration = max(0.085, totalDuration)
    }

    func frame(at referenceTime: TimeInterval) -> UIImage {
        let wrapped = referenceTime.truncatingRemainder(dividingBy: totalDuration)
        let local = wrapped >= 0 ? wrapped : (wrapped + totalDuration)

        var low = 0
        var high = cumulativeEnds.count - 1
        while low < high {
            let mid = (low + high) / 2
            if local < cumulativeEnds[mid] {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return frames[min(max(0, low), frames.count - 1)]
    }
}

private final class LongSkitPlaybackCache: @unchecked Sendable {
    static let shared = LongSkitPlaybackCache()

    private let cache: NSCache<NSString, DecodedSkitSequence> = {
        let c = NSCache<NSString, DecodedSkitSequence>()
        c.countLimit = 2
        return c
    }()
    private let lock = NSLock()

    func skit(named datasetName: String) -> DecodedSkitSequence? {
        let key = datasetName as NSString
        lock.lock()
        if let hit = cache.object(forKey: key) {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let asset = NSDataAsset(name: datasetName),
              let source = CGImageSourceCreateWithData(asset.data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        guard count >= 2 else { return nil }

        var images: [UIImage] = []
        var ends: [TimeInterval] = []
        images.reserveCapacity(count)
        ends.reserveCapacity(count)

        var acc: TimeInterval = 0
        for index in 0..<count {
            guard let cgImg = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let delay = Self.frameDelay(from: source, at: index)
            acc += delay
            images.append(UIImage(cgImage: cgImg))
            ends.append(acc)
        }

        guard !images.isEmpty else { return nil }
        let sequence = DecodedSkitSequence(frames: images, cumulativeEnds: ends, totalDuration: acc)
        lock.lock()
        cache.setObject(sequence, forKey: key)
        lock.unlock()
        return sequence
    }

    private static func frameDelay(from source: CGImageSource, at index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.085
        }
        if let webpDict = props[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let unclamped = webpDict[kCGImagePropertyWebPUnclampedDelayTime] as? Double, unclamped >= 0.02 {
                return unclamped
            }
            if let clamped = webpDict[kCGImagePropertyWebPDelayTime] as? Double, clamped >= 0.02 {
                return clamped
            }
        }
        if let gifDict = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped >= 0.02 {
                return unclamped
            }
            if let clamped = gifDict[kCGImagePropertyGIFDelayTime] as? Double, clamped >= 0.02 {
                return clamped
            }
        }
        return 0.085
    }
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

/// Renders combined two-dog interaction scenes (`duo_<key>_0..3`) and long story skits
/// across Dynamic Island / Lock Screen (2s or 6s Painter's Algorithm) and in-app (`TimelineView`).
public struct AnimatedDuoSpriteView: View {
    public let kind: RareInteractionKind
    public let width: CGFloat
    public let height: CGFloat
    public let driver: AnimatedPetSpriteView.PlaybackDriver
    public let startedAt: TimeInterval?

    private let frameNames: [String]

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase

    public init(
        kind: RareInteractionKind,
        height: CGFloat,
        driver: AnimatedPetSpriteView.PlaybackDriver,
        startedAt: TimeInterval? = nil
    ) {
        if case .widgetTimerGate = driver {
            _ = PetFontRegistrar.registerOnce
        }
        self.kind = kind
        self.height = height
        self.width = (height * (200.0 / 144.0)).rounded()
        self.driver = driver
        self.startedAt = startedAt
        self.frameNames = kind.frameAssetNames
    }

    public var body: some View {
        Group {
            switch driver {
            case .widgetStatic:
                renderDuoFrame(frameNames[0])

            case .widgetTimerGate(let anchor):
                if isLuminanceReduced || frameNames.count < 2 {
                    renderDuoFrame(frameNames[0])
                } else {
                    let sampled = ProcessInfo.processInfo.isLowPowerModeEnabled
                        ? [frameNames[0], frameNames[frameNames.count / 2]]
                        : frameNames
                    let cycle: Double = kind.isLongSkit ? 6.0 : 2.0
                    let fontName = kind.isLongSkit ? "PetTimerGate6s-Regular" : "PetTimerGate-Regular"
                    duoWidgetTwoStackLoop(
                        frames: sampled,
                        anchor: anchor,
                        cycleSeconds: cycle,
                        fontName: fontName
                    )
                }

            case .liveTimeline:
                if isLuminanceReduced || scenePhase != .active || frameNames.count < 2 {
                    renderDuoFrame(frameNames[0])
                } else if let datasetName = kind.longSkitDatasetName,
                          let decodedSkit = LongSkitPlaybackCache.shared.skit(named: datasetName) {
                    let tickInterval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 0.25 : 0.085
                    TimelineView(.periodic(from: .now, by: tickInterval)) { context in
                        let refTime = startedAt.map { max(0, context.date.timeIntervalSince1970 - $0) }
                            ?? context.date.timeIntervalSinceReferenceDate
                        let img = decodedSkit.frame(at: refTime)
                        Image(uiImage: img)
                            .renderingMode(.original)
                            .interpolation(.high)
                            .resizable()
                            .antialiased(true)
                            .scaledToFit()
                            .frame(width: width, height: height)
                    }
                } else {
                    let effectiveFPS = ProcessInfo.processInfo.isLowPowerModeEnabled
                        ? min(kind.inAppFPS, 3.0)
                        : kind.inAppFPS
                    TimelineView(.periodic(from: .now, by: 1.0 / max(effectiveFPS, 1.0))) { context in
                        let refTime = startedAt.map { max(0, context.date.timeIntervalSince1970 - $0) }
                            ?? context.date.timeIntervalSinceReferenceDate
                        let rawTick = Int(floor(refTime * effectiveFPS))
                        let idx = ((rawTick % frameNames.count) + frameNames.count) % frameNames.count
                        renderDuoFrame(frameNames[idx])
                    }
                }
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func duoWidgetTwoStackLoop(
        frames: [String],
        anchor: Date,
        cycleSeconds: Double,
        fontName: String
    ) -> some View {
        let count = max(2, frames.count - (frames.count % 2))
        let half = max(1, count / 2)
        let frameDuration = cycleSeconds / Double(count)
        let halfCycle = cycleSeconds / 2.0

        ZStack {
            ZStack {
                opaqueDuoFrame(frames[0])

                if half > 1 {
                    ForEach(1..<half, id: \.self) { i in
                        opaqueDuoFrame(frames[i])
                            .mask(
                                TimerBlinkMask(
                                    anchorDate: anchor,
                                    deltaSeconds: Double(i) * frameDuration,
                                    width: width,
                                    height: height,
                                    fontName: fontName
                                )
                            )
                    }
                }
            }

            if count > half {
                ZStack {
                    opaqueDuoFrame(frames[half])

                    if count > half + 1 {
                        ForEach((half + 1)..<count, id: \.self) { i in
                            opaqueDuoFrame(frames[i])
                                .mask(
                                    TimerBlinkMask(
                                        anchorDate: anchor,
                                        deltaSeconds: Double(i) * frameDuration,
                                        width: width,
                                        height: height,
                                        fontName: fontName
                                    )
                                )
                        }
                    }
                }
                .mask(
                    TimerBlinkMask(
                        anchorDate: anchor,
                        deltaSeconds: halfCycle,
                        width: width,
                        height: height,
                        fontName: fontName
                    )
                )
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    @ViewBuilder
    private func opaqueDuoFrame(_ assetName: String) -> some View {
        ZStack {
            Color.black
            renderDuoFrame(assetName)
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func renderDuoFrame(_ assetName: String) -> some View {
        Image(assetName)
            .renderingMode(.original)
            .interpolation(.high)
            .resizable()
            .antialiased(true)
            .scaledToFit()
            .frame(width: width, height: height)
    }
}

private struct TimerBlinkMask: View {
    let anchorDate: Date
    let deltaSeconds: TimeInterval
    let width: CGFloat
    let height: CGFloat
    let fontName: String

    init(
        anchorDate: Date,
        deltaSeconds: TimeInterval,
        size: CGFloat,
        fontName: String = "PetTimerGate-Regular"
    ) {
        self.anchorDate = anchorDate
        self.deltaSeconds = deltaSeconds
        self.width = size
        self.height = size
        self.fontName = fontName
    }

    init(
        anchorDate: Date,
        deltaSeconds: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        fontName: String = "PetTimerGate-Regular"
    ) {
        self.anchorDate = anchorDate
        self.deltaSeconds = deltaSeconds
        self.width = width
        self.height = height
        self.fontName = fontName
    }

    var body: some View {
        let gateDim = max(width, height)
        Text(anchorDate.addingTimeInterval(deltaSeconds), style: .timer)
            .font(.custom(fontName, fixedSize: gateDim))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(width: gateDim * 9, height: gateDim, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .offset(x: -gateDim * 4)
            .frame(width: gateDim, height: gateDim)
            .clipped()
            .frame(width: width, height: height)
            .clipped()
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.layoutDirection, .leftToRight)
    }
}
