import SwiftUI

/// The stage, 2D edition — a full-body cutout still on the dark canvas, like
/// the Mac Companion2DView. Subtle breath scale only: NO affine postcard
/// wiggle, NO video loops, NO RealityKit/SceneKit meshes (the procedural 3D
/// bust is gone and must not return).
///
/// Drop the real cutout PNGs (transparent background, full figure) into:
///   ios/Vesper/Vesper/Assets.xcassets/VesperCutout.imageset/vesper-cutout.png
///   ios/Vesper/Vesper/Assets.xcassets/MikaCutout.imageset/mika-cutout.png
/// (Vesper currently ships the locked face reference as a stopgap.)
struct CutoutStage: View {
    let cast: CastMember
    @State private var breathing = false

    private var assetName: String {
        cast == .mika ? "MikaCutout" : "VesperCutout"
    }

    var body: some View {
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(breathing ? 1.008 : 0.998, anchor: .bottom)
                    .animation(
                        .easeInOut(duration: 3.8).repeatForever(autoreverses: true),
                        value: breathing
                    )
                    .onAppear { breathing = true }
            } else {
                placeholder
            }
        }
    }

    /// Quiet stand-in until the cutout PNG lands — never anything cursed.
    private var placeholder: some View {
        ZStack {
            RadialGradient(
                colors: [cast.accent.opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: 0.75),
                startRadius: 0,
                endRadius: 260
            )
            Text(cast.displayName)
                .font(VesperTheme.display(26, weight: .medium))
                .foregroundStyle(VesperTheme.mute.opacity(0.7))
        }
    }
}
