import SwiftUI

/// One clean pill — ChatGPT/Grok grammar. Mic on the left (tap-on/tap-off),
/// field in the middle, send appears only when there's something to send.
struct ComposerPill: View {
    @Binding var draft: String
    @ObservedObject var recorder: AudioRecorder
    var busy: Bool
    var accent: Color
    var placeholder: String
    var onSend: () -> Void
    var onTalkStart: () -> Void
    var onTalkEnd: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            micButton

            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(VesperTheme.ink)
                .tint(accent)
                .submitLabel(.send)
                .onSubmit { if canSend { onSend() } }
                .padding(.vertical, 4)

            if recorder.isRecording {
                MicLevelBars(level: recorder.level, accent: accent)
            } else if canSend {
                sendButton
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().strokeBorder(
                recorder.isRecording ? accent.opacity(0.55) : Color.white.opacity(0.09),
                lineWidth: 1
            )
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: canSend)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: recorder.isRecording)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var micButton: some View {
        Button {
            if recorder.isRecording {
                onTalkEnd()
            } else {
                onTalkStart()
            }
        } label: {
            Image(systemName: recorder.isRecording ? "stop.fill" : "mic")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(recorder.isRecording ? accent : VesperTheme.mute)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.4 : 1)
        .accessibilityLabel(recorder.isRecording ? "Stop and send" : "Tap to talk")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send")
    }
}

/// Live mic level, inline in the pill.
struct MicLevelBars: View {
    var level: Double
    var accent: Color

    private let boost: [Double] = [0.55, 0.9, 0.7]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(accent.opacity(0.9))
                    .frame(width: 3, height: 5 + CGFloat(level * boost[index]) * 13)
            }
        }
        .frame(width: 22, height: 24)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}
