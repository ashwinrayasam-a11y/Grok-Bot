import SwiftUI

/// Rendered-markdown cache: parse a reply exactly once when it completes,
/// never per token, never per body evaluation. (Session-scoped; tiny.)
@MainActor
enum MarkdownStore {
    private static var cache: [UUID: (length: Int, text: AttributedString)] = [:]

    static func rendered(for message: ChatMessage) -> AttributedString {
        if let hit = cache[message.id], hit.length == message.text.count {
            return hit.text
        }
        let parsed = (try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
        cache[message.id] = (message.text.count, parsed)
        return parsed
    }

    static func clear() {
        cache.removeAll()
    }
}

/// One message. Equatable so streaming one bubble never re-renders the rest —
/// the closure is excluded from equality on purpose.
struct MessageRow: View, Equatable {
    let message: ChatMessage
    let isPlaying: Bool
    let accent: Color
    let onReplay: () -> Void

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message == rhs.message
            && lhs.isPlaying == rhs.isPlaying
            && lhs.accent == rhs.accent
    }

    var body: some View {
        if message.role == .user {
            userRow
        } else {
            assistantRow
        }
    }

    /// User: a quiet pill, right-aligned — ChatGPT/Grok grammar.
    private var userRow: some View {
        HStack {
            Spacer(minLength: 64)
            Text(message.text)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(VesperTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )
        }
    }

    /// Assistant: free text on the canvas — no bubble chrome at all.
    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            if message.hasVoice {
                VoiceChip(
                    isPlaying: isPlaying,
                    seconds: message.audioSeconds,
                    accent: accent,
                    action: onReplay
                )
            }
            Group {
                if message.isStreaming {
                    Text(verbatim: message.text)
                } else {
                    Text(MarkdownStore.rendered(for: message))
                }
            }
            .font(.body)
            .lineSpacing(5)
            .foregroundStyle(message.isError ? VesperTheme.mute : VesperTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 40)
    }
}

/// Minimal voice affordance: tap to replay from the start. No transport.
struct VoiceChip: View {
    let isPlaying: Bool
    let seconds: Double?
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying)
                if let seconds {
                    Text(Self.timestamp(seconds))
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(isPlaying ? accent : VesperTheme.mute)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Speaking" : "Replay voice")
    }

    private static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Three quiet dots while the reply forms.
struct ThinkingDots: View {
    let accent: Color
    @State private var on = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(accent.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .opacity(on ? 1 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: on
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { on = true }
    }
}

/// Bespoke empty state per cast member.
struct CastEmptyState: View {
    let cast: CastMember

    var body: some View {
        VStack(spacing: 10) {
            Text(cast.emptyTitle)
                .font(
                    cast == .chat
                        ? .system(.title3, weight: .medium)
                        : VesperTheme.display(22, weight: .medium)
                )
                .foregroundStyle(VesperTheme.ink.opacity(0.9))
            Text(cast.emptyLine)
                .font(.subheadline)
                .foregroundStyle(VesperTheme.mute)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}
