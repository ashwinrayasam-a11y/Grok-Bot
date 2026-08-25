import Foundation
import RealityKit
import simd

/// Drives the rig every frame. Design rules, per the brief:
/// - Fewer, slower, overlapping motions; damped springs on every channel.
/// - No looping tics, no metronome blinks, no discrete expression states —
///   mood only *biases* continuous signals, so she is always in-between.
/// - While Ara speaks, the mouth follows the audio but the body stays loose:
///   a slight lean, a settled gaze, breath still moving.
final class AvatarDirector {
    private let rig: AvatarRig

    /// Live inputs, wired by the presence view.
    var audioLevel: () -> Float = { 0 }
    var isSpeaking: () -> Bool = { false }
    var frameTall = false

    // Continuous mood bias, derived from EmotionState (no pose states).
    private struct Mood {
        var chill = 0.35      // ember → rose light
        var glow = 0.55
        var lidDroop = 0.16
        var sway = 1.0
        var breathDepth = 1.0
        var chinBias = 0.0    // radians; negative = chin dipped, colder
        var blinkSpacing = 1.0
    }
    private var mood = Mood()

    // Idle field.
    private var gazeYaw = Wander(range: -0.075...0.075, pace: 3.5...9)
    private var gazePitch = Wander(range: -0.035...0.035, pace: 4...10)
    private var headRoll = Wander(range: -0.03...0.03, pace: 6...12)
    private var weightX = Wander(range: -0.008...0.008, pace: 7...15)
    private var lipsPart = Wander(range: 0...1, pace: 5...12)
    private var lidFlutter = Wander(range: -0.03...0.03, pace: 2.5...6)
    private var breathPeriod = Wander(range: 3.6...5.4, pace: 9...18)

    // Occasional gestures.
    private var blink = MotionCue(
        interval: 2.2...7.0,
        shape: .init(rise: 0.055...0.09, hold: 0.02...0.05, release: 0.10...0.17),
        doubleChance: 0.14
    )
    private var glance = MotionCue(
        interval: 8...22,
        shape: .init(rise: 0.5...0.9, hold: 0.9...2.4, release: 0.7...1.2)
    )
    private var swallow = MotionCue(
        interval: 18...45,
        shape: .init(rise: 0.15...0.25, hold: 0.04...0.1, release: 0.3...0.5)
    )
    private var settle = MotionCue(
        interval: 12...30,
        shape: .init(rise: 1.2...2.2, hold: 2...6, release: 1.5...3)
    )

    // Output springs — nothing reaches the rig without passing through one.
    private var yawS = Damped()
    private var pitchS = Damped()
    private var rollS = Damped()
    private var weightS = Damped()
    private var rootRollS = Damped()
    private var leanS = Damped()
    private var jawS = Damped()
    private var lidS = Damped(0.16)
    private var speakW = Damped()
    private var speakLevel = Damped()
    private var nod = Damped()
    private var breathFollow = Damped()
    private var chillS = Damped(0.35)
    private var glowS = Damped(0.55)
    private var camY = Damped(0.05)
    private var camZ = Damped(0.46)
    private var camFov = Damped(22)
    private var focusY = Damped(0.045)

    private var breathPhase = 0.0
    private var previousLevel = 0.0

    init(rig: AvatarRig) {
        self.rig = rig
    }

    /// Continuous mapping from her living emotional state — biases, not poses.
    func setMood(from e: EmotionState) {
        mood.chill = min(1, max(0, 0.35 * e.sadism + 0.4 * e.jealousy + 0.25 * e.melancholy))
        mood.glow = min(1, max(0, 0.3 + 0.7 * e.intensity))
        mood.lidDroop = min(0.42, max(0.06, 0.10 + 0.22 * e.melancholy + 0.12 * e.sadism - 0.08 * e.playfulness))
        mood.sway = 0.55 + 0.9 * e.playfulness
        mood.breathDepth = 0.8 + 0.6 * e.intensity
        mood.chinBias = 0.03 * (e.warmth + e.devotion) / 2 - 0.045 * e.sadism - 0.02 * e.jealousy
        mood.blinkSpacing = 1 + 0.8 * e.intensity
    }

    func tick(dt rawDt: Double) {
        let dt = min(rawDt, 1.0 / 20.0)  // guard against hitches
        guard dt > 0 else { return }

        // --- Speech input ---
        let live = Double(audioLevel())
        speakLevel.track(live, dt: dt, tau: live > speakLevel.value ? 0.045 : 0.16)
        speakW.track(isSpeaking() ? 1 : 0, dt: dt, tau: 0.35)
        let talking = speakW.value

        // Small nods riding the onsets of her phrases, decaying naturally.
        let onset = max(0, speakLevel.value - previousLevel) / max(dt, 0.001)
        previousLevel = speakLevel.value
        nod.track(min(0.8, onset * 0.04) * talking, dt: dt, tau: 0.28)

        // --- Idle field (amplitude eases down, never off, while she speaks) ---
        let idle = 1 - 0.45 * talking
        let sway = mood.sway * idle

        let blinkEnv = blink.tick(dt, intervalScale: mood.blinkSpacing)
        let glanceEnv = glance.tick(dt)
        let swallowEnv = swallow.tick(dt)
        let settleEnv = settle.tick(dt)

        breathPhase += dt * 2 * .pi / breathPeriod.tick(dt)
        let breath = (sin(breathPhase) + 1) / 2 * mood.breathDepth + swallowEnv * 0.3
        breathFollow.track(breath, dt: dt, tau: 0.3)  // lagged follow-through

        // Gaze: wandering when idle, settling on you as she speaks,
        // drifting off-focus during a glance and easing back.
        let yawTarget = gazeYaw.tick(dt) * sway * (1 - 0.65 * talking)
            + glanceEnv * glance.direction * 0.14
        let pitchTarget = gazePitch.tick(dt) * idle
            + glanceEnv * abs(glance.direction) * 0.03
            + mood.chinBias
            - swallowEnv * 0.05
            - nod.value * 0.06
        let rollTarget = headRoll.tick(dt) * sway - weightS.value * 3.5

        yawS.track(yawTarget, dt: dt, tau: 0.9)
        pitchS.track(pitchTarget, dt: dt, tau: 1.0)
        rollS.track(rollTarget, dt: dt, tau: 1.1)

        // Weight: slow shifts plus the occasional deeper settle.
        let weightTarget = weightX.tick(dt) * mood.sway + settleEnv * settle.direction * 0.011
        weightS.track(weightTarget, dt: dt, tau: 1.6)
        rootRollS.track(-weightS.value * 0.9, dt: dt, tau: 1.4)
        leanS.track(0.013 * talking, dt: dt, tau: 0.8)

        // Mouth: audio drives the jaw; lips keep a faint idle life of their own.
        let jawTarget = pow(speakLevel.value, 0.85) * 0.16 * (0.75 + 0.25 * mood.glow)
            + lipsPart.tick(dt) * 0.012 * idle
        jawS.track(jawTarget, dt: dt, tau: 0.05)

        // Lids: mood droop + irregular blinks + micro flutter, one blend.
        let lidTarget = max(
            mood.lidDroop + lidFlutter.tick(dt) * idle + glanceEnv * 0.08,
            blinkEnv
        )
        lidS.track(min(1, lidTarget), dt: dt, tau: 0.045)

        // Mood tint eases too — the light never jumps between feelings.
        chillS.track(mood.chill, dt: dt, tau: 2.5)
        glowS.track(mood.glow, dt: dt, tau: 2.5)

        // --- Write the frame ---
        rig.root.transform = Transform(
            scale: .one,
            rotation: simd_quatf(angle: Float(rootRollS.value), axis: [0, 0, 1]),
            translation: SIMD3(Float(weightS.value), 0, Float(leanS.value))
        )

        let breathScale = Float(1 + 0.014 * breathFollow.value)
        rig.chest.transform.scale = SIMD3(breathScale, 1 + Float(0.018 * breathFollow.value), breathScale)
        rig.chest.transform.translation.y = -0.185 + Float(0.0035 * breathFollow.value)

        let yaw = simd_quatf(angle: Float(yawS.value), axis: [0, 1, 0])
        let pitch = simd_quatf(angle: Float(pitchS.value + 0.004 * breathFollow.value), axis: [1, 0, 0])
        let roll = simd_quatf(angle: Float(rollS.value), axis: [0, 0, 1])
        rig.neckPivot.transform.rotation = yaw * pitch * roll

        rig.jawPivot.transform.rotation = simd_quatf(angle: Float(jawS.value), axis: [1, 0, 0])

        let lidScale = Float(max(0.02, lidS.value))
        rig.lidL.transform.scale.y = lidScale
        rig.lidR.transform.scale.y = lidScale

        rig.tintLights(chill: chillS.value, glow: glowS.value)

        // Camera framing (compact bust ↔ pulled-back décolleté), eased.
        camY.track(frameTall ? -0.015 : 0.052, dt: dt, tau: 0.5)
        camZ.track(frameTall ? 0.62 : 0.45, dt: dt, tau: 0.5)
        camFov.track(frameTall ? 30 : 21, dt: dt, tau: 0.5)
        focusY.track(frameTall ? -0.01 : 0.045, dt: dt, tau: 0.5)
        rig.camera.camera.fieldOfViewInDegrees = Float(camFov.value)
        rig.camera.look(
            at: SIMD3(0, Float(focusY.value), 0.02),
            from: SIMD3(Float(weightS.value * 0.3), Float(camY.value), Float(camZ.value)),
            relativeTo: nil
        )
    }
}
