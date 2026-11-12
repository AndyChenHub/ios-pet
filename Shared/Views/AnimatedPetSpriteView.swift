import SwiftUI

/// Drives frame-by-frame animation of Alfie or Teddy in both WidgetKit/Dynamic Island
/// (via the custom OpenType `PetTimerGate.ttf` dual-timer mask) and inside the main app.
public struct AnimatedPetSpriteView: View {
    public enum PlaybackDriver: Sendable {
        /// Zero-CPU WidgetKit / Dynamic Island continuous loop powered by `PetTimerGate.ttf`.
        case widgetTimerGate(anchor: Date)
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
            return frames[2] // Closed-eyes peaceful sleep frame for Always-On Display
        }
        return frames.first ?? character.previewAssetName()
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            switch driver {
            case .widgetTimerGate(let anchor):
                if isLuminanceReduced || frames.count <= 1 {
                    spriteImage(named: restingFrameName)
                } else {
                    widgetMaskedLoop(anchor: anchor)
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
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                    .offset(x: size * 0.04, y: -size * 0.02)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func widgetMaskedLoop(anchor: Date) -> some View {
        let period: Double = 2.0
        let count = frames.count
        let delta = period / Double(count)

        ZStack {
            ForEach(Array(frames.enumerated()), id: \.offset) { index, frameName in
                let offset1 = Double(index) * delta
                let offset2 = Double(index) * delta + delta - 1.0

                spriteImage(named: frameName)
                    .mask {
                        SingleTimerGateMask(date: anchor.addingTimeInterval(offset1))
                    }
                    .mask {
                        SingleTimerGateMask(date: anchor.addingTimeInterval(offset2))
                    }
            }
        }
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

/// Renders a single `PetTimerGate` OpenType GSUB glyph (`ON` for even elapsed seconds,
/// `OFF` for odd elapsed seconds) without ever truncating inside compact Dynamic Island slots.
private struct SingleTimerGateMask: View {
    let date: Date

    var body: some View {
        Color.clear
            .overlay {
                Text(date, style: .timer)
                    .font(.custom("PetTimerGate", fixedSize: 200))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .environment(\.layoutDirection, .leftToRight)
            }
    }
}
