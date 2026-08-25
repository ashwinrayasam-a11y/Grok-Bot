import SwiftUI

/// Her inner weather — the same bars the Gradio mood panel shows.
struct MoodSheet: View {
    @EnvironmentObject private var model: ChatViewModel

    var body: some View {
        ZStack {
            VesperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(model.emotion.moodLabel)
                        .font(VesperTheme.display(28))
                        .foregroundStyle(VesperTheme.ink)
                        .padding(.bottom, 2)

                    ForEach(model.emotion.axes, id: \.0) { name, value in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(name)
                                    .font(.caption.smallCaps())
                                    .foregroundStyle(VesperTheme.mute)
                                Spacer()
                                Text("\(Int(value * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(VesperTheme.mute)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(VesperTheme.panel)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [VesperTheme.ember, VesperTheme.rose],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(4, geo.size.width * value))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
