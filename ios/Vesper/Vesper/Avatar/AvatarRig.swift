import Foundation
import RealityKit
import UIKit

/// Vesper's parametric bust: entity hierarchy, materials, lights, camera.
/// All geometry is generated in code and textured with the locked portrait —
/// nothing here depends on external character assets.
final class AvatarRig {
    /// A hair layer that trails the head with its own lag and drift.
    struct HairPiece {
        let pivot: Entity
        let follow: Double  // how much of the head's motion it inherits
        let tau: Double     // spring lag — longer = heavier, softer
    }

    /// A deformable face region: the pivot sits at the region's center on the
    /// dome; the mesh renders the exact portrait pixels it covers.
    struct FacePatch {
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
    let jawPivot = Entity()    // chin drop while she speaks
    let lidL: ModelEntity
    let lidR: ModelEntity
    let chest: ModelEntity     // silk, breathing
    let hairPieces: [HairPiece]
    let browL: FacePatch
    let browR: FacePatch
    let cornerL: FacePatch
    let cornerR: FacePatch
    let sneer: FacePatch
    let keyLight = PointLight()
    let rimLight = PointLight()
    let camera = PerspectiveCamera()

    private static let ember = UIColor(red: 0.77, green: 0.36, blue: 0.15, alpha: 1)
    private static let rose = UIColor(red: 0.66, green: 0.30, blue: 0.30, alpha: 1)

    init() throws {
        let faceTexture = try TextureResource.load(named: "VesperFace")
        let lidTexture = try TextureResource.load(named: "VesperLid")
        let hairTexture = try TextureResource.load(named: "VesperHair")

        var skin = PhysicallyBasedMaterial()
        skin.baseColor = .init(texture: .init(faceTexture))
        skin.roughness = 0.62
        skin.metallic = 0.0
        skin.blending = .transparent(opacity: .init(texture: .init(faceTexture)))
        skin.faceCulling = .none

        var lidSkin = PhysicallyBasedMaterial()
        lidSkin.baseColor = .init(texture: .init(lidTexture))
        lidSkin.roughness = 0.6
        lidSkin.metallic = 0.0
        lidSkin.faceCulling = .none

        // Strand-striated texture with ragged tip alpha — this is what makes
        // it read as hair instead of dark cards vanishing into the ink UI.
        var hair = PhysicallyBasedMaterial()
        hair.baseColor = .init(texture: .init(hairTexture))
        hair.roughness = 0.38
        hair.metallic = 0.0
        hair.blending = .transparent(opacity: .init(texture: .init(hairTexture)))
        hair.faceCulling = .none

        var silk = PhysicallyBasedMaterial()
        silk.baseColor = .init(tint: UIColor(red: 0.353, green: 0.106, blue: 0.180, alpha: 1))
        silk.roughness = 0.30
        silk.metallic = 0.0
        silk.sheen = .init(tint: UIColor(red: 0.75, green: 0.35, blue: 0.45, alpha: 1))
        silk.faceCulling = .none

        let innerMouth = UnlitMaterial(color: UIColor(red: 0.11, green: 0.03, blue: 0.04, alpha: 1))

        // --- Head content ---
        let shells = try AvatarGeometry.faceShells()
        let face = ModelEntity(mesh: shells.upper, materials: [skin])
        let jaw = ModelEntity(mesh: shells.jaw, materials: [skin])
        let mouth = ModelEntity(mesh: try AvatarGeometry.innerMouth(), materials: [innerMouth])

        // Jaw hinge sits deep in the head at ear height; the child offset puts
        // the mesh in pivot space so rotation swings the chin down and back.
        let jawHinge = SIMD3<Float>(0, FaceMap.y(0.545), -0.005)
        jaw.position = -jawHinge
        jawPivot.position = jawHinge
        jawPivot.addChild(jaw)

        let lidLeft = try AvatarGeometry.eyelid(centerU: FaceMap.eyeLU)
        let lidRight = try AvatarGeometry.eyelid(centerU: FaceMap.eyeRU)
        lidL = ModelEntity(mesh: lidLeft.mesh, materials: [lidSkin])
        lidL.position = lidLeft.pivot
        lidR = ModelEntity(mesh: lidRight.mesh, materials: [lidSkin])
        lidR.position = lidRight.pivot

        // Crown rides the head rigidly; every hanging length gets a sway pivot
        // at its root so the director can give it lagged follow-through.
        let crown = ModelEntity(mesh: try AvatarGeometry.hairCrown(), materials: [hair])
        let curtainL = Self.pivoted(
            try AvatarGeometry.hairCurtain(side: -1), material: hair,
            at: SIMD3(-0.05, 0.15, 0.02)
        )
        let curtainR = Self.pivoted(
            try AvatarGeometry.hairCurtain(side: 1), material: hair,
            at: SIMD3(0.05, 0.15, 0.02)
        )

        // Expression patches — exact portrait crops on the same dome.
        browL = try Self.makePatch(
            rect: AvatarGeometry.browLRect, proud: 0.0012, textureNamed: "VesperBrowL"
        )
        browR = try Self.makePatch(
            rect: AvatarGeometry.browRRect, proud: 0.0012, textureNamed: "VesperBrowR"
        )
        cornerL = try Self.makePatch(
            rect: AvatarGeometry.cornerLRect, proud: 0.0014, textureNamed: "VesperMouthL"
        )
        cornerR = try Self.makePatch(
            rect: AvatarGeometry.cornerRRect, proud: 0.0014, textureNamed: "VesperMouthR"
        )
        sneer = try Self.makePatch(
            rect: AvatarGeometry.sneerRect, proud: 0.0010, textureNamed: "VesperSneer"
        )

        head.addChild(face)
        head.addChild(mouth)
        head.addChild(jawPivot)
        head.addChild(lidL)
        head.addChild(lidR)
        head.addChild(crown)
        head.addChild(curtainL)
        head.addChild(curtainR)
        head.addChild(browL.pivot)
        head.addChild(browR.pivot)
        head.addChild(cornerL.pivot)
        head.addChild(cornerR.pivot)
        head.addChild(sneer.pivot)

        // Neck pivot trick: pivot at the neck, content offset back, so head
        // rotations happen about the neck rather than the shell center.
        let neck = SIMD3<Float>(0, FaceMap.y(0.60), -0.01)
        neckPivot.position = neck
        head.position = -neck
        neckPivot.addChild(head)

        // --- Torso content ---
        let silkParts = try AvatarGeometry.silkChest()
        chest = ModelEntity(mesh: silkParts.mesh, materials: [silk])
        chest.position = silkParts.center

        // Lengths that rest toward the shoulders live on the torso so they
        // trail head turns instead of riding them rigidly.
        let fallL = Self.pivoted(
            try AvatarGeometry.hairFall(side: -1), material: hair,
            at: SIMD3(-0.085, 0.16, -0.03)
        )
        let fallR = Self.pivoted(
            try AvatarGeometry.hairFall(side: 1), material: hair,
            at: SIMD3(0.085, 0.16, -0.03)
        )
        let back = Self.pivoted(
            try AvatarGeometry.hairBack(), material: hair,
            at: SIMD3(0, 0.165, -0.05)
        )

        hairPieces = [
            HairPiece(pivot: curtainL, follow: 0.55, tau: 0.50),
            HairPiece(pivot: curtainR, follow: 0.60, tau: 0.55),
            HairPiece(pivot: fallL, follow: 0.40, tau: 0.72),
            HairPiece(pivot: fallR, follow: 0.45, tau: 0.78),
            HairPiece(pivot: back, follow: 0.30, tau: 0.95),
        ]

        torso.addChild(back)
        torso.addChild(fallL)
        torso.addChild(fallR)
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
        fill.light.intensity = 400
        fill.look(at: [0, 0, 0], from: [0.1, 0.3, 1], relativeTo: nil)

        camera.camera.fieldOfViewInDegrees = 22
        camera.position = [0, 0.05, 0.46]

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

    /// Wrap a mesh (built in body space) under a pivot entity so rotating the
    /// pivot swings the piece about its root.
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

    /// An expression patch: portrait-crop texture on a dome-hugging shell,
    /// pivoted at its own center. Invisible at rest by construction.
    private static func makePatch(
        rect: (Float, Float, Float, Float),
        proud: Float,
        textureNamed name: String
    ) throws -> FacePatch {
        let texture = try TextureResource.load(named: name)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(texture: .init(texture))
        material.roughness = 0.62
        material.metallic = 0.0
        material.blending = .transparent(opacity: .init(texture: .init(texture)))
        material.faceCulling = .none

        let built = try AvatarGeometry.facePatch(rect: rect, proud: proud)
        let pivot = Entity()
        pivot.position = built.pivot
        let model = ModelEntity(mesh: built.mesh, materials: [material])
        pivot.addChild(model)  // mesh is already relative to the pivot
        return FacePatch(pivot: pivot, home: built.pivot)
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
