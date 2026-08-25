import Foundation
import RealityKit
import simd

/// Vesper's stylized head — original modeled geometry, anime-adjacent, built
/// entirely in code. The locked portrait is an identity *reference* only
/// (coloring, liner, mood); nothing is texture-mapped from a photo. Every
/// facial feature is anchored by evaluating the head surface function, so
/// eyes, lids, brows, and lips are registered by construction — no floating
/// parts, and they can actually act.
enum Stylized {
    // Head ellipsoid radii (meters).
    static let rx: Float = 0.075
    static let ry: Float = 0.098
    static let rz: Float = 0.078

    /// Head surface. `alpha` = azimuth from the front (+ right), `beta` =
    /// elevation from center (+ up). Gentle jaw taper, a small nose, a hint
    /// of chin — stylized-smooth; the big eyes and makeup carry the look.
    static func headPoint(_ alpha: Float, _ beta: Float) -> SIMD3<Float> {
        let d = SIMD3(cos(beta) * sin(alpha), sin(beta), cos(beta) * cos(alpha))
        var p = SIMD3(rx * d.x, ry * d.y, rz * d.z)
        // Taper toward a feminine jaw / chin below the cheekbones.
        let drop = max(0, -beta - 0.12)
        let frontness = max(0, cos(alpha))
        p.x *= 1 - 0.24 * min(1, drop / 0.85) * (0.35 + 0.65 * frontness)
        // Small stylized nose.
        let na = alpha / 0.13, nb = (beta + 0.13) / 0.11
        p.z += 0.0075 * exp(-(na * na + nb * nb))
        // A hint of chin so the profile isn't an egg.
        let ca = alpha / 0.22, cb = (beta + 0.72) / 0.16
        p.z += 0.004 * exp(-(ca * ca + cb * cb))
        return p
    }

    /// Push a surface point outward along its radial direction.
    static func proud(_ p: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
        let len = simd_length(p)
        guard len > 1e-5 else { return p }
        return p * (1 + amount / len)
    }

    // Feature anchors (all derived from the surface function).
    static let eyeRadius: Float = 0.015
    static func eyeCenter(side: Float) -> SIMD3<Float> {
        let anchor = headPoint(side * 0.36, 0.10)
        return proud(anchor, -eyeRadius * 0.85)  // recess so ~3 mm bulges out
    }
    static let mouthAnchor: SIMD3<Float> = proud(headPoint(0, -0.42), 0.0012)
    static let jawHinge = SIMD3<Float>(0, mouthAnchor.y - 0.006, mouthAnchor.z - 0.045)
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

enum AvatarGeometry {
    // MARK: - Head & face

    static func headMesh() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-.pi, .pi, 48),
            vs: ramp(-1.35, 1.45, 40),
            point: { Stylized.headPoint($0, $1) },
            uv: { SIMD2(($0 / .pi + 1) / 2, ($1 + 1.35) / 2.8) },
            outwardFrom: .zero
        )
        return try mesh.resource(named: "head")
    }

    /// Eyeball sphere, vertices relative to the eye center. Front pole at +z;
    /// UV v runs 1 (front pole, iris) → 0 (back), matching VesperIris.png.
    static func eyeball() throws -> MeshResource {
        let r = Stylized.eyeRadius
        let mesh = GridMesh.build(
            us: ramp(0, 2 * .pi, 24),
            vs: ramp(0.02, .pi, 18),
            point: { phi, theta in
                SIMD3(
                    r * sin(theta) * cos(phi),
                    r * sin(theta) * sin(phi),
                    r * cos(theta)
                )
            },
            uv: { phi, theta in SIMD2(phi / (2 * .pi), 1 - theta / .pi) },
            outwardFrom: .zero
        )
        return try mesh.resource(named: "eye")
    }

    /// Spherical sector around an eye center (for lids and liner bands).
    /// Polar measured from +y (up), azimuth around y with 0 = +z (front).
    static func eyeSector(
        radius: Float,
        polar: ClosedRange<Float>,
        azimuth: ClosedRange<Float>
    ) throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(azimuth.lowerBound, azimuth.upperBound, 14),
            vs: ramp(polar.lowerBound, polar.upperBound, 8),
            point: { phi, theta in
                SIMD3(
                    radius * sin(theta) * sin(phi),
                    radius * cos(theta),
                    radius * sin(theta) * cos(phi)
                )
            },
            uv: { SIMD2($0, $1) },
            outwardFrom: .zero
        )
        return try mesh.resource(named: "eyeSector")
    }

    /// Arched brow — a surface-hugging ribbon; strong, slightly angular,
    /// peaking about two-thirds out (glam, colder). Vertices relative to the
    /// returned pivot so lift/roll act about the brow itself.
    static func brow(side: Float) throws -> (mesh: MeshResource, pivot: SIMD3<Float>) {
        func spine(_ t: Float) -> (alpha: Float, beta: Float) {
            let rise = min(1, t / 0.68)
            let fall = max(0, (t - 0.68) / 0.32)
            return (side * (0.10 + 0.55 * t), 0.20 + 0.155 * rise - 0.105 * fall)
        }
        let p = spine(0.45)
        let pivot = Stylized.proud(Stylized.headPoint(p.alpha, p.beta), 0.0018)
        let mesh = GridMesh.build(
            us: ramp(0, 1, 16),
            vs: ramp(-1, 1, 2),
            point: { t, w in
                let s = spine(t)
                let half = 0.05 * (1 - 0.62 * t) + 0.012
                return Stylized.proud(
                    Stylized.headPoint(s.alpha, s.beta + w * half * 0.5), 0.0018
                ) - pivot
            },
            uv: { SIMD2($0, ($1 + 1) / 2) },
            outwardFrom: -pivot
        )
        return (try mesh.resource(named: "brow"), pivot)
    }

    /// Half lip as a tapering tube (center → corner). Upper carries the
    /// cupid's bow; lower is fuller. Vertices relative to the mouth anchor.
    static func lipHalf(side: Float, upper: Bool) throws -> MeshResource {
        func spineY(_ t: Float) -> Float {
            if upper {
                let dip = 0.0014 * exp(-powf(t / 0.16, 2))
                return 0.0030 * (1 - t * t) - dip + 0.0004
            }
            return -0.0046 * (1 - t * t) - 0.0002
        }
        let mesh = GridMesh.build(
            us: ramp(0, 1, 14),
            vs: ramp(0, 2 * .pi, 10),
            point: { t, psi in
                let cx = side * 0.0215 * powf(t, 0.95)
                let cy = spineY(t)
                let cz: Float = 0.0016 - 0.0006 * t
                let r = (upper ? 0.0026 : 0.0036) * (1 - 0.5 * t) + 0.0008
                return SIMD3(cx, cy + r * cos(psi), cz + r * sin(psi) * 0.7)
            },
            uv: { SIMD2($0, $1 / (2 * .pi)) },
            rawNormals: true
        )
        return try mesh.resource(named: "lip")
    }

    /// Dark cavity behind the lips, revealed as the jaw drops.
    static func innerMouth() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-1, 1, 8),
            vs: ramp(-1, 1, 4),
            point: { SIMD3($0 * 0.017, $1 * 0.008 - 0.001, -0.005) },
            uv: { SIMD2(($0 + 1) / 2, ($1 + 1) / 2) }
        )
        return try mesh.resource(named: "innerMouth")
    }

    /// The signature winged-liner flick at the outer corner (static makeup).
    static func linerWing(side: Float) throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(0, 1, 4),
            vs: ramp(0, 1, 2),
            point: { t, s in
                SIMD3(
                    side * (0.0135 + 0.0085 * t),
                    -0.0005 + 0.0042 * t + s * 0.0018,
                    0.006 - 0.0035 * t
                )
            },
            uv: { SIMD2($0, $1) }
        )
        return try mesh.resource(named: "wing")
    }

    // MARK: - Neck, chest, silk

    static func neck() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(0, 2 * .pi, 20),
            vs: ramp(0, 1, 6),
            point: { phi, t in
                let flare = 1 + 0.35 * powf(t, 2.2)  // widens into the shoulders
                return SIMD3(
                    0.026 * flare * sin(phi),
                    0.02 - 0.13 * t,
                    0.030 * flare * cos(phi) - 0.004
                )
            },
            uv: { SIMD2($0 / (2 * .pi), $1) },
            outwardFrom: SIMD3(0, -0.05, -0.004)
        )
        return try mesh.resource(named: "neck")
    }

    /// Bare décolleté between the neck and the silk neckline.
    static func chestSkin() throws -> (mesh: MeshResource, center: SIMD3<Float>) {
        let center = SIMD3<Float>(0, -0.118, -0.008)
        let radii = SIMD3<Float>(0.125, 0.06, 0.048)
        let mesh = GridMesh.build(
            us: ramp(0, 1, 16),
            vs: ramp(0.18, 0.85, 8),
            point: { u, v in
                let phi = (u - 0.5) * .pi
                let theta = v * .pi
                return SIMD3(
                    radii.x * sin(theta) * sin(phi),
                    radii.y * cos(theta),
                    radii.z * sin(theta) * cos(phi)
                )
            },
            uv: { SIMD2($0, $1) },
            outwardFrom: .zero
        )
        return (try mesh.resource(named: "chestSkin"), center)
    }

    /// Merlot silk across the chest — put-together, draped, not disheveled.
    static func silkChest() throws -> (mesh: MeshResource, center: SIMD3<Float>) {
        let center = SIMD3<Float>(0, -0.185, -0.012)
        let radii = SIMD3<Float>(0.19, 0.075, 0.06)
        let mesh = GridMesh.build(
            us: ramp(0, 1, 20),
            vs: ramp(0.15, 0.85, 10),
            point: { u, v in
                let phi = (u - 0.5) * .pi
                let theta = v * .pi
                // soft drape folds
                let fold = 0.0016 * sin(u * 22) * sin(v * 6)
                return SIMD3(
                    radii.x * sin(theta) * sin(phi),
                    radii.y * cos(theta),
                    (radii.z + fold) * sin(theta) * cos(phi)
                )
            },
            uv: { SIMD2($0, $1) },
            outwardFrom: .zero
        )
        return (try mesh.resource(named: "silk"), center)
    }

    // MARK: - Hair (around and behind the head — never over the face)

    /// Scalp cap hugging the modeled skull (+4 mm), open over the face: the
    /// front stops well above the brows, sweeping lower toward the nape.
    static func hairScalp() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-.pi, .pi, 40),
            vs: ramp(0, 1, 12),
            point: { alpha, s in
                let span = 0.84 + (1 - cos(alpha)) * 0.45
                let beta = .pi / 2 - s * span
                return Stylized.proud(Stylized.headPoint(alpha, beta), 0.0045)
            },
            uv: { alpha, s in
                SIMD2((alpha / .pi + 1) / 2, 1 - (0.05 + 0.55 * s))
            },
            outwardFrom: .zero
        )
        return try mesh.resource(named: "hairScalp")
    }

    /// Front curtain: rooted at the scalp edge, tucked behind the (opaque)
    /// head across the face's height, emerging below the jaw to fall past the
    /// shoulders. It frames the face and can never veil it.
    static func hairCurtain(side: Float) throws -> MeshResource {
        let band: ClosedRange<Float> = side < 0 ? 0.03...0.45 : 0.55...0.97
        let mesh = GridMesh.build(
            us: ramp(0, 1, 6),
            vs: ramp(0, 1, 26),
            point: { s, t in
                let inner: Float = 0.048 + 0.028 * powf(t, 0.9)
                let width: Float = 0.040 + 0.024 * t
                return SIMD3(
                    side * (inner + s * width),
                    0.078 - 0.50 * t + s * 0.003,
                    0.008 - 0.020 * t - 0.030 * t * t - s * 0.022
                )
            },
            uv: { s, t in
                SIMD2(band.lowerBound + s * (band.upperBound - band.lowerBound), 1 - t)
            }
        )
        return try mesh.resource(named: "curtain")
    }

    /// Side fall behind the shoulders (torso space).
    static func hairFall(side: Float) throws -> MeshResource {
        let band: ClosedRange<Float> = side < 0 ? 0.10...0.48 : 0.52...0.90
        let mesh = GridMesh.build(
            us: ramp(0, 1, 6),
            vs: ramp(0, 1, 24),
            point: { s, t in
                SIMD3(
                    side * (0.058 + 0.024 * t + s * 0.046),
                    0.10 - 0.53 * t,
                    -0.030 - 0.030 * t - s * 0.016
                )
            },
            uv: { s, t in
                SIMD2(band.lowerBound + s * (band.upperBound - band.lowerBound), 1 - t)
            }
        )
        return try mesh.resource(named: "hairFall")
    }

    /// Wide sheet down the back to mid-back (torso space).
    static func hairBack() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-1, 1, 14),
            vs: ramp(0, 1, 16),
            point: { u, v in
                let half: Float = 0.135 + 0.075 * v
                return SIMD3(
                    u * half,
                    0.12 - 0.57 * v,
                    -0.060 - 0.02 * sin(v * .pi * 0.5) + 0.030 * u * u
                )
            },
            uv: { SIMD2(($0 + 1) / 2, 1 - $1) }
        )
        return try mesh.resource(named: "hairBack")
    }
}
