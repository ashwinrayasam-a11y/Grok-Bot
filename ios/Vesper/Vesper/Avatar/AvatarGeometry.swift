import Foundation
import RealityKit
import simd

/// Landmarks measured (in normalized texture coordinates, v top-down) from the
/// shipped portrait `VesperFace.png`. If the texture is regenerated, re-measure
/// these — everything else derives from them.
enum FaceMap {
    static let eyeV: Float = 0.322
    static let eyeLU: Float = 0.333
    static let eyeRU: Float = 0.661
    static let lipV: Float = 0.527
    static let headTopV: Float = 0.061
    static let hairlineV: Float = 0.135

    /// Shell size in meters, same 2:3 aspect as the texture.
    static let shellW: Float = 0.232
    static let shellH: Float = 0.348
    static let shellD: Float = 0.050

    /// The hinged-jaw cut, in texture space (chin only — not neck or chest).
    static let jawU: ClosedRange<Float> = 0.30...0.70
    static let jawV: ClosedRange<Float> = 0.527...0.660

    static func x(_ u: Float) -> Float { (u - 0.5) * shellW }
    static func y(_ v: Float) -> Float { (0.5 - v) * shellH }

    /// Gentle convex relief: a soft dome over the portrait with a raised nose.
    static func dome(_ u: Float, _ v: Float) -> Float {
        let dx = (u - 0.5) / 0.62
        let dy = (v - 0.42) / 0.74
        let base = max(0, 1 - dx * dx - dy * dy)
        let nu = (u - 0.5) / 0.06
        let nv = (v - 0.46) / 0.07
        let nose = exp(-(nu * nu + nv * nv)) * 0.22
        return shellD * (sqrt(base) + nose)
    }

    static func point(_ u: Float, _ v: Float) -> SIMD3<Float> {
        SIMD3(x(u), y(v), dome(u, v))
    }
}

/// Parametric grid mesh with analytic-ish normals (central differences).
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
        skipCell: ((Float, Float) -> Bool)? = nil
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
                if let center {
                    if dot(n, p - center) < 0 { n = -n }
                } else if n.z < 0 {
                    n = -n
                }
                let len = simd_length(n)
                mesh.normals.append(len > 1e-6 ? n / len : SIMD3(0, 0, 1))
                mesh.uvs.append(uv(u, v))
            }
        }
        for vi in 0..<(vs.count - 1) {
            for ui in 0..<(cols - 1) {
                if let skipCell, skipCell((us[ui] + us[ui + 1]) / 2, (vs[vi] + vs[vi + 1]) / 2) {
                    continue
                }
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

/// Inclusive linear ramp with `n` segments.
func ramp(_ a: Float, _ b: Float, _ n: Int) -> [Float] {
    (0...n).map { a + (b - a) * Float($0) / Float(n) }
}

/// RealityKit texture coordinates are bottom-left origin; the portrait's v is
/// top-down, hence the flip.
private func portraitUV(_ u: Float, _ v: Float) -> SIMD2<Float> {
    SIMD2(u, 1 - v)
}

enum AvatarGeometry {
    /// Static face shell (with a hole where the jaw hinges) + the jaw piece.
    static func faceShells() throws -> (upper: MeshResource, jaw: MeshResource) {
        let us = ramp(0, FaceMap.jawU.lowerBound, 10)
            + ramp(FaceMap.jawU.lowerBound, FaceMap.jawU.upperBound, 18).dropFirst()
            + ramp(FaceMap.jawU.upperBound, 1, 10).dropFirst()
        let vs = ramp(0, FaceMap.jawV.lowerBound, 26)
            + ramp(FaceMap.jawV.lowerBound, FaceMap.jawV.upperBound, 8).dropFirst()
            + ramp(FaceMap.jawV.upperBound, 1, 16).dropFirst()

        let upper = GridMesh.build(
            us: Array(us), vs: Array(vs),
            point: FaceMap.point,
            uv: portraitUV,
            skipCell: { FaceMap.jawU.contains($0) && FaceMap.jawV.contains($1) }
        )
        let jaw = GridMesh.build(
            us: ramp(FaceMap.jawU.lowerBound, FaceMap.jawU.upperBound, 18),
            vs: ramp(FaceMap.jawV.lowerBound, FaceMap.jawV.upperBound, 8),
            point: FaceMap.point,
            uv: portraitUV
        )
        return (try upper.resource(named: "face"), try jaw.resource(named: "jaw"))
    }

    /// Eyelid shell hugging the face dome, vertices relative to its top-edge
    /// pivot so animating scale.y closes it downward over the eye.
    static func eyelid(centerU: Float) throws -> (mesh: MeshResource, pivot: SIMD3<Float>) {
        let u0 = centerU - 0.085, u1 = centerU + 0.085
        let v0 = FaceMap.eyeV - 0.048, v1 = FaceMap.eyeV + 0.052
        let proud: Float = 0.0028
        let pivot = FaceMap.point(centerU, v0) + SIMD3(0, 0, proud)
        let mesh = GridMesh.build(
            us: ramp(u0, u1, 10),
            vs: ramp(v0, v1, 6),
            point: { FaceMap.point($0, $1) + SIMD3(0, 0, proud) - pivot },
            uv: { SIMD2(($0 - u0) / (u1 - u0), 1 - ($1 - v0) / (v1 - v0)) }
        )
        return (try mesh.resource(named: "lid"), pivot)
    }

    /// Dark backing revealed when the jaw opens.
    static func innerMouth() throws -> MeshResource {
        let z = FaceMap.dome(0.5, 0.56) - 0.018
        let mesh = GridMesh.build(
            us: ramp(0.36, 0.64, 2),
            vs: ramp(0.49, 0.62, 2),
            point: { SIMD3(FaceMap.x($0), FaceMap.y($1), z) },
            uv: { SIMD2($0, 1 - $1) }
        )
        return try mesh.resource(named: "innerMouth")
    }

    // MARK: - Hair
    //
    // Long, full, straight, dark — layered sheets all sampling the strand
    // texture `VesperHair.png` (striations run along v; the bottom of the
    // image is ragged strand-tip alpha, so lengths must map v = 1−t).

    /// Crown cap hugging the skull, reaching lower at the back. Samples the
    /// solid (non-tip) zone of the strand texture.
    static func hairCrown() throws -> MeshResource {
        let center = SIMD3<Float>(0, FaceMap.y(0.26), -0.016)
        let radii = SIMD3<Float>(0.098, 0.132, 0.082)
        let mesh = GridMesh.build(
            us: ramp(0, 1, 36),  // azimuth around the head
            vs: ramp(0.02, 1, 14),  // 0 = apex, 1 = brim
            point: { u, v in
                let phi = u * 2 * .pi  // 0 = front
                let maxPolar: Float = 1.26 + (1 - cos(phi)) * 0.38
                let theta = v * maxPolar
                return center + SIMD3(
                    radii.x * sin(theta) * sin(phi),
                    radii.y * cos(theta),
                    radii.z * sin(theta) * cos(phi)
                )
            },
            uv: { SIMD2($0, 1 - (0.02 + 0.5 * $1)) },
            outwardFrom: center
        )
        return try mesh.resource(named: "hairCrown")
    }

    /// Front curtain framing one side of the face, falling to mid-back.
    static func hairCurtain(side: Float) throws -> MeshResource {
        let band: ClosedRange<Float> = side < 0 ? 0.03...0.45 : 0.55...0.97
        let mesh = GridMesh.build(
            us: ramp(0, 1, 7),  // across the fall, inner → outer
            vs: ramp(0, 1, 26),  // along its length, root → tip
            point: { s, t in
                let inner: Float = 0.052 + 0.060 * powf(t, 0.85)
                let width: Float = 0.052 + 0.030 * t
                let x = side * (inner + s * width)
                let y = 0.152 - 0.52 * t + s * 0.004
                let z = 0.052 - 0.022 * t - 0.048 * t * t - s * 0.026
                return SIMD3(x, y, z)
            },
            uv: { s, t in
                SIMD2(band.lowerBound + s * (band.upperBound - band.lowerBound), 1 - t)
            }
        )
        return try mesh.resource(named: "curtain")
    }

    /// Side fall between the curtain and the back sheet — fills the gap so
    /// hair visibly drapes past the shoulders from the front.
    static func hairFall(side: Float) throws -> MeshResource {
        let band: ClosedRange<Float> = side < 0 ? 0.10...0.48 : 0.52...0.90
        let mesh = GridMesh.build(
            us: ramp(0, 1, 6),
            vs: ramp(0, 1, 24),
            point: { s, t in
                let x = side * (0.062 + 0.020 * t + s * 0.048)
                let y = 0.160 - 0.58 * t
                let z: Float = -0.020 - 0.032 * t - s * 0.018
                return SIMD3(x, y, z)
            },
            uv: { s, t in
                SIMD2(band.lowerBound + s * (band.upperBound - band.lowerBound), 1 - t)
            }
        )
        return try mesh.resource(named: "hairFall")
    }

    /// Wide sheet down the back, past the chest bottom in tall framing.
    static func hairBack() throws -> MeshResource {
        let mesh = GridMesh.build(
            us: ramp(-1, 1, 14),
            vs: ramp(0, 1, 16),
            point: { u, v in
                let half: Float = 0.165 + 0.075 * v
                let x = u * half
                let y = 0.168 - 0.64 * v
                let z: Float = -0.055 - 0.02 * sin(v * .pi * 0.5) + 0.032 * u * u
                return SIMD3(x, y, z)
            },
            uv: { SIMD2(($0 + 1) / 2, 1 - $1) }
        )
        return try mesh.resource(named: "hairBack")
    }

    // MARK: - Expression patches
    //
    // Small shells that hug the face dome and render the exact portrait
    // pixels they cover (pre-cropped, feather-edged textures) — invisible at
    // rest, and tiny eased offsets read as living skin. Same person, same
    // texture; nothing here swaps the face.

    /// Baked crop rectangles — must match the PNGs generated from the portrait.
    static let browLRect: (Float, Float, Float, Float) = (0.20, 0.47, 0.240, 0.335)
    static let browRRect: (Float, Float, Float, Float) = (0.53, 0.80, 0.240, 0.335)
    static let cornerLRect: (Float, Float, Float, Float) = (0.345, 0.475, 0.478, 0.600)
    static let cornerRRect: (Float, Float, Float, Float) = (0.525, 0.655, 0.478, 0.600)
    static let sneerRect: (Float, Float, Float, Float) = (0.41, 0.59, 0.430, 0.515)

    /// Patch mesh over a texture-space rect, vertices relative to its center
    /// pivot so rotation and scale happen about the region itself.
    static func facePatch(
        rect: (Float, Float, Float, Float),
        proud: Float
    ) throws -> (mesh: MeshResource, pivot: SIMD3<Float>) {
        let (u0, u1, v0, v1) = rect
        let pivot = FaceMap.point((u0 + u1) / 2, (v0 + v1) / 2) + SIMD3(0, 0, proud)
        let mesh = GridMesh.build(
            us: ramp(u0, u1, 8),
            vs: ramp(v0, v1, 6),
            point: { FaceMap.point($0, $1) + SIMD3(0, 0, proud) - pivot },
            uv: { SIMD2(($0 - u0) / (u1 - u0), 1 - ($1 - v0) / (v1 - v0)) }
        )
        return (try mesh.resource(named: "patch"), pivot)
    }

    /// Merlot silk across the chest, vertices relative to its center so
    /// breathing can scale it in place.
    static func silkChest() throws -> (mesh: MeshResource, center: SIMD3<Float>) {
        let center = SIMD3<Float>(0, -0.185, -0.012)
        let radii = SIMD3<Float>(0.19, 0.075, 0.06)
        let mesh = GridMesh.build(
            us: ramp(0, 1, 20),
            vs: ramp(0.15, 0.85, 10),
            point: { u, v in
                let phi = (u - 0.5) * .pi  // front half
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
        return (try mesh.resource(named: "silk"), center)
    }
}
