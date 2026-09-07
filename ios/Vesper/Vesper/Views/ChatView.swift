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
    @AppStorage("stageTall") private var stageTall = false

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
            await model.refreshLink()
        }
        .onChange(of: recorder.deniedReason) {
            if let reason = recorder.deniedReason {
                model.banner = reason
                recorder.deniedReason = nil
            }
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
                conversation
                statusLine
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
            .safeAreaInset(edge: .top, spacing: 0) { header }
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

            if model.mode == .away || model.mode == .offline {
                Circle()
                    .fill(model.mode == .away ? model.cast.accent.opacity(0.8) : Color.gray)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(model.mode.label)
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
                colors: [Color.black.opacity(0.45), .clear],
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
            tall: stageTall
        )
        .frame(height: stageTall ? 420 : 290)
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
                            accent: model.cast.accent,
                            onReplay: { [weak model] in model?.voice.replay(message) }
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
            if recorder.isRecording { return "listening — tap ■ to send" }
            if model.isHearing { return model.hearingStatus ?? "hearing you…" }
            return model.banner
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
                RadialGradient(
                    colors: [Color(hex: 0xC4703A).opacity(0.13), .clear],
                    center: UnitPoint(x: 0.15, y: 0.95),
                    startRadius: 0, endRadius: 500
                )
                RadialGradient(
                    colors: [Color(hex: 0x2A6E6A).opacity(0.10), .clear],
                    center: UnitPoint(x: 0.95, y: 0.05),
                    startRadius: 0, endRadius: 420
                )
            case .mika:
                // Night flight: teal glow up top, a faint horizon line.
                RadialGradient(
                    colors: [Color(hex: 0x3FB8B2).opacity(0.14), .clear],
                    center: UnitPoint(x: 0.5, y: -0.1),
                    startRadius: 0, endRadius: 520
                )
                LinearGradient(
                    colors: [.clear, Color(hex: 0x3FB8B2).opacity(0.06), .clear],
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
