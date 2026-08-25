import Foundation
import RealityKit
import UIKit

/// Vesper's parametric bust: entity hierarchy, materials, lights, camera.
/// All geometry is generated in code and textured with the locked portrait —
/// nothing here depends on external character assets.
final class AvatarRig {
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
    let keyLight = PointLight()
    let rimLight = PointLight()
    let camera = PerspectiveCamera()

    private static let ember = UIColor(red: 0.77, green: 0.36, blue: 0.15, alpha: 1)
    private static let rose = UIColor(red: 0.66, green: 0.30, blue: 0.30, alpha: 1)

    init() throws {
        let faceTexture = try TextureResource.load(named: "VesperFace")
        let lidTexture = try TextureResource.load(named: "VesperLid")

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

        var hair = PhysicallyBasedMaterial()
        hair.baseColor = .init(tint: UIColor(red: 0.10, green: 0.075, blue: 0.06, alpha: 1))
        hair.roughness = 0.42
        hair.metallic = 0.0
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

        let crown = ModelEntity(mesh: try AvatarGeometry.hairCrown(), materials: [hair])
        let curtainL = ModelEntity(mesh: try AvatarGeometry.hairCurtain(side: -1), materials: [hair])
        let curtainR = ModelEntity(mesh: try AvatarGeometry.hairCurtain(side: 1), materials: [hair])

        head.addChild(face)
        head.addChild(mouth)
        head.addChild(jawPivot)
        head.addChild(lidL)
        head.addChild(lidR)
        head.addChild(crown)
        head.addChild(curtainL)
        head.addChild(curtainR)

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
        let hairBack = ModelEntity(mesh: try AvatarGeometry.hairBack(), materials: [hair])

        torso.addChild(hairBack)
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
