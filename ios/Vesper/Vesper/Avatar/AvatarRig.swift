import Foundation
import RealityKit
import UIKit

/// Vesper's stylized bust: original modeled geometry (no photo shells) with a
/// simple transform rig — eyeballs, lids, brows, and lip halves each hang on
/// their own pivot so the director can act with them continuously.
final class AvatarRig {
    /// A hair layer that trails the head with its own lag and drift.
    struct HairPiece {
        let pivot: Entity
        let follow: Double
        let tau: Double
    }

    /// A feature on its own pivot, remembering its rest position.
    struct RigHandle {
        let pivot: Entity
        let home: SIMD3<Float>
    }

    /// Everything to anchor into the scene.
    let stage = Entity()

    // Animation handles (the director writes these every frame).
    let root = Entity()        // weight shift / lean
    let torso = Entity()
    let neckPivot = Entity()   // head yaw / pitch / roll about the neck
    let head = Entity()
    let jawPivot = Entity()    // carries the lower lip while she speaks
    let eyeL = Entity()        // gaze
    let eyeR = Entity()
    let lidL = Entity()        // blink / droop (rotation over the eyeball)
    let lidR = Entity()
    let browL: RigHandle
    let browR: RigHandle
    let lipUL = Entity()       // lip halves, pivoted at the mouth center —
    let lipUR = Entity()       // corner lift/curl is a roll of each half
    let lipLL = Entity()
    let lipLR = Entity()
    let chest: ModelEntity     // silk, breathing
    let hairPieces: [HairPiece]
    let keyLight = PointLight()
    let rimLight = PointLight()
    let camera = PerspectiveCamera()

    private static let ember = UIColor(red: 0.77, green: 0.36, blue: 0.15, alpha: 1)
    private static let rose = UIColor(red: 0.66, green: 0.30, blue: 0.30, alpha: 1)

    init() throws {
        let irisTexture = try TextureResource.load(named: "VesperIris")
        let hairTexture = try TextureResource.load(named: "VesperHair")

        // --- Materials (colors keyed to the locked reference) ---
        var skin = PhysicallyBasedMaterial()
        skin.baseColor = .init(tint: UIColor(red: 0.94, green: 0.85, blue: 0.78, alpha: 1))
        skin.roughness = 0.55
        skin.metallic = 0.0

        var eye = PhysicallyBasedMaterial()
        eye.baseColor = .init(texture: .init(irisTexture))
        eye.roughness = 0.12
        eye.metallic = 0.0

        var makeup = PhysicallyBasedMaterial()  // liner, lashes, brows
        makeup.baseColor = .init(tint: UIColor(red: 0.082, green: 0.059, blue: 0.043, alpha: 1))
        makeup.roughness = 0.35
        makeup.metallic = 0.0
        makeup.faceCulling = .none

        var lip = PhysicallyBasedMaterial()  // merlot matte
        lip.baseColor = .init(tint: UIColor(red: 0.37, green: 0.12, blue: 0.19, alpha: 1))
        lip.roughness = 0.38
        lip.metallic = 0.0
        lip.faceCulling = .none

        var hair = PhysicallyBasedMaterial()
        hair.baseColor = .init(texture: .init(hairTexture))
        hair.roughness = 0.40
        hair.metallic = 0.0
        hair.blending = .transparent(opacity: .init(texture: .init(hairTexture)))
        hair.faceCulling = .none

        var silk = PhysicallyBasedMaterial()
        silk.baseColor = .init(tint: UIColor(red: 0.353, green: 0.106, blue: 0.180, alpha: 1))
        silk.roughness = 0.30
        silk.metallic = 0.0
        silk.sheen = .init(tint: UIColor(red: 0.75, green: 0.35, blue: 0.45, alpha: 1))

        let innerMouth = UnlitMaterial(color: UIColor(red: 0.11, green: 0.03, blue: 0.04, alpha: 1))

        // --- Head & face ---
        head.addChild(ModelEntity(mesh: try AvatarGeometry.headMesh(), materials: [skin]))

        let eyeMesh = try AvatarGeometry.eyeball()
        let lidRadius = Stylized.eyeRadius + 0.002
        let lidMesh = try AvatarGeometry.eyeSector(
            radius: lidRadius, polar: 0.32...1.06, azimuth: -1.15...1.15
        )
        let lashMesh = try AvatarGeometry.eyeSector(
            radius: lidRadius + 0.0006, polar: 0.99...1.08, azimuth: -1.18...1.18
        )
        let lowerLidMesh = try AvatarGeometry.eyeSector(
            radius: lidRadius, polar: 1.82...2.16, azimuth: -0.95...0.95
        )
        let lowerLinerMesh = try AvatarGeometry.eyeSector(
            radius: lidRadius + 0.0004, polar: 1.78...1.86, azimuth: -1.0...1.0
        )

        for side: Float in [-1, 1] {
            let center = Stylized.eyeCenter(side: side)

            let eyePivot = side < 0 ? eyeL : eyeR
            eyePivot.position = center
            eyePivot.addChild(ModelEntity(mesh: eyeMesh, materials: [eye]))
            head.addChild(eyePivot)

            let lidPivot = side < 0 ? lidL : lidR
            lidPivot.position = center
            lidPivot.addChild(ModelEntity(mesh: lidMesh, materials: [skin]))
            lidPivot.addChild(ModelEntity(mesh: lashMesh, materials: [makeup]))
            head.addChild(lidPivot)

            let lowerLid = ModelEntity(mesh: lowerLidMesh, materials: [skin])
            lowerLid.position = center
            head.addChild(lowerLid)
            let lowerLiner = ModelEntity(mesh: lowerLinerMesh, materials: [makeup])
            lowerLiner.position = center
            head.addChild(lowerLiner)

            let wing = ModelEntity(mesh: try AvatarGeometry.linerWing(side: side), materials: [makeup])
            wing.position = center
            head.addChild(wing)
        }

        let browBuiltL = try AvatarGeometry.brow(side: -1)
        let browBuiltR = try AvatarGeometry.brow(side: 1)
        browL = Self.handle(mesh: browBuiltL.mesh, material: makeup, at: browBuiltL.pivot)
        browR = Self.handle(mesh: browBuiltR.mesh, material: makeup, at: browBuiltR.pivot)
        head.addChild(browL.pivot)
        head.addChild(browR.pivot)

        // Mouth: upper halves pivot at the mouth anchor; lower halves ride the
        // jaw hinge and still roll about the anchor for corner acting.
        let mouth = Stylized.mouthAnchor
        let cavity = ModelEntity(mesh: try AvatarGeometry.innerMouth(), materials: [innerMouth])
        cavity.position = mouth
        head.addChild(cavity)

        lipUL.position = mouth
        lipUL.addChild(ModelEntity(mesh: try AvatarGeometry.lipHalf(side: -1, upper: true), materials: [lip]))
        lipUR.position = mouth
        lipUR.addChild(ModelEntity(mesh: try AvatarGeometry.lipHalf(side: 1, upper: true), materials: [lip]))
        head.addChild(lipUL)
        head.addChild(lipUR)

        jawPivot.position = Stylized.jawHinge
        lipLL.position = mouth - Stylized.jawHinge
        lipLL.addChild(ModelEntity(mesh: try AvatarGeometry.lipHalf(side: -1, upper: false), materials: [lip]))
        lipLR.position = mouth - Stylized.jawHinge
        lipLR.addChild(ModelEntity(mesh: try AvatarGeometry.lipHalf(side: 1, upper: false), materials: [lip]))
        jawPivot.addChild(lipLL)
        jawPivot.addChild(lipLR)
        head.addChild(jawPivot)

        // --- Hair: scalp cap rides the head; lengths hang on sway pivots ---
        head.addChild(ModelEntity(mesh: try AvatarGeometry.hairScalp(), materials: [hair]))
        let curtainL = Self.pivoted(
            try AvatarGeometry.hairCurtain(side: -1), material: hair,
            at: SIMD3(-0.048, 0.075, 0.008)
        )
        let curtainR = Self.pivoted(
            try AvatarGeometry.hairCurtain(side: 1), material: hair,
            at: SIMD3(0.048, 0.075, 0.008)
        )
        head.addChild(curtainL)
        head.addChild(curtainR)

        // Head content sits above the neck joint.
        let neckJoint = SIMD3<Float>(0, -0.045, -0.008)
        neckPivot.position = neckJoint
        head.position = SIMD3(0, 0.055, 0) - neckJoint
        neckPivot.addChild(head)

        // --- Torso ---
        let neck = ModelEntity(mesh: try AvatarGeometry.neck(), materials: [skin])
        let chestBuilt = try AvatarGeometry.chestSkin()
        let decollete = ModelEntity(mesh: chestBuilt.mesh, materials: [skin])
        decollete.position = chestBuilt.center
        let silkBuilt = try AvatarGeometry.silkChest()
        chest = ModelEntity(mesh: silkBuilt.mesh, materials: [silk])
        chest.position = silkBuilt.center

        let fallL = Self.pivoted(
            try AvatarGeometry.hairFall(side: -1), material: hair, at: SIMD3(-0.08, 0.10, -0.03)
        )
        let fallR = Self.pivoted(
            try AvatarGeometry.hairFall(side: 1), material: hair, at: SIMD3(0.08, 0.10, -0.03)
        )
        let back = Self.pivoted(
            try AvatarGeometry.hairBack(), material: hair, at: SIMD3(0, 0.12, -0.06)
        )

        hairPieces = [
            HairPiece(pivot: curtainL, follow: 0.40, tau: 0.50),
            HairPiece(pivot: curtainR, follow: 0.45, tau: 0.55),
            HairPiece(pivot: fallL, follow: 0.30, tau: 0.72),
            HairPiece(pivot: fallR, follow: 0.35, tau: 0.78),
            HairPiece(pivot: back, follow: 0.25, tau: 0.95),
        ]

        torso.addChild(back)
        torso.addChild(fallL)
        torso.addChild(fallR)
        torso.addChild(neck)
        torso.addChild(decollete)
        torso.addChild(chest)
        torso.addChild(neckPivot)
        root.addChild(torso)

        // --- Stage: lights + camera ---
        keyLight.light.color = Self.ember
        keyLight.light.intensity = 16000
        keyLight.light.attenuationRadius = 4
        keyLight.position = [0.28, 0.18, 0.5]

        rimLight.light.color = Self.rose
        rimLight.light.intensity = 9000
        rimLight.light.attenuationRadius = 4
        rimLight.position = [-0.35, 0.25, -0.35]

        let fill = DirectionalLight()
        fill.light.color = UIColor(red: 0.55, green: 0.57, blue: 0.66, alpha: 1)
        fill.light.intensity = 450
        fill.look(at: [0, 0, 0], from: [0.1, 0.3, 1], relativeTo: nil)

        camera.camera.fieldOfViewInDegrees = 23
        camera.position = [0, 0.06, 0.44]

        stage.addChild(root)
        stage.addChild(keyLight)
        stage.addChild(rimLight)
        stage.addChild(fill)
        stage.addChild(camera)
    }

    /// Continuous mood tint: ember warmth cooling toward rose as her edge
    /// sharpens. Called every frame with an already-smoothed 0…1 value.
    func tintLights(chill: Double, glow: Double) {
        keyLight.light.color = Self.blend(Self.ember, Self.rose, Float(chill))
        keyLight.light.intensity = Float(12000 + glow * 9000)
        rimLight.light.intensity = Float(6000 + chill * 7000)
    }

    private static func handle(
        mesh: MeshResource,
        material: RealityKit.Material,
        at pivot: SIMD3<Float>
    ) -> RigHandle {
        let entity = Entity()
        entity.position = pivot
        entity.addChild(ModelEntity(mesh: mesh, materials: [material]))
        return RigHandle(pivot: entity, home: pivot)
    }

    private static func pivoted(
        _ mesh: MeshResource,
        material: RealityKit.Material,
        at pivot: SIMD3<Float>
    ) -> Entity {
        let holder = Entity()
        holder.position = pivot
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.position = -pivot
        holder.addChild(model)
        return holder
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ t: Float) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let k = CGFloat(min(1, max(0, t)))
        return UIColor(
            red: ar + (br - ar) * k,
            green: ag + (bg - ag) * k,
            blue: ab + (bb - ab) * k,
            alpha: 1
        )
    }
}
