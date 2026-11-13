import SwiftUI

// 2.1 result reveal (TASK-REVEAL): while the on-device analysis runs, the
// analyzing page plays a one-shot ~1.2 s "thump" of Stephanie's HeroMelon
// (squash, then a damped rocking wobble) with sound-wave rings rippling
// outward. The analyzing page stays up for at least `RevealTiming.minimum`
// on the success path so the animation is actually seen.

enum RevealTiming {
    /// Minimum time the analyzing page is shown on a successful analysis,
    /// measured from when it appears.
    static let minimum: TimeInterval = 1.2

    /// How much longer to wait before revealing the result, given how long
    /// the analyzing page has already been up. Clamped to [0, minimum]:
    /// slow analyses reveal immediately; a negative elapsed (clock oddity)
    /// never waits more than `minimum`.
    static func remaining(elapsed: TimeInterval, minimum: TimeInterval) -> TimeInterval {
        guard minimum > 0, !minimum.isNaN else { return 0 }
        guard !elapsed.isNaN else { return minimum }
        return min(max(minimum - elapsed, 0), minimum)
    }
}

/// HeroMelon thump + ripple rings. Plays once per appearance (no
/// repeatForever); afterwards the melon rests still. With Reduce Motion on,
/// the melon is shown static and no rings are drawn.
struct RevealAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Melon width; the rings start at this diameter. Sized so the view
    /// keeps roughly the footprint of the PleaseWaitArt block it replaced
    /// (full width x ~180 pt); rings may spill past it while fading.
    var melonWidth: CGFloat = 170
    var height: CGFloat = 200

    @State private var thump = 0
    @State private var ringsOut = false

    /// Ring stagger (s) and per-ring expand/fade duration (s).
    static let ringDelays: [Double] = [0, 0.18, 0.36]
    static let ringDuration: Double = 0.8
    /// Ring scale at end of expansion (relative to melonWidth).
    static let ringEndScale: CGFloat = 1.45

    private struct Pose {
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var angle: Double = 0
    }

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(Self.ringDelays.indices, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 2.5)
                        .frame(width: melonWidth, height: melonWidth)
                        .scaleEffect(ringsOut ? Self.ringEndScale : 0.9)
                        .opacity(ringsOut ? 0 : 0.9)
                        .animation(.easeOut(duration: Self.ringDuration).delay(Self.ringDelays[i]),
                                   value: ringsOut)
                }
            }
            melon
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            ringsOut = true
            thump += 1
        }
    }

    @ViewBuilder private var melon: some View {
        let image = Image("HeroMelon")
            .resizable()
            .scaledToFit()
            .frame(width: melonWidth)
        if reduceMotion {
            image
        } else {
            image.keyframeAnimator(initialValue: Pose(), trigger: thump) { content, pose in
                content
                    .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(pose.angle), anchor: .bottom)
            } keyframes: { _ in
                // Thump: squash down in 0.04 s, spring back by 0.12 s.
                KeyframeTrack(\.scaleY) {
                    CubicKeyframe(0.92, duration: 0.04)
                    CubicKeyframe(1.0, duration: 0.08)
                }
                KeyframeTrack(\.scaleX) {
                    CubicKeyframe(1.04, duration: 0.04)
                    CubicKeyframe(1.0, duration: 0.08)
                }
                // Damped rock about the base, at rest by 1.08 s.
                KeyframeTrack(\.angle) {
                    LinearKeyframe(0, duration: 0.08)
                    CubicKeyframe(-5, duration: 0.14)
                    CubicKeyframe(4, duration: 0.2)
                    CubicKeyframe(-2.5, duration: 0.2)
                    CubicKeyframe(1.2, duration: 0.18)
                    CubicKeyframe(-0.4, duration: 0.14)
                    CubicKeyframe(0, duration: 0.14)
                }
            }
        }
    }
}
