import Combine
import RealityKit
import SwiftUI

/// The RealityKit surface hosting Vesper's bust. nonAR camera, transparent
/// background so she stands in the app's candlelight, per-frame updates via
/// the scene's update event (60 fps).
struct AvatarSurface: UIViewRepresentable {
    @EnvironmentObject private var model: ChatViewModel
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
        context.coordinator.attach(to: view, model: model)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.director?.setMood(from: model.emotion)
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
        func attach(to view: ARView, model: ChatViewModel) {
            do {
                let rig = try AvatarRig()
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(rig.stage)
                view.scene.addAnchor(anchor)

                let director = AvatarDirector(rig: rig)
                // Close over the (nonisolated) player, not the main-actor
                // view model — the render loop polls these off-actor.
                let voice = model.voice
                director.audioLevel = { [weak voice] in voice?.meterLevel() ?? 0 }
                director.isSpeaking = { [weak voice] in voice?.isLive ?? false }
                director.setMood(from: model.emotion)

                self.rig = rig
                self.director = director
                updateSub = view.scene.subscribe(to: SceneEvents.Update.self) { [weak director] event in
                    director?.tick(dt: event.deltaTime)
                }
            } catch {
                // Presence is decoration on top of the chat — if the rig or
                // textures fail to build, the app keeps chatting without her.
            }
        }
    }
}

/// Her place in the room: sits between the header and the conversation.
/// Tap to pull down from bust framing to décolleté framing; the chevron
/// tucks her away entirely.
struct PresencePanel: View {
    @EnvironmentObject private var model: ChatViewModel
    @AppStorage("presenceTall") private var tall = false
    @AppStorage("presenceShown") private var shown = true

    var body: some View {
        VStack(spacing: 0) {
            if shown {
                AvatarSurface(tall: tall)
                    .frame(height: tall ? 380 : 195)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.35)) { tall.toggle() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 24).onEnded { value in
                            withAnimation(.easeInOut(duration: 0.35)) {
                                if value.translation.height > 30 {
                                    if shown && !tall { tall = true } else { shown = true }
                                } else if value.translation.height < -30 {
                                    if tall { tall = false } else { shown = false }
                                }
                            }
                        }
                    )
            }
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { shown.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Capsule()
                        .fill(VesperTheme.line)
                        .frame(width: 44, height: 3)
                    Image(systemName: shown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(VesperTheme.mute.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shown ? "Hide her" : "Show her")
        }
    }
}
