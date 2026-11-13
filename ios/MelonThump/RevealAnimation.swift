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
            image.thump(trigger: thump)
        }
    }
}

// MARK: - Home melon (TASK-HOMEANIM)

/// Home-screen HeroMelon: a gentle idle sway about the base, and one thump
/// (identical to the reveal's) per tap. Purely visual: the tap triggers
/// nothing else. With Reduce Motion on, the melon is fully static and taps
/// do nothing.
///
/// Transform composition: the thump keyframes sit on the INNER image; the
/// idle sway rotation wraps them on the OUTSIDE, so the two rotations add
/// up instead of fighting. Both are transform-only, so layout never moves.
struct HomeMelonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Idle sway amplitude (degrees either side of upright) and full
    /// left-right-left period (s).
    static let swayDegrees: Double = 2
    static let swayPeriod: Double = 2.4

    @State private var thump = 0
    @State private var swaying = false

    var body: some View {
        let image = Image("HeroMelon")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 290)
        Group {
            if reduceMotion {
                image
                    // Reset so turning Reduce Motion back off restarts the sway.
                    .onAppear { swaying = false }
            } else {
                image
                    .thump(trigger: thump)
                    .contentShape(Rectangle())
                    .onTapGesture { thump += 1 }
                    // Scoped animation: the repeatForever applies only to
                    // this rotation, never to layout changes in the same
                    // transaction.
                    .animation(.easeInOut(duration: Self.swayPeriod / 2)
                                   .repeatForever(autoreverses: true)) { content in
                        content.rotationEffect(.degrees(swaying ? Self.swayDegrees : -Self.swayDegrees),
                                               anchor: .bottom)
                    }
                    .onAppear { swaying = true }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shared thump (TASK-HOMEANIM)

/// The one-shot thump pose: a quick squash about the base, then a damped
/// rocking wobble at rest by 1.08 s. Shared by the reveal melon and the
/// home melon so both thump identically.
private struct ThumpPose {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var angle: Double = 0
}

extension View {
    /// Plays one thump each time `trigger` changes. Callers handle Reduce
    /// Motion themselves (by not applying this modifier).
    func thump(trigger: Int) -> some View {
        keyframeAnimator(initialValue: ThumpPose(), trigger: trigger) { content, pose in
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
