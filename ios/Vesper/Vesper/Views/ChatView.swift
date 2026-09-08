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
    @State private var showThreads = false
    @State private var talkOn = false
    /// When her last clip finished — the mic holds off until echo dies.
    @State private var lastSpokeAt: Date?
    @State private var talkWatchdog: Task<Void, Never>?
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
        .sheet(isPresented: $showThreads) {
            ThreadsSheet()
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
        // Talk loop. The one hard rule: her voice and the mic NEVER overlap.
        .onChange(of: model.voice.playingID) {
            if model.voice.playingID != nil {
                // She started speaking — if the mic is open, close it and
                // throw the take away (it would contain her own voice).
                if talkOn && recorder.isRecording {
                    recorder.cancel()
                }
            } else {
                lastSpokeAt = Date()
                maybeRearmTalk()
            }
        }
        .onChange(of: model.isThinking) {
            if !model.isThinking { maybeRearmTalk() }
        }
        .onChange(of: model.isHearing) {
            if !model.isHearing { maybeRearmTalk() }
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

            // Header lives in the layout (not a safe-area inset) so its menus
            // always hit-test, no matter what the stage underneath is doing.
            VStack(spacing: 0) {
                header
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
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: showChat)
        }
    }

    /// Thin header: every space visible at once — Vesper, Mika, and Chat are
    /// pages you step into (tap a pill or swipe the stage), not a dropdown.
    private var header: some View {
        HStack {
            castPills

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
                Button {
                    model.newThread()
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                }
                Button {
                    showThreads = true
                } label: {
                    Label("Threads…", systemImage: "text.justify.left")
                }
                Divider()
                if model.cast != .chat {
                    Button("Mood") { showMood = true }
                }
                Button("Settings") { showSettings = true }
                Divider()
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

    /// Her stage: the familiar 2D cutout over the page's own light, fading
    /// into the canvas. Breath only — no wiggle, no 3D. Tap to resize.
    private var stage: some View {
        CutoutStage(cast: model.cast)
        .frame(height: showChat ? (stageTall ? 560 : 420) : nil)
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
        // Swipe between spaces, like flipping pages.
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                let all = CastMember.allCases
                guard let index = all.firstIndex(of: model.cast) else { return }
                if value.translation.width < -60, index < all.count - 1 {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        model.switchCast(to: all[index + 1])
                    }
                } else if value.translation.width > 60, index > 0 {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        model.switchCast(to: all[index - 1])
                    }
                }
            }
        )
    }

    /// The page switcher: all three worlds, each set in its own type.
    private var castPills: some View {
        HStack(spacing: 6) {
            ForEach(CastMember.allCases) { member in
                Button {
                    guard member != model.cast else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        model.switchCast(to: member)
                    }
                } label: {
                    Text(member.displayName)
                        .font(Self.pillFont(for: member))
                        .foregroundStyle(member == model.cast ? VesperTheme.ink : VesperTheme.mute)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                member == model.cast ? member.accent.opacity(0.16) : .clear
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                member == model.cast ? member.accent.opacity(0.45) : .clear,
                                lineWidth: 1
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func pillFont(for member: CastMember) -> Font {
        switch member {
        case .vesper: return .system(size: 14, weight: .semibold, design: .serif)
        case .mika: return .system(size: 14, weight: .semibold, design: .rounded)
        case .chat: return .system(size: 14, weight: .medium)
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
            // One long-lived voiceChat session (with system echo cancellation)
            // owns audio for the whole conversation — also what keeps Talk
            // alive in the background (UIBackgroundModes: audio).
            TalkSession.begin()
            recorder.managesSession = false
            model.voice.managesSession = false
            recorder.autoStopOnSilence = true
            // Never open the mic blind: if she's mid-sentence or a turn is in
            // flight, the re-arm machinery opens it when the air is clear.
            maybeRearmTalk()
            talkWatchdog?.cancel()
            talkWatchdog = Task {
                // Safety net: fully guarded, so the worst it does is nothing.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    maybeRearmTalk()
                }
            }
        } else {
            talkWatchdog?.cancel()
            talkWatchdog = nil
            recorder.autoStopOnSilence = false
            recorder.cancel()
            model.voice.stop()
            recorder.managesSession = true
            model.voice.managesSession = true
            TalkSession.end()
        }
    }

    /// Re-arm the mic only when the air is clear: nothing recording, nothing
    /// thinking, nothing transcribing, nothing playing — and her last clip at
    /// least ~1.5 s gone, so speaker echo can't become the next message.
    private func maybeRearmTalk() {
        guard talkOn, !recorder.isRecording, !model.isThinking, !model.isHearing,
              model.voice.playingID == nil
        else { return }
        Task {
            let sinceSpeech = lastSpokeAt.map { Date().timeIntervalSince($0) } ?? .infinity
            let wait = max(0.5, 1.6 - sinceSpeech)
            try? await Task.sleep(for: .seconds(wait))
            let clearedEcho = lastSpokeAt.map { Date().timeIntervalSince($0) >= 1.45 } ?? true
            guard talkOn, !recorder.isRecording, !model.isThinking, !model.isHearing,
                  model.voice.playingID == nil, clearedEcho
            else { return }  // a queued clip resumed or a turn started — its end will retrigger
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
