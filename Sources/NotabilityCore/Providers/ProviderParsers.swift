import Foundation

/// Parses provider responses into the typed result models. Tested against
/// fixture JSON on Linux.
public enum ProviderParsers {

    /// `choices[0].message.content` is a JSON string matching `MathOCRResult`.
    public static func mathOCR(_ data: Data) throws -> MathOCRResult {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let resultData = content.data(using: .utf8)
        else { throw AIProviderError.invalidResponse }
        let decoder = JSONDecoder()
        return try decoder.decode(MathOCRResult.self, from: resultData)
    }

    /// Whisper `verbose_json`: top-level `text` plus `segments[{start,end,text}]`.
    public static func transcription(_ data: Data) throws -> TranscriptionResult {
        struct Segment: Codable { let start: Double; let end: Double; let text: String }
        struct Response: Codable { let text: String?; let segments: [Segment]? }
        let decoder = JSONDecoder()
        let response = try decoder.decode(Response.self, from: data)
        let segments = (response.segments ?? []).map { TranscriptionSegment(start: $0.start, end: $0.end, text: $0.text) }
        return TranscriptionResult(segments: segments, fullText: response.text ?? segments.map(\.text).joined(separator: " "))
    }

    /// Chat completion whose `content` is a JSON string matching `Quiz`.
    public static func quiz(_ data: Data) throws -> Quiz {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let resultData = content.data(using: .utf8)
        else { throw AIProviderError.invalidResponse }
        struct QuizResponse: Codable { let questions: [QuizQuestion] }
        let decoded = try JSONDecoder().decode(QuizResponse.self, from: resultData)
        return Quiz(questions: decoded.questions)
    }

    /// OpenAI-compatible images edits: `data[0].b64_json` = transparent PNG.
    public static func backgroundRemoval(_ data: Data) throws -> Data {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["data"] as? [[String: Any]],
              let b64 = items.first?["b64_json"] as? String,
              let png = Data(base64Encoded: b64)
        else { throw AIProviderError.invalidResponse }
        return png
    }
}
