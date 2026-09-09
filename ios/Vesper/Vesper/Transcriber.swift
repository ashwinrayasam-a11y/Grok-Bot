import Foundation
import WhisperKit

/// On-device Whisper for Away mode (WhisperKit / argmax-oss-swift).
/// Verbatim transcription — no Apple Speech, no profanity filter.
/// The CoreML model (base.en, small enough for an iPhone) downloads once on
/// first use and is cached by WhisperKit after that.
actor LocalWhisper {
    static let shared = LocalWhisper()

    private var pipe: WhisperKit?

    func transcribe(
        _ fileURL: URL,
        status: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if pipe == nil {
            status("fetching her ears — one-time Whisper download…")
            pipe = try await WhisperKit(WhisperKitConfig(model: "base.en"))
        }
        guard let pipe else {
            throw VesperError.emptyReply
        }
        status("hearing you…")
        let results = try await pipe.transcribe(audioPath: fileURL.path)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
