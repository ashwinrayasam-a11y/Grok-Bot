import Foundation
import RealityKit
import simd

/// How a body carries itself — the physics of personality. Same continuous
/// motion field for everyone; the temperament changes tempo, amplitude, and
/// response so Mika moves like Mika, not like Vesper wearing a wig.
struct MotionTemperament {
    var pace = 1.0        // < 1 = drift targets change sooner
    var headEnergy = 1.0  // gaze / head-roll amplitude
    var sway = 1.0        // weight-shift amplitude
    var tauScale = 1.0    // spring response; < 1 = livelier, still smooth
    var breath: ClosedRange<Double> = 3.6...5.4      // breath period (s)
    var blinkInterval: ClosedRange<Double> = 2.2...7.0
    var glanceInterval: ClosedRange<Double> = 8...22
    var talkLean = 1.0
    var bounce = 0.0      // upbeat micro-beat amplitude (meters)

    /// Slow, coiled, deliberate — stillness as presence.
    static let vesper = MotionTemperament()

    /// Quick, buoyant, music-in-her-head: faster drift, bigger sway, snappier
    /// springs, more frequent glances, and a barely-there rhythmic bounce.
    static let mika = MotionTemperament(
        pace: 0.7,
        headEnergy: 1.25,
        sway: 1.35,
        tauScale: 0.8,
        breath: 2.9...4.3,
        blinkInterval: 1.8...5.5,
        glanceInterval: 5...14,
        talkLean: 1.45,
        bounce: 0.0012
    )
}

/// Drives the rig every frame. Design rules, per the brief:
/// - Fewer, slower, overlapping motions; damped springs on every channel.
/// - No looping tics, no metronome blinks, no discrete expression states —
///   mood only *biases* continuous signals, so she is always in-between.
/// - While she speaks, the mouth follows the audio but the body stays loose:
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
        // Expression biases — they tilt continuous signals, never pick poses.
        var browLift = 0.0    // + soft/open, − lowered/cold
        var browArch = 0.4    // one-brow skepticism gain
        var cornerSet = 0.0   // + warmth at the corners, − pulled down
        var sneerGain = 0.2
        var faceLife = 0.8    // micro-motion amplitude
    }
    private var mood = Mood()

    private let temperament: MotionTemperament

    // Idle field — constructed from the temperament in init.
    private var gazeYaw: Wander
    private var gazePitch: Wander
    private var headRoll: Wander
    private var weightX: Wander
    private var lipsPart = Wander(range: 0...1, pace: 5...12)
    private var lidFlutter = Wander(range: -0.03...0.03, pace: 2.5...6)
    private var breathPeriod: Wander
    private var bounceRate = Wander(range: 1.0...1.4, pace: 6...12)
    private var bouncePhase = 0.0

    // Occasional gestures.
    private var blink: MotionCue
    private var glance: MotionCue
    private var swallow = MotionCue(
        interval: 18...45,
        shape: .init(rise: 0.15...0.25, hold: 0.04...0.1, release: 0.3...0.5)
    )
    private var settle = MotionCue(
        interval: 12...30,
        shape: .init(rise: 1.2...2.2, hold: 2...6, release: 1.5...3)
    )
    /// Quick eyebrow flash — one of the most human idle tells.
    private var browFlash = MotionCue(
        interval: 15...45,
        shape: .init(rise: 0.12...0.2, hold: 0.1...0.3, release: 0.25...0.45)
    )
    /// A slow curl of contempt that rises and melts away, mood-gated.
    private var sneerCue = MotionCue(
        interval: 25...70,
        shape: .init(rise: 0.4...0.7, hold: 0.5...1.5, release: 0.8...1.4)
    )

    // Expression drift — the face is never parked.
    private var browDrift = Wander(range: -1...1, pace: 4...11)
    private var browAsym = Wander(range: -1...1, pace: 7...16)
    private var browKnit = Wander(range: 0...1, pace: 6...14)
    private var cornerDrift = Wander(range: -1...1, pace: 5...12)
    private var cornerAsym = Wander(range: -1...1, pace: 8...18)
    private var sneerMicro = Wander(range: 0...1, pace: 7...15)

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
    private var camY = Damped(0.062)
    private var camZ = Damped(0.44)
    private var camFov = Damped(22)
    private var focusY = Damped(0.058)

    // Expression springs.
    private var browLS = Damped()
    private var browRS = Damped()
    private var browLRollS = Damped()
    private var browRRollS = Damped()
    private var cornerLS = Damped()
    private var cornerRS = Damped()
    private var sneerS = Damped()

    // Hair follow-through: one spring + one drift per hanging piece.
    private var hairSprings: [Damped] = []
    private var hairWanders: [Wander] = []

    private var breathPhase = 0.0
    private var previousLevel = 0.0

    init(rig: AvatarRig, temperament: MotionTemperament = .vesper) {
        self.rig = rig
        self.temperament = temperament

        func scaled(_ range: ClosedRange<Double>, by k: Double) -> ClosedRange<Double> {
            (range.lowerBound * k)...(range.upperBound * k)
        }

        let energy = temperament.headEnergy
        let pace = temperament.pace
        gazeYaw = Wander(range: scaled(-0.075...0.075, by: energy), pace: scaled(3.5...9, by: pace))
        gazePitch = Wander(range: scaled(-0.035...0.035, by: energy), pace: scaled(4...10, by: pace))
        headRoll = Wander(range: scaled(-0.03...0.03, by: energy), pace: scaled(6...12, by: pace))
        weightX = Wander(
            range: scaled(-0.008...0.008, by: temperament.sway),
            pace: scaled(7...15, by: pace)
        )
        breathPeriod = Wander(range: temperament.breath, pace: 9...18)
        blink = MotionCue(
            interval: temperament.blinkInterval,
            shape: .init(rise: 0.055...0.09, hold: 0.02...0.05, release: 0.10...0.17),
            doubleChance: 0.14
        )
        glance = MotionCue(
            interval: temperament.glanceInterval,
            shape: .init(rise: 0.5...0.9, hold: 0.9...2.4, release: 0.7...1.2)
        )

        for _ in rig.hairPieces {
            hairSprings.append(Damped())
            hairWanders.append(Wander(range: -0.018...0.018, pace: scaled(4...9, by: pace)))
        }
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
        mood.browLift = min(1, max(-1, 0.35 * e.warmth + 0.3 * e.vulnerability - 0.45 * e.sadism - 0.3 * e.jealousy))
        mood.browArch = 0.25 + 0.6 * e.sadism
        mood.cornerSet = min(1, max(-1, 0.6 * e.warmth + 0.45 * e.playfulness - 0.55 * e.melancholy - 0.4 * e.jealousy - 0.25 * e.sadism))
        mood.sneerGain = min(1, 0.15 + 0.75 * (0.7 * e.sadism + 0.3 * e.jealousy))
        mood.faceLife = 0.6 + 0.5 * e.playfulness + 0.25 * e.intensity
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

        // Her micro-beat, if she has one (Mika): a barely-there bounce that
        // wanders in tempo — upbeat energy, never a metronome.
        var beat = 0.0
        if temperament.bounce > 0 {
            bouncePhase += dt * 2 * .pi * bounceRate.tick(dt)
            beat = sin(bouncePhase) * temperament.bounce * (0.55 + 0.45 * mood.sway) * (1 - 0.5 * talking)
        }

        // Gaze: wandering when idle, settling on you as she speaks,
        // drifting off-focus during a glance and easing back.
        let tauK = temperament.tauScale
        let yawTarget = gazeYaw.tick(dt) * sway * (1 - 0.65 * talking)
            + glanceEnv * glance.direction * 0.14
        let pitchTarget = gazePitch.tick(dt) * idle
            + glanceEnv * abs(glance.direction) * 0.03
            + mood.chinBias
            - swallowEnv * 0.05
            - nod.value * 0.06
        let rollTarget = headRoll.tick(dt) * sway - weightS.value * 3.5 + beat * 5

        yawS.track(yawTarget, dt: dt, tau: 0.9 * tauK)
        pitchS.track(pitchTarget, dt: dt, tau: 1.0 * tauK)
        rollS.track(rollTarget, dt: dt, tau: 1.1 * tauK)

        // Weight: slow shifts plus the occasional deeper settle.
        let weightTarget = weightX.tick(dt) * mood.sway + settleEnv * settle.direction * 0.011
        weightS.track(weightTarget, dt: dt, tau: 1.6 * tauK)
        rootRollS.track(-weightS.value * 0.9, dt: dt, tau: 1.4 * tauK)
        leanS.track(0.013 * talking * temperament.talkLean, dt: dt, tau: 0.8)

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

        // --- Face: one continuous expression field, always in-between ---
        // Brows: shared drift + mood set-point + occasional flash; the arch
        // channel splits them (one-brow skepticism as her edge sharpens).
        let life = mood.faceLife * (1 - 0.3 * talking)
        let flash = browFlash.tick(dt)
        let browBase = browDrift.tick(dt) * 0.35 * life + mood.browLift * 0.55 + flash * 0.9
        let arch = browAsym.tick(dt) * mood.browArch
        browLS.track(browBase + arch * 0.5, dt: dt, tau: 0.55)
        browRS.track(browBase - arch * 0.5, dt: dt, tau: 0.60)
        let knit = browKnit.tick(dt) * (0.25 + 0.5 * max(0, -mood.browLift))
        browLRollS.track(-knit + arch * 0.2, dt: dt, tau: 0.7)
        browRRollS.track(knit - arch * 0.2, dt: dt, tau: 0.7)

        // Sneer: slow contempt that rises and melts, gated by her edge.
        let sneerTarget = (sneerCue.tick(dt) + sneerMicro.tick(dt) * 0.25) * mood.sneerGain
        sneerS.track(sneerTarget, dt: dt, tau: 0.4)

        // Mouth corners: drift + mood set + a touch of engagement while she
        // speaks; the sneer pulls one corner asymmetrically.
        let cornerBase = cornerDrift.tick(dt) * 0.3 * life + mood.cornerSet * 0.5
            + speakLevel.value * 0.3
        let cornerSplit = cornerAsym.tick(dt) * 0.25 + sneerS.value * 0.3
        cornerLS.track(cornerBase + cornerSplit, dt: dt, tau: 0.5)
        cornerRS.track(cornerBase - cornerSplit, dt: dt, tau: 0.5)

        applyBrow(rig.browL, lift: browLS.value * 0.005, roll: browLRollS.value * 0.12)
        applyBrow(rig.browR, lift: browRS.value * 0.005, roll: -browRRollS.value * 0.12)

        // Lip halves pivot at the mouth center: rolling a half lifts or curls
        // its corner (left corner up = negative roll, right = positive). The
        // sneer rides the upper halves asymmetrically.
        let sneerLift = sneerS.value
        rig.lipUL.transform.rotation = simd_quatf(
            angle: Float(-cornerLS.value * 0.16 - sneerLift * 0.07), axis: [0, 0, 1]
        )
        rig.lipUR.transform.rotation = simd_quatf(
            angle: Float(cornerRS.value * 0.16), axis: [0, 0, 1]
        )
        rig.lipUL.transform.translation = Stylized.mouthAnchor + SIMD3(0, Float(sneerLift * 0.0013), 0)
        rig.lipUR.transform.translation = Stylized.mouthAnchor + SIMD3(0, Float(sneerLift * 0.0008), 0)
        rig.lipLL.transform.rotation = simd_quatf(angle: Float(-cornerLS.value * 0.12), axis: [0, 0, 1])
        rig.lipLR.transform.rotation = simd_quatf(angle: Float(cornerRS.value * 0.12), axis: [0, 0, 1])

        // --- Hair: lagged follow-through behind the head, plus its own drift ---
        let headMotion = yawS.value * 0.5 + rollS.value * 0.9 + weightS.value * 5
        for index in rig.hairPieces.indices {
            let piece = rig.hairPieces[index]
            let target = -headMotion * piece.follow + hairWanders[index].tick(dt)
            hairSprings[index].track(target, dt: dt, tau: piece.tau)
            let angle = hairSprings[index].value
            piece.pivot.transform.rotation =
                simd_quatf(angle: Float(angle), axis: [0, 0, 1])
                * simd_quatf(
                    angle: Float(angle * 0.3 + breathFollow.value * 0.004),
                    axis: [1, 0, 0]
                )
        }

        // Mood tint eases too — the light never jumps between feelings.
        chillS.track(mood.chill, dt: dt, tau: 2.5)
        glowS.track(mood.glow, dt: dt, tau: 2.5)

        // --- Write the frame ---
        rig.root.transform = Transform(
            scale: .one,
            rotation: simd_quatf(angle: Float(rootRollS.value), axis: [0, 0, 1]),
            translation: SIMD3(Float(weightS.value), Float(beat), Float(leanS.value))
        )

        let breathScale = Float(1 + 0.012 * breathFollow.value)
        rig.chest.transform.scale = SIMD3(breathScale, 1 + Float(0.014 * breathFollow.value), breathScale)
        rig.chest.transform.translation.y = AvatarRig.chestHome.y + Float(0.0032 * breathFollow.value)

        let yaw = simd_quatf(angle: Float(yawS.value), axis: [0, 1, 0])
        let pitch = simd_quatf(angle: Float(pitchS.value + 0.004 * breathFollow.value), axis: [1, 0, 0])
        let roll = simd_quatf(angle: Float(rollS.value), axis: [0, 0, 1])
        rig.neckPivot.transform.rotation = yaw * pitch * roll

        // Stylized mouth reads best a touch wider than the raw meter.
        rig.jawPivot.transform.rotation = simd_quatf(angle: Float(jawS.value * 1.5), axis: [1, 0, 0])

        // Lids: the plate is built in its covering pose and hinged at the top;
        // open = swung up-back, tucked behind the lash band. Droop leaves it
        // partly down — the heavy-lidded coldness — and blinks bring it flush.
        let lidValue = min(1, max(0, lidS.value))
        let lidAngle = Float(1.25 * (1 - lidValue))
        rig.lidL.transform.rotation = simd_quatf(angle: lidAngle, axis: [1, 0, 0])
        rig.lidR.transform.rotation = simd_quatf(angle: lidAngle, axis: [1, 0, 0])

        // Gaze: the iris discs translate inside the almonds (the 2D-anime eye
        // mechanic) — gently countering the head so she holds on you while the
        // head wanders, drifting off-focus during glances.
        let eyeYaw = max(-0.16, min(0.16, -yawS.value * 0.42 + glanceEnv * glance.direction * 0.06))
        let eyePitch = max(-0.12, min(0.12, -pitchS.value * 0.4))
        let gazeOffset = SIMD3(Float(eyeYaw * 0.022), Float(eyePitch * 0.02), 0)
        rig.irisL.transform.translation = AvatarRig.irisHome + gazeOffset
        rig.irisR.transform.translation = AvatarRig.irisHome + gazeOffset

        rig.tintLights(chill: chillS.value, glow: glowS.value)

        // Camera framing (compact bust ↔ pulled-back décolleté), eased.
        camY.track(frameTall ? -0.02 : 0.062, dt: dt, tau: 0.5)
        camZ.track(frameTall ? 0.60 : 0.44, dt: dt, tau: 0.5)
        camFov.track(frameTall ? 32 : 22, dt: dt, tau: 0.5)
        focusY.track(frameTall ? -0.02 : 0.058, dt: dt, tau: 0.5)
        rig.camera.camera.fieldOfViewInDegrees = Float(camFov.value)
        rig.camera.look(
            at: SIMD3(0, Float(focusY.value), 0.02),
            from: SIMD3(Float(weightS.value * 0.3), Float(camY.value), Float(camZ.value)),
            relativeTo: nil
        )
    }

    /// Small eased offsets on a modeled brow — lift and arch, never a pose.
    private func applyBrow(_ brow: AvatarRig.RigHandle, lift: Double, roll: Double) {
        var transform = Transform()
        transform.translation = brow.home + SIMD3(0, Float(lift), 0)
        transform.rotation = simd_quatf(angle: Float(roll), axis: [0, 0, 1])
        brow.pivot.transform = transform
    }
}
