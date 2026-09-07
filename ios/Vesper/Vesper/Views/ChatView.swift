import SwiftUI

/// The shell: dark, minimal, fast — Grok/ChatGPT grammar. Chrome is nearly
/// invisible; each cast member owns a page (backdrop, accent, stage, copy),
/// and switching crossfades between worlds.
struct ChatView: View {
    @EnvironmentObject private var model: ChatViewModel
    @StateObject private var recorder = AudioRecorder()
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showMood = false
    @State private var talkOn = false
    @AppStorage("stageTall") private var stageTall = false
    @AppStorage("chatVisible") private var chatVisible = true

    /// Chat cast has no stage, so its chat panel can never be hidden.
    private var showChat: Bool {
        chatVisible || !model.cast.hasPresence
    }

    var body: some View {
        ZStack {
            world
                .id(model.cast)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.4), value: model.cast)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showMood) {
            MoodSheet()
                .environmentObject(model)
        }
        .task {
            recorder.onAutoStop = { sendSpoken() }
            await model.refreshLink()
        }
        .onChange(of: recorder.deniedReason) {
            if let reason = recorder.deniedReason {
                model.banner = reason
                recorder.deniedReason = nil
            }
        }
        // Talk loop: when her reply finishes speaking (or a voiceless turn
        // completes), re-arm the mic after a beat.
        .onChange(of: model.voice.playingID) { maybeRearmTalk() }
        .onChange(of: model.isThinking) {
            if !model.isThinking { maybeRearmTalk() }
        }
        .onChange(of: model.cast) {
            if talkOn { setTalk(false) }
        }
    }

    // MARK: - One member's world

    private var world: some View {
        ZStack {
            CastBackdrop(cast: model.cast)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if model.cast.hasPresence {
                    stage
                }
                if showChat {
                    conversation
                } else {
                    Spacer(minLength: 0)
                }
                statusLine
                if showChat {
                    ComposerPill(
                        draft: $draft,
                        recorder: recorder,
                        busy: model.isHearing,
                        accent: model.cast.accent,
                        placeholder: model.cast.placeholder,
                        onSend: sendDraft,
                        onTalkStart: startListening,
                        onTalkEnd: sendSpoken
                    )
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: showChat)
        }
    }

    /// Thin floating header: name as the cast switcher, one menu. Nothing else.
    private var header: some View {
        HStack {
            Menu {
                ForEach(CastMember.allCases) { member in
                    Button {
                        model.switchCast(to: member)
                    } label: {
                        if member == model.cast {
                            Label(member.displayName, systemImage: "checkmark")
                        } else {
                            Text(member.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(model.cast.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(VesperTheme.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VesperTheme.mute)
                }
            }

            Spacer()

            // Offline is the only state worth a pixel of chrome.
            if model.mode == .offline {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(model.mode.label)
            }

            // Talk: hands-free loop — listen, send, she answers, listen again.
            Button {
                setTalk(!talkOn)
            } label: {
                Image(systemName: talkOn ? "mic.fill" : "mic")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(talkOn ? model.cast.accent : VesperTheme.mute)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(talkOn ? "End Talk" : "Start Talk")

            if model.cast.hasPresence {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        chatVisible.toggle()
                    }
                } label: {
                    Image(systemName: showChat ? "bubble.left.fill" : "bubble.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VesperTheme.mute)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(showChat ? "Hide chat" : "Show chat")
            }

            Menu {
                if model.cast == .vesper {
                    Button("Mood") { showMood = true }
                }
                Button("Settings") { showSettings = true }
                Button("Clear conversation", role: .destructive) {
                    MarkdownStore.clear()
                    model.resetSoul()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VesperTheme.mute)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.30), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    /// Her stage: the bust over the page's own light, fading into the canvas.
    /// Tap to pull between bust and décolleté framing.
    private var stage: some View {
        AvatarSurface(
            style: model.cast == .mika ? .mika : .vesper,
            temperament: model.cast == .mika ? .mika : .vesper,
            tall: showChat ? stageTall : true
        )
        .frame(height: showChat ? (stageTall ? 420 : 290) : nil)
        .frame(maxHeight: showChat ? nil : .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, CastBackdrop.canvas(for: model.cast)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 70)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                stageTall.toggle()
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if model.messages.isEmpty && !model.isThinking {
                        CastEmptyState(cast: model.cast)
                    }
                    ForEach(model.messages) { message in
                        MessageRow(
                            message: message,
                            isPlaying: model.voice.playingID == message.id,
                            isRegenerating: model.regeneratingID == message.id,
                            canRegenerate: model.cast.voiceID != nil
                                && message.role == .assistant && !message.isError,
                            accent: model.cast.accent,
                            onReplay: { [weak model] in model?.voice.replay(message) },
                            onRegenerate: { [weak model] in model?.regenerateVoice(for: message) }
                        )
                        .equatable()
                        .id(message.id)
                    }
                    if model.isThinking {
                        ThinkingDots(accent: model.cast.accent)
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.count) {
                if let last = model.messages.last {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.scrollPulse) {
                // Throttled follow while tokens stream — no animation, no thrash.
                if let last = model.messages.last, last.role == .assistant {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: model.isThinking) {
                if model.isThinking {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    /// One quiet status line above the pill — listening, hearing, or errors.
    @ViewBuilder
    private var statusLine: some View {
        let text: String? = {
            if let banner = model.banner { return banner }
            if recorder.isRecording {
                return talkOn ? "Talk on — just speak" : "listening — tap ■ to send"
            }
            if model.isHearing { return model.hearingStatus ?? "hearing you…" }
            if talkOn { return model.isThinking ? nil : "Talk on" }
            return nil
        }()
        if let text {
            Text(text)
                .font(.footnote)
                .foregroundStyle(model.banner != nil && !recorder.isRecording && !model.isHearing
                    ? Color(hex: 0xC98080)
                    : VesperTheme.mute)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.bottom, 6)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: text)
        }
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

    // MARK: - Talk mode (STT → reply → TTS → listen again)

    private func setTalk(_ on: Bool) {
        talkOn = on
        if on {
            // One long-lived voiceChat session owns audio for the whole
            // conversation — this is also what keeps Talk alive when the app
            // is backgrounded (UIBackgroundModes: audio).
            TalkSession.begin()
            recorder.managesSession = false
            model.voice.managesSession = false
            recorder.autoStopOnSilence = true
            startListening()
        } else {
            recorder.autoStopOnSilence = false
            recorder.cancel()
            model.voice.stop()
            recorder.managesSession = true
            model.voice.managesSession = true
            TalkSession.end()
        }
    }

    private func maybeRearmTalk() {
        guard talkOn, !recorder.isRecording, !model.isThinking, !model.isHearing,
              model.voice.playingID == nil
        else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard talkOn, !recorder.isRecording, !model.isThinking, !model.isHearing,
                  model.voice.playingID == nil
            else { return }
            await recorder.start()
        }
    }
}

/// Each member's canvas — near-black with their own light, never a template.
struct CastBackdrop: View {
    let cast: CastMember

    static func canvas(for cast: CastMember) -> Color {
        switch cast {
        case .vesper: return Color(hex: 0x0C0908)
        case .mika: return Color(hex: 0x070B0D)
        case .chat: return Color(hex: 0x0B0B0A)
        }
    }

    var body: some View {
        ZStack {
            Self.canvas(for: cast)
            switch cast {
            case .vesper:
                // Her night: low ember warmth, a breath of teal high and away.
                // Vignette kept light — the canvas should read near-black.
                RadialGradient(
                    colors: [Color(hex: 0xC4703A).opacity(0.09), .clear],
                    center: UnitPoint(x: 0.15, y: 0.95),
                    startRadius: 0, endRadius: 500
                )
                RadialGradient(
                    colors: [Color(hex: 0x2A6E6A).opacity(0.06), .clear],
                    center: UnitPoint(x: 0.95, y: 0.05),
                    startRadius: 0, endRadius: 420
                )
            case .mika:
                // Night flight: teal glow up top, a faint horizon line.
                RadialGradient(
                    colors: [Color(hex: 0x3FB8B2).opacity(0.09), .clear],
                    center: UnitPoint(x: 0.5, y: -0.1),
                    startRadius: 0, endRadius: 520
                )
                LinearGradient(
                    colors: [.clear, Color(hex: 0x3FB8B2).opacity(0.04), .clear],
                    startPoint: UnitPoint(x: 0, y: 0.42),
                    endPoint: UnitPoint(x: 0, y: 0.50)
                )
            case .chat:
                // Deliberately nothing: a clean assistant canvas.
                EmptyView()
            }
        }
    }
}
