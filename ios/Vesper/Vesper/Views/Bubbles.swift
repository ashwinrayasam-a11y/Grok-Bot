import SwiftUI

struct MessageBubble: View {
    @EnvironmentObject private var model: ChatViewModel
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 48)
            }
            VStack(alignment: .leading, spacing: 8) {
                if message.role == .assistant, message.audio != nil {
                    VoiceBar(message: message)
                }
                Text(rendered)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundStyle(message.isError ? VesperTheme.mute : VesperTheme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(shape.fill(fill))
            .overlay(shape.stroke(stroke, lineWidth: 1))
            if message.role == .assistant {
                Spacer(minLength: 48)
            }
        }
    }

    /// Inline markdown (her *emphasis*) with newlines preserved.
    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
    }

    private var shape: UnevenRoundedRectangle {
        message.role == .user
            ? UnevenRoundedRectangle(
                topLeadingRadius: 20, bottomLeadingRadius: 20,
                bottomTrailingRadius: 20, topTrailingRadius: 6, style: .continuous
            )
            : UnevenRoundedRectangle(
                topLeadingRadius: 6, bottomLeadingRadius: 20,
                bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous
            )
    }

    private var fill: AnyShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [VesperTheme.ember.opacity(0.30), VesperTheme.rose.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(VesperTheme.panel.opacity(0.92))
    }

    private var stroke: Color {
        if message.isError { return VesperTheme.rose.opacity(0.5) }
        return message.role == .user ? VesperTheme.ember.opacity(0.35) : VesperTheme.line
    }
}

/// Her voice: play control, live bars, duration.
struct VoiceBar: View {
    @EnvironmentObject private var model: ChatViewModel
    let message: ChatMessage

    private var isPlaying: Bool {
        model.voice.playingID == message.id
    }

    var body: some View {
        Button {
            model.voice.toggle(message)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VesperTheme.bg)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(VesperTheme.ember))
                EqualizerBars(active: isPlaying)
                if let seconds = message.audioSeconds {
                    Text(Self.timestamp(seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(VesperTheme.mute)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct EqualizerBars: View {
    var active: Bool
    @State private var phase = false

    private let low: [CGFloat] = [7, 11, 17, 9, 13]
    private let high: [CGFloat] = [15, 21, 9, 19, 7]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(VesperTheme.ember.opacity(active ? 0.85 : 0.35))
                    .frame(width: 3, height: active ? (phase ? high[index] : low[index]) : 6)
            }
        }
        .frame(height: 22)
        .animation(
            active ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true) : .default,
            value: phase
        )
        .onAppear { phase = active }
        .onChange(of: active) { phase = active }
    }
}

/// She's turning it over.
struct ThinkingBubble: View {
    @State private var on = false

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(VesperTheme.ember.opacity(0.8))
                        .frame(width: 6, height: 6)
                        .opacity(on ? 1 : 0.25)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: on
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 6, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous
                )
                .fill(VesperTheme.panel.opacity(0.92))
            )
            Spacer(minLength: 48)
        }
        .onAppear { on = true }
    }
}

/// Home / Away / unreachable indicator.
struct ModeChip: View {
    let mode: LinkMode

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(mode.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(VesperTheme.mute)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(VesperTheme.panel))
        .overlay(Capsule().stroke(VesperTheme.line, lineWidth: 1))
    }

    private var dotColor: Color {
        switch mode {
        case .home: return VesperTheme.ember
        case .away: return VesperTheme.rose
        case .offline: return .gray
        case .checking: return VesperTheme.mute
        }
    }
}

struct BannerView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(VesperTheme.ink)
            .lineLimit(3)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(VesperTheme.rose.opacity(0.92))
            )
            .padding(.horizontal, 24)
            .padding(.top, 6)
    }
}
