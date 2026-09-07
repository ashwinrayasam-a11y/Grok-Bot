import Foundation
import RealityKit
import UIKit

/// Per-member styling for the shared stylized rig: textures, tints, hair cut,
/// and stage-light colors. Vesper and Mika share bones, never a look.
struct AvatarStyle {
    var hairTexture: String
    var irisTexture: String
    var lipTint: UIColor
    var browTint: UIColor
    var keyWarm: UIColor   // key light at ease
    var keyCool: UIColor   // key light as the mood sharpens
    var bob: Bool          // jaw-length bob + fringe instead of mid-back falls

    static let vesper = AvatarStyle(
        hairTexture: "VesperHair",
        irisTexture: "VesperIris",
        lipTint: UIColor(red: 0.73, green: 0.50, blue: 0.49, alpha: 1),
        browTint: UIColor(red: 0.243, green: 0.180, blue: 0.141, alpha: 1),
        keyWarm: UIColor(red: 0.77, green: 0.36, blue: 0.15, alpha: 1),
        keyCool: UIColor(red: 0.66, green: 0.30, blue: 0.30, alpha: 1),
        bob: false
    )

    static let mika = AvatarStyle(
        hairTexture: "MikaHair",
        irisTexture: "MikaIris",
        lipTint: UIColor(red: 0.80, green: 0.47, blue: 0.43, alpha: 1),
        browTint: UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1),
        keyWarm: UIColor(red: 0.28, green: 0.74, blue: 0.71, alpha: 1),
        keyCool: UIColor(red: 0.32, green: 0.48, blue: 0.66, alpha: 1),
        bob: true
    )
}

/// A stylized bust: swept-profile skull with a real V-jaw, layered graphic
/// eyes (almond sclera, translating iris discs with catch-lights, bold winged
/// liner), filled lips, and framing hair. Original design — no photo
/// textures, no borrowed companions. The style struct dresses it per member.
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

    private let keyWarm: UIColor
    private let keyCool: UIColor

    init(style: AvatarStyle = .vesper) throws {
        keyWarm = style.keyWarm
        keyCool = style.keyCool
        let irisTexture = try TextureResource.load(named: style.irisTexture)
        let hairTexture = try TextureResource.load(named: style.hairTexture)

        // --- Materials (colors keyed to the blonde look target) ---
        var skin = PhysicallyBasedMaterial()
        skin.baseColor = .init(tint: UIColor(red: 0.95, green: 0.865, blue: 0.815, alpha: 1))
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

        var makeup = PhysicallyBasedMaterial()  // liner + lashes stay dark, smoky
        makeup.baseColor = .init(tint: UIColor(red: 0.098, green: 0.071, blue: 0.055, alpha: 1))
        makeup.roughness = 0.35
        makeup.metallic = 0.0
        makeup.faceCulling = .none

        var browTint = PhysicallyBasedMaterial()
        browTint.baseColor = .init(tint: style.browTint)
        browTint.roughness = 0.42
        browTint.metallic = 0.0
        browTint.faceCulling = .none

        var lidShadow = PhysicallyBasedMaterial()  // smoky eyeshadow tone
        lidShadow.baseColor = .init(tint: UIColor(red: 0.55, green: 0.42, blue: 0.40, alpha: 1))
        lidShadow.roughness = 0.5
        lidShadow.metallic = 0.0
        lidShadow.faceCulling = .none

        var lip = PhysicallyBasedMaterial()
        lip.baseColor = .init(tint: style.lipTint)
        lip.roughness = 0.30
        lip.metallic = 0.0
        lip.sheen = .init(tint: UIColor(red: 0.86, green: 0.66, blue: 0.64, alpha: 1))
        lip.faceCulling = .none

        var teethTint = PhysicallyBasedMaterial()
        teethTint.baseColor = .init(tint: UIColor(red: 0.91, green: 0.88, blue: 0.84, alpha: 1))
        teethTint.roughness = 0.4
        teethTint.metallic = 0.0

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
        browL = Self.handle(mesh: browBuiltL.mesh, material: browTint, at: browBuiltL.pivot)
        browR = Self.handle(mesh: browBuiltR.mesh, material: browTint, at: browBuiltR.pivot)
        head.addChild(browL.pivot)
        head.addChild(browR.pivot)

        // --- Mouth ---
        let mouth = Stylized.mouthAnchor
        let cavity = ModelEntity(mesh: try AvatarGeometry.innerMouth(), materials: [cavityMaterial])
        cavity.position = mouth
        head.addChild(cavity)
        // Upper teeth, just visible through the resting part of the lips.
        let teeth = ModelEntity(mesh: try AvatarGeometry.teeth(), materials: [teethTint])
        teeth.position = mouth
        head.addChild(teeth)

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
        let curtainLength: Float = style.bob ? 0.185 : 0.52
        let curtainL = Self.pivoted(
            try AvatarGeometry.hairCurtain(side: -1, length: curtainLength, drape: !style.bob),
            material: hair,
            at: SIMD3(-0.048, 0.062, 0.006)
        )
        let curtainR = Self.pivoted(
            try AvatarGeometry.hairCurtain(side: 1, length: curtainLength, drape: !style.bob),
            material: hair,
            at: SIMD3(0.048, 0.062, 0.006)
        )
        head.addChild(curtainL)
        head.addChild(curtainR)
        if style.bob {
            head.addChild(ModelEntity(mesh: try AvatarGeometry.hairFringe(), materials: [hair]))
        }

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

        if style.bob {
            // Short bob skirt behind the head; moves with it.
            let bobBack = Self.pivoted(
                try AvatarGeometry.hairBack(topY: 0.05, drop: 0.20, half: 0.10, z: -0.058),
                material: hair, at: SIMD3(0, 0.05, -0.058)
            )
            head.addChild(bobBack)
            hairPieces = [
                HairPiece(pivot: curtainL, follow: 0.50, tau: 0.40),
                HairPiece(pivot: curtainR, follow: 0.55, tau: 0.44),
                HairPiece(pivot: bobBack, follow: 0.35, tau: 0.60),
            ]
        } else {
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
        }

        torso.addChild(figure)
        torso.addChild(chest)
        torso.addChild(strapL)
        torso.addChild(strapR)
        torso.addChild(neckPivot)
        root.addChild(torso)

        // --- Stage: lights + camera ---
        keyLight.light.color = keyWarm
        keyLight.light.intensity = 16000
        keyLight.light.attenuationRadius = 4
        keyLight.position = [0.28, 0.18, 0.5]

        rimLight.light.color = keyCool
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
        keyLight.light.color = Self.blend(keyWarm, keyCool, Float(chill))
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
