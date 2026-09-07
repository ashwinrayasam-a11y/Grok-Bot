import Combine
import RealityKit
import SwiftUI

/// The RealityKit surface hosting a companion's bust. nonAR camera,
/// transparent background so she stands in the page's own light, per-frame
/// updates via the scene's update event (60 fps).
struct AvatarSurface: UIViewRepresentable {
    @EnvironmentObject private var model: ChatViewModel
    var style: AvatarStyle
    var temperament: MotionTemperament
    var tall: Bool

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.renderOptions.formUnion([
            .disableMotionBlur,
            .disableDepthOfField,
            .disableCameraGrain,
            .disablePersonOcclusion,
            .disableGroundingShadows,
        ])
        context.coordinator.attach(to: view, model: model, style: style, temperament: temperament)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.director?.setMood(from: model.presenceEmotion, dials: model.presenceDials)
        context.coordinator.director?.frameTall = tall
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var director: AvatarDirector?
        private var rig: AvatarRig?
        private var updateSub: Cancellable?

        @MainActor
        func attach(
            to view: ARView,
            model: ChatViewModel,
            style: AvatarStyle,
            temperament: MotionTemperament
        ) {
            do {
                let rig = try AvatarRig(style: style)
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(rig.stage)
                view.scene.addAnchor(anchor)

                let director = AvatarDirector(rig: rig, temperament: temperament)
                // Close over the (nonisolated) player, not the main-actor
                // view model — the render loop polls these off-actor.
                let voice = model.voice
                director.audioLevel = { [weak voice] in voice?.meterLevel() ?? 0 }
                director.isSpeaking = { [weak voice] in voice?.isLive ?? false }
                director.setMood(from: model.presenceEmotion, dials: model.presenceDials)

                self.rig = rig
                self.director = director
                updateSub = view.scene.subscribe(to: SceneEvents.Update.self) { [weak director] event in
                    director?.tick(dt: event.deltaTime)
                }
            } catch {
                // Presence is decoration on top of the chat — if the rig fails
                // to build, the page keeps chatting without her.
            }
        }
    }
}
