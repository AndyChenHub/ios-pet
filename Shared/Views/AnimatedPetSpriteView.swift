import CoreText
import SwiftUI

private enum PetFontRegistrar {
    static let registerOnce: Void = {
        if let url = Bundle.main.url(forResource: "PetTimerGate-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

/// Drives frame-by-frame animation of Alfie or Teddy in both WidgetKit/Dynamic Island
/// (via the 2-stack Painter's Algorithm + `PetTimerGate-Regular.ttf` seconds ligature gate)
/// and inside the main app.
public struct AnimatedPetSpriteView: View {
    public enum PlaybackDriver: Sendable {
        /// Zero-CPU WidgetKit / Dynamic Island continuous loop with guaranteed visible base frame.
        case widgetTimerGate(anchor: Date)
        /// Lightweight static single-frame render for the tiny Dynamic Island Minimal bubble.
        case widgetStatic
        /// High-FPS TimelineView loop for interactive in-app stages and previews.
        case liveTimeline
    }

    public let character: PetCharacter
    public let action: PetAction
    public let size: CGFloat
    public let driver: PlaybackDriver
    public var showSleepBadge: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(
        character: PetCharacter,
        action: PetAction,
        size: CGFloat,
        driver: PlaybackDriver,
        showSleepBadge: Bool = false
    ) {
        _ = PetFontRegistrar.registerOnce
        self.character = character
        self.action = action
        self.size = size
        self.driver = driver
        self.showSleepBadge = showSleepBadge
    }

    private var frames: [String] {
        character.frameAssetNames(for: action)
    }

    private var restingFrameName: String {
        if action == .sleeping, frames.count > 2 {
            return frames[2]
        }
        return frames.first ?? character.previewAssetName()
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            switch driver {
            case .widgetStatic:
                spriteImage(named: restingFrameName)

            case .widgetTimerGate(let anchor):
                if isLuminanceReduced || frames.count < 2 {
                    spriteImage(named: restingFrameName)
                } else {
                    widgetTwoStackLoop(anchor: anchor)
                }

            case .liveTimeline:
                TimelineView(.periodic(from: .now, by: 1.0 / max(action.inAppFPS, 1.0))) { context in
                    let rawTick = Int(floor(context.date.timeIntervalSinceReferenceDate * action.inAppFPS))
                    let idx = ((rawTick % frames.count) + frames.count) % frames.count
                    spriteImage(named: frames[idx])
                }
            }

            if showSleepBadge && action == .sleeping && size >= 44 {
                Text("zZz")
                    .font(.system(size: max(10, size * 0.17), weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.76, green: 0.72, blue: 1.0))
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    .offset(x: size * 0.04, y: -size * 0.02)
            }
        }
        .frame(width: size, height: size)
    }

    /// Two-stack Painter's Algorithm over a 2.0-second cycle:
    /// - Frame 0 sits unmasked at the bottom so a dog is ALWAYS visible on the Dynamic Island.
    /// - Each subsequent opaque-black-backed frame covers the previous one as its 1s blink gate opens.
    @ViewBuilder
    private func widgetTwoStackLoop(anchor: Date) -> some View {
        let count = frames.count
        let half = max(1, count / 2)
        let frameDuration = 2.0 / Double(count)

        ZStack {
            // Stack 1: Frames 0 ..< half (Frame 0 is completely unmasked!)
            ZStack {
                opaqueBlackBackedSprite(named: frames[0])

                if half > 1 {
                    ForEach(1..<half, id: \.self) { i in
                        opaqueBlackBackedSprite(named: frames[i])
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

            // Stack 2: Frames half ..< count, visible during [1.0s, 2.0s) of each 2s loop
            if count > half {
                ZStack {
                    opaqueBlackBackedSprite(named: frames[half])

                    if count > half + 1 {
                        ForEach((half + 1)..<count, id: \.self) { i in
                            opaqueBlackBackedSprite(named: frames[i])
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
    private func opaqueBlackBackedSprite(named name: String) -> some View {
        ZStack {
            Color.black
            spriteImage(named: name)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func spriteImage(named name: String) -> some View {
        Image(name)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Blinks ON (solid `size x size` square) during even elapsed seconds and OFF during odd elapsed seconds
/// by centering the trailing 2-digit seconds ligature of `Text(..., style: .timer)` over `[0, size]`.
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
