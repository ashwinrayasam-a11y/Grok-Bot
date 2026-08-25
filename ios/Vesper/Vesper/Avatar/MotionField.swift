import Foundation

/// The motion vocabulary for Vesper's presence. Three primitives, one rule:
/// everything is continuous. There is no pose library and no state machine of
/// expressions — every visible value is a sum of drifting, eased signals, so
/// the face and body are always in-between, never parked on a named pose.

/// C2-continuous ease (no velocity or acceleration snaps at the ends).
func smootherstep(_ t: Double) -> Double {
    let x = min(1, max(0, t))
    return x * x * x * (x * (x * 6 - 15) + 10)
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * min(1, max(0, t))
}

/// Critically damped smoothing — ease in/out on every motion, overshoot-free.
/// (Standard SmoothDamp formulation.)
struct Damped {
    private(set) var value: Double
    private var velocity: Double = 0

    init(_ initial: Double = 0) {
        value = initial
    }

    mutating func track(_ target: Double, dt: Double, tau: Double) {
        let omega = 2 / max(tau, 0.0001)
        let x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        value = target + (change + temp) * decay
    }
}

/// Smooth aimless drift: picks a new target at irregular intervals and eases
/// toward it. Irrational-feeling pacing, never loops, never sits still.
struct Wander {
    private var from: Double
    private var to: Double
    private var t: Double = 0
    private var duration: Double
    private let range: ClosedRange<Double>
    private let pace: ClosedRange<Double>

    init(range: ClosedRange<Double>, pace: ClosedRange<Double>) {
        self.range = range
        self.pace = pace
        from = .random(in: range)
        to = .random(in: range)
        duration = .random(in: pace)
        t = .random(in: 0...(duration * 0.8))
    }

    mutating func tick(_ dt: Double) -> Double {
        t += dt
        if t >= duration {
            t = 0
            from = to
            to = .random(in: range)
            duration = .random(in: pace)
        }
        return from + (to - from) * smootherstep(t / duration)
    }
}

/// An occasional gesture (blink, glance away, swallow, weight settle) with an
/// eased rise / hold / release envelope. Intervals, depth, and direction are
/// randomized per event so nothing is metronome-regular; a small chance of an
/// immediate follow-up gives natural double-blinks.
/// (Named MotionCue to avoid colliding with SwiftUI's Gesture protocol.)
struct MotionCue {
    struct Shape {
        var rise: ClosedRange<Double>
        var hold: ClosedRange<Double>
        var release: ClosedRange<Double>
    }

    private let interval: ClosedRange<Double>
    private let shape: Shape
    private let doubleChance: Double
    private var wait: Double
    private var age: Double = 0
    private var active = false
    private var rise = 0.1, hold = 0.1, release = 0.2

    /// Randomized per event: how deep this instance goes (0.55…1).
    private(set) var strength: Double = 1
    /// Randomized per event: signed direction bias (−1…−0.35 or 0.35…1).
    private(set) var direction: Double = 0.5

    init(interval: ClosedRange<Double>, shape: Shape, doubleChance: Double = 0) {
        self.interval = interval
        self.shape = shape
        self.doubleChance = doubleChance
        wait = .random(in: interval)
    }

    /// Current envelope, 0…1. `intervalScale` > 1 spaces events out (mood).
    mutating func tick(_ dt: Double, intervalScale: Double = 1) -> Double {
        if !active {
            wait -= dt / max(intervalScale, 0.05)
            if wait <= 0 {
                active = true
                age = 0
                rise = .random(in: shape.rise)
                hold = .random(in: shape.hold)
                release = .random(in: shape.release)
                strength = .random(in: 0.55...1.0)
                direction = Bool.random() ? .random(in: 0.35...1) : .random(in: (-1)...(-0.35))
            }
            return 0
        }
        age += dt
        if age < rise {
            return smootherstep(age / rise) * strength
        }
        if age < rise + hold {
            return strength
        }
        let r = (age - rise - hold) / release
        if r >= 1 {
            active = false
            wait = Double.random(in: 0...1) < doubleChance
                ? .random(in: 0.15...0.4)
                : .random(in: interval)
            return 0
        }
        return (1 - smootherstep(r)) * strength
    }
}
