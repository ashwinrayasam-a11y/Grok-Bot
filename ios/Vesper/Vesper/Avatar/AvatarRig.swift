import Foundation
import RealityKit
import UIKit

/// Vesper's stylized bust, v2: swept-profile skull with a real V-jaw, layered
/// graphic eyes (almond sclera, translating iris discs with catch-lights,
/// bold winged liner), filled merlot lips, and framing hair. Original design —
/// colors keyed to the locked reference, no photo textures, no borrowed
/// companions.
final class AvatarRig {
    struct HairPiece {
        let pivot: Entity
        let follow: Double
        let tau: Double
    }

    struct RigHandle {
        let pivot: Entity
        let home: SIMD3<Float>
    }

    /// Everything to anchor into the scene.
    let stage = Entity()

    // Animation handles (the director writes these every frame).
    let root = Entity()
    let torso = Entity()
    let neckPivot = Entity()
    let head = Entity()
    let jawPivot = Entity()
    let irisL = Entity()       // gaze = translating the iris in the almond
    let irisR = Entity()
    let lidL = Entity()        // blink = swinging the lid plate down flush
    let lidR = Entity()
    let browL: RigHandle
    let browR: RigHandle
    let lipUL = Entity()
    let lipUR = Entity()
    let lipLL = Entity()
    let lipLR = Entity()
    let chest: ModelEntity
    let hairPieces: [HairPiece]
    let keyLight = PointLight()
    let rimLight = PointLight()
    let camera = PerspectiveCamera()

    /// Iris rest offset in eye-root space (proud of the sclera bulge).
    static let irisHome = SIMD3<Float>(0, 0, 0.0045)

    /// Silk camisole rest position — the director breathes it around this.
    static let chestHome = SIMD3<Float>(0, -0.15, 0)

    private static let ember = UIColor(red: 0.77, green: 0.36, blue: 0.15, alpha: 1)
    private static let rose = UIColor(red: 0.66, green: 0.30, blue: 0.30, alpha: 1)

    init() throws {
        let irisTexture = try TextureResource.load(named: "VesperIris")
        let hairTexture = try TextureResource.load(named: "VesperHair")

        // --- Materials ---
        var skin = PhysicallyBasedMaterial()
        skin.baseColor = .init(tint: UIColor(red: 0.94, green: 0.85, blue: 0.78, alpha: 1))
        skin.roughness = 0.55
        skin.metallic = 0.0

        var sclera = PhysicallyBasedMaterial()
        sclera.baseColor = .init(tint: UIColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1))
        sclera.roughness = 0.25
        sclera.metallic = 0.0
        sclera.faceCulling = .none

        var iris = PhysicallyBasedMaterial()
        iris.baseColor = .init(texture: .init(irisTexture))
        iris.roughness = 0.18
        iris.metallic = 0.0
        iris.blending = .transparent(opacity: .init(texture: .init(irisTexture)))
        iris.faceCulling = .none

        let glint = UnlitMaterial(color: UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1))

        var makeup = PhysicallyBasedMaterial()  // liner, lashes, brows
        makeup.baseColor = .init(tint: UIColor(red: 0.075, green: 0.055, blue: 0.042, alpha: 1))
        makeup.roughness = 0.35
        makeup.metallic = 0.0
        makeup.faceCulling = .none

        var lidShadow = PhysicallyBasedMaterial()  // smoky eyeshadow tone
        lidShadow.baseColor = .init(tint: UIColor(red: 0.55, green: 0.42, blue: 0.40, alpha: 1))
        lidShadow.roughness = 0.5
        lidShadow.metallic = 0.0
        lidShadow.faceCulling = .none

        var lip = PhysicallyBasedMaterial()
        lip.baseColor = .init(tint: UIColor(red: 0.38, green: 0.12, blue: 0.19, alpha: 1))
        lip.roughness = 0.33
        lip.metallic = 0.0
        lip.sheen = .init(tint: UIColor(red: 0.55, green: 0.25, blue: 0.33, alpha: 1))
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

        let cavityMaterial = UnlitMaterial(color: UIColor(red: 0.11, green: 0.03, blue: 0.04, alpha: 1))

        // --- Skull, nose ---
        head.addChild(ModelEntity(mesh: try AvatarGeometry.headMesh(), materials: [skin]))
        head.addChild(ModelEntity(mesh: try AvatarGeometry.nose(), materials: [skin]))

        // --- Eyes: layered graphic assemblies ---
        for side: Float in [-1, 1] {
            let eyeRoot = Entity()
            eyeRoot.position = Stylized.eyeCenter(side: side)
            // Cat-eye tilt: outer corners up.
            eyeRoot.orientation = simd_quatf(angle: side * Stylized.eyeTilt, axis: [0, 0, 1])

            eyeRoot.addChild(ModelEntity(mesh: try AvatarGeometry.sclera(side: side), materials: [sclera]))

            let irisPivot = side < 0 ? irisL : irisR
            irisPivot.position = Self.irisHome
            irisPivot.addChild(ModelEntity(mesh: try AvatarGeometry.irisDisc(), materials: [iris]))
            let sparkle = ModelEntity(mesh: try AvatarGeometry.glint(), materials: [glint])
            sparkle.position = SIMD3(-side * 0.0032, 0.0034, 0.0008)
            irisPivot.addChild(sparkle)
            eyeRoot.addChild(irisPivot)

            eyeRoot.addChild(ModelEntity(mesh: try AvatarGeometry.lashBand(side: side), materials: [makeup]))
            eyeRoot.addChild(ModelEntity(mesh: try AvatarGeometry.lowerLiner(side: side), materials: [makeup]))

            let lidBuilt = try AvatarGeometry.lidPlate(side: side)
            let lidPivot = side < 0 ? lidL : lidR
            lidPivot.position = lidBuilt.hinge
            lidPivot.addChild(ModelEntity(mesh: lidBuilt.mesh, materials: [lidShadow]))
            eyeRoot.addChild(lidPivot)

            head.addChild(eyeRoot)
        }

        // --- Brows ---
        let browBuiltL = try AvatarGeometry.brow(side: -1)
        let browBuiltR = try AvatarGeometry.brow(side: 1)
        browL = Self.handle(mesh: browBuiltL.mesh, material: makeup, at: browBuiltL.pivot)
        browR = Self.handle(mesh: browBuiltR.mesh, material: makeup, at: browBuiltR.pivot)
        head.addChild(browL.pivot)
        head.addChild(browR.pivot)

        // --- Mouth ---
        let mouth = Stylized.mouthAnchor
        let cavity = ModelEntity(mesh: try AvatarGeometry.innerMouth(), materials: [cavityMaterial])
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

        // --- Hair on the head ---
        head.addChild(ModelEntity(mesh: try AvatarGeometry.hairScalp(), materials: [hair]))
        let curtainL = Self.pivoted(
            try AvatarGeometry.hairCurtain(side: -1), material: hair,
            at: SIMD3(-0.048, 0.062, 0.006)
        )
        let curtainR = Self.pivoted(
            try AvatarGeometry.hairCurtain(side: 1), material: hair,
            at: SIMD3(0.048, 0.062, 0.006)
        )
        head.addChild(curtainL)
        head.addChild(curtainR)

        // Head content sits above the neck joint.
        let neckJoint = SIMD3<Float>(0, -0.045, -0.008)
        neckPivot.position = neckJoint
        head.position = SIMD3(0, 0.055, 0) - neckJoint
        neckPivot.addChild(head)

        // --- Body: swept figure (neck, shoulders, bust) in a silk camisole ---
        let figure = ModelEntity(mesh: try AvatarGeometry.torsoSkin(), materials: [skin])
        let silkBuilt = try AvatarGeometry.torsoSilk()
        chest = ModelEntity(mesh: silkBuilt.mesh, materials: [silk])
        chest.position = silkBuilt.center
        let strapL = ModelEntity(mesh: try AvatarGeometry.silkStrap(side: -1), materials: [silk])
        let strapR = ModelEntity(mesh: try AvatarGeometry.silkStrap(side: 1), materials: [silk])

        let fallL = Self.pivoted(
            try AvatarGeometry.hairFall(side: -1), material: hair, at: SIMD3(-0.10, 0.10, -0.055)
        )
        let fallR = Self.pivoted(
            try AvatarGeometry.hairFall(side: 1), material: hair, at: SIMD3(0.10, 0.10, -0.055)
        )
        let back = Self.pivoted(
            try AvatarGeometry.hairBack(), material: hair, at: SIMD3(0, 0.12, -0.072)
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
        torso.addChild(figure)
        torso.addChild(chest)
        torso.addChild(strapL)
        torso.addChild(strapR)
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

        camera.camera.fieldOfViewInDegrees = 22
        camera.position = [0, 0.055, 0.44]

        stage.addChild(root)
        stage.addChild(keyLight)
        stage.addChild(rimLight)
        stage.addChild(fill)
        stage.addChild(camera)
    }

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
