import Foundation

enum VesperError: LocalizedError {
    case badURL
    case http(Int, String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "That Mac URL doesn't parse."
        case .http(let code, let body):
            return "HTTP \(code): \(String(body.prefix(160)))"
        case .emptyReply:
            return "Empty reply from the model."
        }
    }
}

private func snakeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
}

private func snakeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

// MARK: - Home leg: the phone API on the Mac

struct MacChatRequest: Encodable {
    var message: String
    var history: [Turn]
    var state: EmotionState
    var userName: String
    var notes: String
    var warmthBias: Double
    var sadismBias: Double
    var intensity: Double
    var wantAudio: Bool
    var temperature: Double = 0.92
    /// Cast support: bespoke prompt for non-Vesper members; `plain` skips the
    /// emotion pipeline server-side; `voice` picks the TTS voice per member.
    var personaOverride: String?
    var plain: Bool = false
    var voice: String?
}

struct MacChatResponse: Decodable {
    var reply: String
    var state: EmotionState
    var mood: String
    var audioB64: String?
    var audioMime: String?
}

/// One NDJSON event from POST /v1/chat/stream.
struct MacStreamEvent: Decodable {
    var type: String
    var text: String?
    var state: EmotionState?
    var mood: String?
    var audioB64: String?
    var audioMime: String?
    var reply: String?
    var detail: String?
    var seq: Int?
}

struct MacLink {
    var baseURL: URL

    init?(urlString: String) {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme != nil
        else { return nil }
        baseURL = url
    }

    /// Quick knock on /v1/health — decides Home vs Away.
    func isAwake() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "v1/health"))
        request.timeoutInterval = 2.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["ok"] as? Bool == true
        else { return false }
        return true
    }

    func chat(_ payload: MacChatRequest) async throws -> MacChatResponse {
        var request = URLRequest(url: baseURL.appending(path: "v1/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try snakeEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VesperError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try snakeDecoder().decode(MacChatResponse.self, from: data)
    }

    /// Streaming chat: tokens render live and her voice starts on the first
    /// sentence. Events are delivered in order on the main actor.
    func chatStream(
        _ payload: MacChatRequest,
        onEvent: @MainActor @escaping (MacStreamEvent) -> Void
    ) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/chat/stream"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120  // idle timeout between chunks
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try snakeEncoder().encode(payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VesperError.emptyReply
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 500 { break }
            }
            throw VesperError.http(http.statusCode, body)
        }

        let decoder = snakeDecoder()
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let event = try? decoder.decode(MacStreamEvent.self, from: data)
            else { continue }
            await onEvent(event)
        }
    }

    /// Fresh TTS take from the Mac (POST /v1/tts) — used by Regenerate.
    func tts(text: String, voice: String?) async throws -> Data {
        struct TTSRequestBody: Encodable {
            var text: String
            var voice: String?
        }
        struct TTSResponseBody: Decodable {
            var audioB64: String
        }
        var request = URLRequest(url: baseURL.appending(path: "v1/tts"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try snakeEncoder().encode(TTSRequestBody(text: text, voice: voice))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VesperError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try snakeDecoder().decode(TTSResponseBody.self, from: data)
        guard let clip = Data(base64Encoded: decoded.audioB64) else {
            throw VesperError.emptyReply
        }
        return clip
    }

    /// Upload a recorded clip to the Mac's Whisper (POST /v1/stt) — verbatim,
    /// uncensored transcription with the same stack the desktop uses.
    func transcribe(fileURL: URL) async throws -> String {
        let audio = try Data(contentsOf: fileURL)
        let boundary = "vesper-\(UUID().uuidString)"

        var request = URLRequest(url: baseURL.appending(path: "v1/stt"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append(
            "Content-Disposition: form-data; name=\"audio\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
        )
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VesperError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        struct STTResponse: Decodable {
            let text: String
        }
        return try JSONDecoder().decode(STTResponse.self, from: data).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

// MARK: - Away leg: xAI direct (Grok + Ara), key from Keychain

struct XAILink {
    var apiKey: String
    var model: String

    private static let chatURL = URL(string: "https://api.x.ai/v1/chat/completions")!
    private static let ttsURL = URL(string: "https://api.x.ai/v1/tts")!

    private struct CompletionRequest: Encodable {
        var model: String
        var messages: [Turn]
        var temperature: Double
        var maxTokens: Int
    }

    private struct CompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
            }
            var message: Message
        }
        var choices: [Choice]
    }

    private struct TTSRequest: Encodable {
        var text: String
        var voiceId: String
        var language: String
    }

    func chat(
        system: String,
        history: [Turn],
        user: String,
        temperature: Double = 0.92
    ) async throws -> String {
        var turns: [Turn] = [Turn(role: "system", content: system)]
        turns += history
        turns.append(Turn(role: "user", content: user))

        var request = URLRequest(url: Self.chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try snakeEncoder().encode(
            CompletionRequest(model: model, messages: turns, temperature: temperature, maxTokens: 900)
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VesperError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try snakeDecoder().decode(CompletionResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw VesperError.emptyReply }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ara says it. Returns raw MP3 bytes.
    func speak(_ text: String, voice: String = "ara") async throws -> Data {
        var request = URLRequest(url: Self.ttsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try snakeEncoder().encode(
            TTSRequest(text: Persona.speakable(text), voiceId: voice, language: "en")
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VesperError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
