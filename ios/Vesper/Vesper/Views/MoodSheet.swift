import SwiftUI

/// Her inner weather — every axis a live slider. Drag it and she *is* it:
/// writes go straight into the living EmotionState and persist.
struct MoodSheet: View {
    @EnvironmentObject private var model: ChatViewModel

    private let axes: [(String, WritableKeyPath<EmotionState, Double>)] = [
        ("devotion", \.devotion),
        ("warmth", \.warmth),
        ("sadism", \.sadism),
        ("trust", \.trust),
        ("jealousy", \.jealousy),
        ("vulnerability", \.vulnerability),
        ("playfulness", \.playfulness),
        ("melancholy", \.melancholy),
        ("intensity", \.intensity),
        ("bond", \.bond),
    ]

    var body: some View {
        ZStack {
            VesperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.emotion.moodLabel)
                        .font(VesperTheme.display(28))
                        .foregroundStyle(VesperTheme.ink)
                        .padding(.bottom, 2)
                        .animation(.easeInOut(duration: 0.2), value: model.emotion.moodLabel)

                    ForEach(axes, id: \.0) { name, keyPath in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(name)
                                    .font(.caption.smallCaps())
                                    .foregroundStyle(VesperTheme.mute)
                                Spacer()
                                Text("\(Int(model.emotion[keyPath: keyPath] * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(VesperTheme.mute)
                            }
                            Slider(value: binding(for: keyPath), in: 0...1)
                                .tint(VesperTheme.ember)
                        }
                    }
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func binding(for keyPath: WritableKeyPath<EmotionState, Double>) -> Binding<Double> {
        Binding(
            get: { model.emotion[keyPath: keyPath] },
            set: { model.updateEmotion(keyPath, to: $0) }
        )
    }
}
