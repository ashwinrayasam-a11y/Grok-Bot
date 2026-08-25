import SwiftUI

/// Compact composer: multiline field, tap-on/tap-off mic, send.
struct Composer: View {
    @Binding var draft: String
    @ObservedObject var recorder: AudioRecorder
    /// True while a finished take is being transcribed — mic pauses until done.
    var busy: Bool
    var onSend: () -> Void
    var onTalkStart: () -> Void
    var onTalkEnd: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Speak to her…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(VesperTheme.ink)
                .tint(VesperTheme.ember)
                .submitLabel(.send)
                .onSubmit {
                    if canSend { onSend() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(VesperTheme.panel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(VesperTheme.line, lineWidth: 1)
                )

            talkButton
            sendButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Tap to start listening, tap again to stop and send the transcript.
    private var talkButton: some View {
        Button {
            if recorder.isRecording {
                onTalkEnd()
            } else {
                onTalkStart()
            }
        } label: {
            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(recorder.isRecording ? VesperTheme.bg : VesperTheme.mute)
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(recorder.isRecording ? VesperTheme.ember : VesperTheme.panel)
                )
                .overlay(
                    Circle().stroke(
                        recorder.isRecording ? VesperTheme.ember : VesperTheme.line,
                        lineWidth: 1
                    )
                )
                .scaleEffect(recorder.isRecording ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        .animation(.spring(duration: 0.25), value: recorder.isRecording)
        .accessibilityLabel(recorder.isRecording ? "Stop and send" : "Tap to talk")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(canSend ? VesperTheme.bg : VesperTheme.mute.opacity(0.6))
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(canSend ? VesperTheme.ember : VesperTheme.panel)
                )
                .overlay(
                    Circle().stroke(canSend ? VesperTheme.ember : VesperTheme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }
}
