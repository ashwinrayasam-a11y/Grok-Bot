import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: ChatViewModel
    @StateObject private var recorder = AudioRecorder()
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showMood = false

    var body: some View {
        ZStack {
            VesperBackground()
            VStack(spacing: 0) {
                header
                Rectangle()
                    .fill(VesperTheme.line)
                    .frame(height: 1)
                PresencePanel()
                conversation
                if recorder.isRecording {
                    listeningBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if model.isHearing {
                    hearingBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Composer(
                    draft: $draft,
                    recorder: recorder,
                    busy: model.isHearing,
                    onSend: sendDraft,
                    onTalkStart: startListening,
                    onTalkEnd: sendSpoken
                )
            }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(text: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.banner)
        .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
        .animation(.easeInOut(duration: 0.2), value: model.isHearing)
        // Sheets are a new presentation tree — inject the model explicitly or
        // their @EnvironmentObject lookup fatal-errors at presentation time.
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showMood) {
            MoodSheet()
                .environmentObject(model)
        }
        .task {
            await model.refreshLink()
        }
        .onChange(of: recorder.deniedReason) {
            if let reason = recorder.deniedReason {
                model.banner = reason
                recorder.deniedReason = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Vesper")
                    .font(VesperTheme.display(32))
                    .foregroundStyle(VesperTheme.ink)
                Button {
                    showMood = true
                } label: {
                    HStack(spacing: 6) {
                        Text(model.emotion.moodLabel)
                            .font(.footnote.italic())
                            .foregroundStyle(VesperTheme.mute)
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(VesperTheme.mute.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            ModeChip(mode: model.mode)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(VesperTheme.mute)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(VesperTheme.panel))
                    .overlay(Circle().stroke(VesperTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if model.messages.isEmpty && !model.isThinking {
                        EmptyNest()
                            .padding(.top, 90)
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if model.isThinking {
                        ThinkingBubble()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.count) {
                if let last = model.messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.messages.last?.text) {
                // Follow her words as they stream in (no animation at token rate).
                if let last = model.messages.last, last.role == .assistant {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: model.isThinking) {
                if model.isThinking {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var listeningBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(VesperTheme.ember)
            Text("listening… tap ■ to send")
                .font(.callout)
                .foregroundStyle(VesperTheme.ink)
            MicLevelBars(level: recorder.level)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                recorder.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VesperTheme.mute)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(VesperTheme.bg.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VesperTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VesperTheme.ember.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private var hearingBar: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(VesperTheme.ember)
            Text(model.hearingStatus ?? "hearing you…")
                .font(.callout)
                .foregroundStyle(VesperTheme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VesperTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VesperTheme.line, lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Actions

    private func sendDraft() {
        let text = draft
        draft = ""
        model.send(text)
    }

    private func startListening() {
        model.voice.stop()
        Task { await recorder.start() }
    }

    private func sendSpoken() {
        if let url = recorder.stop() {
            model.heard(url)
        }
    }
}

/// Live microphone level while she listens.
struct MicLevelBars: View {
    var level: Double

    private let boost: [Double] = [0.55, 0.85, 1.0, 0.7, 0.45]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(VesperTheme.ember.opacity(0.85))
                    .frame(width: 3, height: 5 + CGFloat(level * boost[index]) * 15)
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

/// What you see before the first word.
struct EmptyNest: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "flame")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(VesperTheme.ember.opacity(0.8))
            Text("Say something.\nShe's already listening.")
                .font(VesperTheme.display(20, weight: .medium))
                .foregroundStyle(VesperTheme.mute)
                .multilineTextAlignment(.center)
        }
    }
}
