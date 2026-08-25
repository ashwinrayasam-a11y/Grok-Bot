import Foundation
import RealityKit
import simd

/// Vesper's stylized head, v2 — an original anime-adjacent build. The skull is
/// a swept profile (wide cranium, cheekbones, real V-jaw and chin — not an
/// egg); the beauty lives in large graphic features: almond eyes with bold
/// winged liner and big translating irises, filled merlot lips, a small real
/// nose. The locked portrait is a color/mood reference only; nothing is
/// texture-mapped from a photo, and nothing borrows Ani or Mika.
enum Stylized {
    /// Head profile keys, top → chin: (y, halfWidth, frontDepth, backDepth, n)
    /// where n is the superellipse exponent (higher = flatter cheeks/face).
    private static let keys: [(y: Float, w: Float, dF: Float, dB: Float, n: Float)] = [
        (0.096, 0.012, 0.012, 0.012, 2.0),   // crown
        (0.080, 0.048, 0.052, 0.056, 2.0),
        (0.055, 0.066, 0.064, 0.072, 2.1),
        (0.025, 0.074, 0.069, 0.078, 2.2),   // brow / temple — widest
        (-0.005, 0.075, 0.072, 0.076, 2.3),  // eye line — flat face plane
        (-0.030, 0.070, 0.071, 0.070, 2.3),  // cheekbones
        (-0.050, 0.055, 0.068, 0.058, 2.2),  // jaw sweep begins
        (-0.070, 0.034, 0.063, 0.044, 2.1),
        (-0.085, 0.016, 0.056, 0.028, 2.0),  // chin
        (-0.092, 0.004, 0.046, 0.014, 2.0),  // under-chin
    ]

    static let yTop: Float = 0.096
    static let yChin: Float = -0.092

    /// Interpolated profile at a given height.
    static func profile(y: Float) -> (w: Float, dF: Float, dB: Float, n: Float) {
        let yy = min(yTop, max(yChin, y))
        for i in 0..<(keys.count - 1) {
            let a = keys[i], b = keys[i + 1]
            if yy <= a.y && yy >= b.y {
                let t = (a.y - yy) / max(a.y - b.y, 1e-5)
                let s = t * t * (3 - 2 * t)
                return (
                    a.w + (b.w - a.w) * s,
                    a.dF + (b.dF - a.dF) * s,
                    a.dB + (b.dB - a.dB) * s,
                    a.n + (b.n - a.n) * s
                )
            }
        }
        let last = keys[keys.count - 1]
        return (last.w, last.dF, last.dB, last.n)
    }

    /// Head surface by cross-section angle (psi, 0 = front) and height.
    static func surface(_ psi: Float, _ y: Float) -> SIMD3<Float> {
        let p = profile(y: y)
        let c = cos(psi), s = sin(psi)
        let e = 2 / p.n
        let depth = c >= 0 ? p.dF : p.dB
        let z = powf(abs(c), e) * depth * (c >= 0 ? 1 : -1)
        let x = powf(abs(s), e) * p.w * (s >= 0 ? 1 : -1)
        return SIMD3(x, y, z)
    }

    static func frontZ(_ y: Float) -> Float {
        profile(y: y).dF
    }

    // --- Feature anchors (all derived from the profile) ---
    static let eyeY: Float = -0.008
    static let eyeSpacing: Float = 0.036   // eye centers at ±this
    static let eyeWidth: Float = 0.036
    static let eyeTilt: Float = 0.12       // cat-eye: outer corners up

    static func eyeCenter(side: Float) -> SIMD3<Float> {
        SIMD3(side * eyeSpacing, eyeY, frontZ(eyeY) + 0.001)
    }

    static let mouthY: Float = -0.052
    static let mouthAnchor = SIMD3<Float>(0, mouthY, frontZ(mouthY) + 0.0015)
    static let jawHinge = SIMD3<Float>(0, mouthY - 0.006, mouthAnchor.z - 0.048)

    // MARK: Torso (world/torso space; the head sits at world y 0.055)

    /// Torso profile keys, neck top → crop: (y, halfWidth, frontDepth,
    /// backDepth, n). Slender neck, sloped trapezius, real shoulders, a bust
    /// line, under-bust and ribcage taper — a figure, not a gumdrop.
    private static let torsoKeys: [(y: Float, w: Float, dF: Float, dB: Float, n: Float)] = [
        (-0.018, 0.023, 0.026, 0.024, 2.0),  // neck top (tucks into the head)
        (-0.055, 0.026, 0.028, 0.026, 2.0),  // neck base
        (-0.070, 0.048, 0.034, 0.036, 2.2),  // trapezius slope
        (-0.085, 0.095, 0.040, 0.042, 2.4),
        (-0.095, 0.108, 0.042, 0.044, 2.6),  // shoulder line (widest)
        (-0.115, 0.104, 0.046, 0.046, 2.5),  // upper chest
        (-0.140, 0.096, 0.058, 0.048, 2.4),  // bust swell
        (-0.158, 0.090, 0.066, 0.048, 2.3),  // bust line (max forward)
        (-0.175, 0.084, 0.056, 0.046, 2.3),  // under-bust
        (-0.205, 0.076, 0.046, 0.044, 2.3),  // ribcage
        (-0.245, 0.070, 0.042, 0.042, 2.3),
        (-0.300, 0.072, 0.044, 0.044, 2.3),  // crop bottom
    ]

    static let torsoTop: Float = -0.018
    static let torsoBottom: Float = -0.300

    static func torsoProfile(y: Float) -> (w: Float, dF: Float, dB: Float, n: Float) {
        let yy = min(torsoTop, max(torsoBottom, y))
        for i in 0..<(torsoKeys.count - 1) {
            let a = torsoKeys[i], b = torsoKeys[i + 1]
            if yy <= a.y && yy >= b.y {
                let t = (a.y - yy) / max(a.y - b.y, 1e-5)
                let s = t * t * (3 - 2 * t)
                return (
                    a.w + (b.w - a.w) * s,
                    a.dF + (b.dF - a.dF) * s,
                    a.dB + (b.dB - a.dB) * s,
                    a.n + (b.n - a.n) * s
                )
            }
        }
        let last = torsoKeys[torsoKeys.count - 1]
        return (last.w, last.dF, last.dB, last.n)
    }

    /// Torso surface with a soft center crease through the bust zone.
    static func torsoSurface(_ psi: Float, _ y: Float) -> SIMD3<Float> {
        let p = torsoProfile(y: y)
        let c = cos(psi), s = sin(psi)
        let e = 2 / p.n
        let depth = c >= 0 ? p.dF : p.dB
        var z = powf(abs(c), e) * depth * (c >= 0 ? 1 : -1)
        let x = powf(abs(s), e) * p.w * (s >= 0 ? 1 : -1)
        if z > 0 {
            let bustZone = exp(-powf((y + 0.152) / 0.028, 2))
            z -= z * 0.13 * exp(-powf(x / 0.02, 2)) * bustZone
        }
        return SIMD3(x, y, z)
    }

    static func torsoFrontZ(_ y: Float) -> Float {
        torsoProfile(y: y).dF
    }
}

/// Parametric grid mesh with numeric normals.
struct GridMesh {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    static func build(
        us: [Float],
        vs: [Float],
        point: (Float, Float) -> SIMD3<Float>,
        uv: (Float, Float) -> SIMD2<Float>,
        outwardFrom center: SIMD3<Float>? = nil,
        rawNormals: Bool = false
    ) -> GridMesh {
        var mesh = GridMesh()
        let cols = us.count
        for v in vs {
            for u in us {
                let p = point(u, v)
                mesh.positions.append(p)
                let du: Float = 0.004, dv: Float = 0.004
                let pu = point(u + du, v) - point(u - du, v)
                let pv = point(u, v + dv) - point(u, v - dv)
                var n = cross(pu, pv)
                if !rawNormals {
                    if let center {
                        if dot(n, p - center) < 0 { n = -n }
                    } else if n.z < 0 {
                        n = -n
                    }
                }
                let len = simd_length(n)
                mesh.normals.append(len > 1e-6 ? n / len : SIMD3(0, 0, 1))
                mesh.uvs.append(uv(u, v))
            }
        }
        for vi in 0..<(vs.count - 1) {
            for ui in 0..<(cols - 1) {
                let a = UInt32(vi * cols + ui)
                let b = a + 1
                let c = UInt32((vi + 1) * cols + ui)
                let d = c + 1
                mesh.indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return mesh
    }

    func resource(named name: String) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

func ramp(_ a: Float, _ b: Float, _ n: Int) -> [Float] {
    (0...n).map { a + (b - a) * Float($0) / Float(n) }
}

private func clamp01(_ x: Float) -> Float {
    min(1, max(0, x))
}

enum AvatarGeometry {
    // MARK: - Skull

    static func headMesh() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-.pi, .pi, 48),
            vs: ramp(0, 1, 40),
            point: { psi, v in
                Stylized.surface(psi, Stylized.yTop + (Stylized.yChin - Stylized.yTop) * v)
            },
            uv: { SIMD2(($0 / .pi + 1) / 2, 1 - $1) },
            outwardFrom: .zero
        )
        return try mesh.resource(named: "head")
    }

    /// Small, sharp stylized nose — reads in silhouette and shading, not as a
    /// blob. Skin material; vertices relative to the head origin.
    static func nose() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-1, 1, 6),
            vs: ramp(0, 1.12, 8),
            point: { s, t in
                let down = min(t, 1.0)
                let underside = max(0, t - 1.0)  // folds back under the tip
                let y: Float = -0.006 - 0.024 * down - 0.003 * underside
                let width: Float = 0.0045 * (0.35 + 0.65 * down)
                let out: Float = 0.0078 * down * (1 - 0.4 * abs(s)) - 0.055 * underside
                return SIMD3(
                    s * width,
                    y,
                    Stylized.frontZ(y) - 0.0015 + out
                )
            },
            uv: { SIMD2(($0 + 1) / 2, $1 / 1.12) }
        )
        return try mesh.resource(named: "nose")
    }

    // MARK: - Eyes (large, almond, graphic — the heart of the look)

    /// Almond outline: t 0 = inner corner, 1 = outer corner. Peak shifted
    /// toward the outer corner for the glam cat-eye read.
    static func almondUpper(_ t: Float) -> Float {
        0.0112 * powf(sin(.pi * powf(clamp01(t), 0.88)), 0.9)
    }

    static func almondLower(_ t: Float) -> Float {
        -0.0078 * sin(.pi * clamp01(t))
    }

    static func almondX(_ t: Float, side: Float) -> Float {
        side * (t - 0.5) * Stylized.eyeWidth
    }

    /// Slightly convex white of the eye filling the almond aperture.
    /// Vertices relative to the eye root.
    static func sclera(side: Float) throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(0, 1, 18),
            vs: ramp(0, 1, 8),
            point: { t, s in
                let lo = almondLower(t)
                let hi = almondUpper(t)
                let bulge = 0.0035 * sin(.pi * clamp01(t)) * sin(.pi * s)
                return SIMD3(almondX(t, side: side), lo + (hi - lo) * s, bulge)
            },
            uv: { SIMD2($0, $1) }
        )
        return try mesh.resource(named: "sclera")
    }

    /// Iris disc (textured with VesperIris.png). Sits proud of the sclera and
    /// *translates* for gaze — the 2D-anime eye mechanic, robust and readable.
    static func irisDisc() throws -> MeshResource {
        let r: Float = 0.0085
        let mesh = GridMesh.build(
            us: ramp(0, 1, 20),
            vs: ramp(0, 1, 3),
            point: { u, v in
                let ang = u * 2 * .pi
                let rad = r * v
                return SIMD3(cos(ang) * rad, sin(ang) * rad, 0)
            },
            uv: { u, v in
                let ang = u * 2 * .pi
                return SIMD2(0.5 + cos(ang) * 0.5 * v, 0.5 + sin(ang) * 0.5 * v)
            }
        )
        return try mesh.resource(named: "iris")
    }

    /// Tiny catch-light riding the iris — makes the eye read as alive.
    static func glint() throws -> MeshResource {
        let r: Float = 0.0021
        let mesh = GridMesh.build(
            us: ramp(0, 1, 12),
            vs: ramp(0, 1, 2),
            point: { u, v in
                let ang = u * 2 * .pi
                return SIMD3(cos(ang) * r * v, sin(ang) * r * v, 0)
            },
            uv: { SIMD2($0, $1) }
        )
        return try mesh.resource(named: "glint")
    }

    /// Bold upper lash/liner band sweeping past the outer corner into the
    /// signature wing. t runs 0…1.16 — beyond 1 is the wing.
    static func lashBand(side: Float) throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(0, 1.16, 22),
            vs: ramp(0, 1, 2),
            point: { t, s in
                let base = min(t, 1.0)
                let wing = max(0, t - 1.0)
                let x = almondX(t, side: side)
                let y = almondUpper(base) + wing * 0.055 + s * (0.0042 * (0.35 + 0.65 * sin(.pi * clamp01(base))) + wing * 0.01)
                return SIMD3(x, y, 0.0052 - wing * 0.008)
            },
            uv: { SIMD2(min($0, 1), $1) }
        )
        return try mesh.resource(named: "lash")
    }

    /// Thin lower liner with a little outer-corner emphasis.
    static func lowerLiner(side: Float) throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(0.18, 1.04, 14),
            vs: ramp(0, 1, 2),
            point: { t, s in
                let tt = clamp01(t)
                return SIMD3(
                    almondX(t, side: side),
                    almondLower(tt) - s * (0.0011 + 0.0009 * tt),
                    0.0048
                )
            },
            uv: { SIMD2(clamp01($0), $1) }
        )
        return try mesh.resource(named: "lowerLiner")
    }

    /// Blinking lid: an almond-shaped plate built in its *covering* pose,
    /// hinged along the top edge. The director swings it up-back to tuck it
    /// behind the lash band when open, down flush to close. Smoky eyeshadow
    /// tone doubles as her makeup when the lids hang heavy.
    static func lidPlate(side: Float) throws -> (mesh: MeshResource, hinge: SIMD3<Float>) {
        let hingeY: Float = 0.0116
        let hinge = SIMD3<Float>(0, hingeY, 0.0035)
        let mesh = GridMesh.build(
            us: ramp(0, 1, 16),
            vs: ramp(0, 1, 6),
            point: { t, s in
                let lo = almondLower(t) - 0.0012
                let y = hingeY + (lo - hingeY) * s
                let bulge = 0.0028 * sin(.pi * clamp01(t)) * sin(.pi * s * 0.9)
                return SIMD3(almondX(t, side: side), y - hingeY, bulge)
            },
            uv: { SIMD2($0, $1) }
        )
        return (try mesh.resource(named: "lid"), hinge)
    }

    /// Strong arched brow, angular peak about two-thirds out. Vertices
    /// relative to the returned pivot.
    static func brow(side: Float) throws -> (mesh: MeshResource, pivot: SIMD3<Float>) {
        func spine(_ t: Float) -> SIMD3<Float> {
            let rise = min(1, t / 0.66)
            let fall = max(0, (t - 0.66) / 0.34)
            let y: Float = 0.0125 + 0.0105 * rise - 0.0095 * fall
            let x = side * (0.014 + 0.048 * t)
            return SIMD3(x, y, Stylized.frontZ(y) + 0.002 - 0.006 * max(0, t - 0.8))
        }
        let pivot = spine(0.45)
        let mesh = GridMesh.build(
            us: ramp(0, 1, 16),
            vs: ramp(0, 1, 2),
            point: { t, s in
                let thickness: Float = 0.0042 * (1 - 0.68 * t) + 0.0008
                return spine(t) + SIMD3(0, s * thickness, 0) - pivot
            },
            uv: { SIMD2($0, $1) }
        )
        return (try mesh.resource(named: "brow"), pivot)
    }

    // MARK: - Mouth (filled lip plates, not slits)

    /// Half of the upper lip: a filled plate from the lip line up to the
    /// cupid's bow, gently bowed forward. Vertices relative to the mouth anchor.
    static func lipHalf(side: Float, upper: Bool) throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(0, 1, 14),
            vs: ramp(0, 1, 5),
            point: { t, s in
                let x = side * 0.015 * t
                let lipline: Float = -0.0006 - 0.0012 * t * t
                let edge: Float
                if upper {
                    let dip = 0.0016 * exp(-powf(t / 0.15, 2))
                    edge = 0.0046 * (1 - powf(t, 1.6)) - dip
                } else {
                    edge = -0.0084 * (1 - powf(t, 1.5))
                }
                let y = lipline + (edge - lipline) * s
                let bow = (upper ? 0.0024 : 0.0034) * sin(.pi * s) * (1 - 0.5 * t)
                return SIMD3(x, y, 0.0012 + bow)
            },
            uv: { SIMD2($0, $1) },
            rawNormals: true
        )
        return try mesh.resource(named: "lip")
    }

    /// Dark cavity behind the lips, revealed as the jaw drops.
    static func innerMouth() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-1, 1, 8),
            vs: ramp(-1, 1, 4),
            point: { SIMD3($0 * 0.016, $1 * 0.007 - 0.002, -0.004) },
            uv: { SIMD2(($0 + 1) / 2, ($1 + 1) / 2) }
        )
        return try mesh.resource(named: "innerMouth")
    }

    // MARK: - Body (swept figure: neck → shoulders → bust → ribcage)

    /// Bare skin: the full torso sweep including the neck, connecting cleanly
    /// into the head's underside.
    static func torsoSkin() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-.pi, .pi, 44),
            vs: ramp(Stylized.torsoTop, Stylized.torsoBottom, 26),
            point: { Stylized.torsoSurface($0, $1) },
            uv: { SIMD2(($0 / .pi + 1) / 2, ($1 - Stylized.torsoBottom) / (Stylized.torsoTop - Stylized.torsoBottom)) },
            outwardFrom: .zero
        )
        return try mesh.resource(named: "torsoSkin")
    }

    /// Camisole neckline: dips at the center front (sweetheart), rises over
    /// the chest sides, sits straight and higher across the back.
    static func necklineY(_ psi: Float) -> Float {
        let front: Float = -0.116 - 0.016 * exp(-powf(psi / 0.5, 2))
        let k = min(1, max(0, (abs(psi) - 1.1) / 0.8))
        let s = k * k * (3 - 2 * k)
        return front * (1 - s) + (-0.102) * s
    }

    /// Merlot silk camisole: the same torso surface, offset 1.5 mm proud, from
    /// the neckline down to the crop. Soft drape folds; put-together, fitted.
    /// Vertices relative to `center` so breathing can scale it in place.
    static func torsoSilk() throws -> (mesh: MeshResource, center: SIMD3<Float>) {
        let center = SIMD3<Float>(0, -0.15, 0)
        let mesh = GridMesh.build(
            us: ramp(-.pi, .pi, 44),
            vs: ramp(0, 1, 18),
            point: { psi, s in
                let top = necklineY(psi)
                let y = top + (Stylized.torsoBottom - top) * s
                var p = Stylized.torsoSurface(psi, y)
                let fold = 0.0014 * sin(psi * 9) * sin(s * 5.5)
                let radial = SIMD3(p.x, 0, p.z)
                let len = simd_length(radial)
                if len > 1e-5 {
                    p += radial / len * (0.0015 + fold)
                }
                return p - center
            },
            uv: { SIMD2(($0 / .pi + 1) / 2, 1 - $1) },
            outwardFrom: SIMD3(0, 0, 0) - center
        )
        return (try mesh.resource(named: "silk"), center)
    }

    /// Thin silk strap from the front neckline over the shoulder to the back.
    static func silkStrap(side: Float) throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(0, 1, 12),
            vs: ramp(-1, 1, 2),
            point: { t, w in
                let psi = side * (0.82 + 1.50 * t)
                let y = -0.112 + 0.028 * sin(.pi * t) + w * 0.0035
                var p = Stylized.torsoSurface(psi, y)
                let radial = SIMD3(p.x, 0, p.z)
                let len = simd_length(radial)
                if len > 1e-5 {
                    p += radial / len * 0.0018
                }
                return p
            },
            uv: { SIMD2($0, ($1 + 1) / 2) },
            outwardFrom: .zero
        )
        return try mesh.resource(named: "strap")
    }

    // MARK: - Hair (frames the face; never a veil)

    /// Scalp cap hugging the swept skull (+4 mm): open over the face down to a
    /// high hairline, sweeping to the nape at the back.
    static func hairScalp() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-.pi, .pi, 40),
            vs: ramp(0, 1, 12),
            point: { psi, s in
                let k = clamp01((abs(psi) - 0.8) / 1.6)
                let yMin: Float = 0.042 - 0.094 * (k * k * (3 - 2 * k))
                let y = 0.094 + (yMin - 0.094) * s
                let p = Stylized.surface(psi, y)
                let len = simd_length(p)
                return len > 1e-5 ? p * (1 + 0.004 / len) : p
            },
            uv: { psi, s in SIMD2((psi / .pi + 1) / 2, 1 - (0.05 + 0.55 * s)) },
            outwardFrom: .zero
        )
        return try mesh.resource(named: "hairScalp")
    }

    /// Front curtain: rooted at the scalp side, tucked behind the (opaque)
    /// head across the face's height, emerging below the V-jaw — then draping
    /// forward OVER the shoulders and bust by tracking the torso profile, the
    /// way long hair actually rests on a chest. Frames the face; never veils.
    /// Built in head space (head center sits at world y +0.055).
    static func hairCurtain(side: Float) throws -> MeshResource {
        let band: ClosedRange<Float> = side < 0 ? 0.03...0.45 : 0.55...0.97
        let mesh = GridMesh.build(
            us: ramp(0, 1, 6),
            vs: ramp(0, 1, 28),
            point: { s, t in
                let inner: Float = 0.048 + 0.026 * powf(t, 0.9)
                let width: Float = 0.038 + 0.024 * t
                let y: Float = 0.062 - 0.52 * t + s * 0.003
                let worldY = y + 0.055
                var z: Float = 0.006 - 0.018 * t - 0.024 * t * t - s * 0.020
                if worldY < -0.06 {
                    // Ride the chest: torso front + clearance, blended in.
                    let k = min(1, (-worldY - 0.06) / 0.035)
                    let blend = k * k * (3 - 2 * k)
                    let drape = Stylized.torsoFrontZ(worldY) + 0.007 - s * 0.004
                    z = z * (1 - blend) + drape * blend
                }
                return SIMD3(side * (inner + s * width), y, z)
            },
            uv: { s, t in
                SIMD2(band.lowerBound + s * (band.upperBound - band.lowerBound), 1 - t)
            }
        )
        return try mesh.resource(named: "curtain")
    }

    /// Side fall behind the shoulders (torso space) — outside the new
    /// shoulder width, behind the back plane.
    static func hairFall(side: Float) throws -> MeshResource {
        let band: ClosedRange<Float> = side < 0 ? 0.10...0.48 : 0.52...0.90
        let mesh = GridMesh.build(
            us: ramp(0, 1, 6),
            vs: ramp(0, 1, 24),
            point: { s, t in
                SIMD3(
                    side * (0.075 + 0.030 * t + s * 0.050),
                    0.10 - 0.53 * t,
                    -0.055 - 0.028 * t - s * 0.016
                )
            },
            uv: { s, t in
                SIMD2(band.lowerBound + s * (band.upperBound - band.lowerBound), 1 - t)
            }
        )
        return try mesh.resource(named: "hairFall")
    }

    /// Wide sheet down the back to mid-back (torso space) — a dark backdrop
    /// visible beyond the shoulder silhouette.
    static func hairBack() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-1, 1, 14),
            vs: ramp(0, 1, 16),
            point: { u, v in
                let half: Float = 0.150 + 0.080 * v
                return SIMD3(
                    u * half,
                    0.12 - 0.57 * v,
                    -0.072 - 0.02 * sin(v * .pi * 0.5) + 0.030 * u * u
                )
            },
            uv: { SIMD2(($0 + 1) / 2, 1 - $1) }
        )
        return try mesh.resource(named: "hairBack")
    }
}
