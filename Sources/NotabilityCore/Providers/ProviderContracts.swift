import Foundation

// MARK: - Configuration

/// BYOK AI configuration (Section 9). Only the *service name* of the API key
/// lives here (`apiKeyRef`) — the key itself stays in the Keychain.
public struct AIProviderConfig: Codable, Equatable, Sendable {
    public var transcriptionBaseURL: String
    public var transcriptionModel: String
    public var llmBaseURL: String
    public var chatModel: String
    public var visionModel: String
    public var backgroundRemovalBaseURL: String
    /// Keychain service name used to look up the key (never the key itself).
    public var apiKeyRef: String

    public init(
        transcriptionBaseURL: String = "https://api.deepinfra.com/v1/openai",
        transcriptionModel: String = "openai/whisper-large-v3-turbo",
        llmBaseURL: String = "https://api.deepinfra.com/v1/openai",
        chatModel: String = "deepseek-ai/DeepSeek-V4-Flash-0731",
        visionModel: String = "Qwen/Qwen3-VL-235B-A22B-Instruct",
        backgroundRemovalBaseURL: String = "",
        apiKeyRef: String = "deepinfra"
    ) {
        self.transcriptionBaseURL = transcriptionBaseURL
        self.transcriptionModel = transcriptionModel
        self.llmBaseURL = llmBaseURL
        self.chatModel = chatModel
        self.visionModel = visionModel
        self.backgroundRemovalBaseURL = backgroundRemovalBaseURL
        self.apiKeyRef = apiKeyRef
    }
}

// MARK: - Transport abstraction

/// Minimal transport the live providers need. The app's URLSession adapter is
/// the only concrete implementation; core tests exercise builders/parsers.
public protocol AIProviderTransport: Sendable {
    func postJSON(_ request: ProviderJSONRequest) async throws -> Data
    func postMultipart(_ request: ProviderMultipartRequest) async throws -> Data
}

public struct ProviderJSONRequest: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
    public let jsonBody: Data

    public init(url: URL, headers: [String: String], jsonBody: Data) {
        self.url = url
        self.headers = headers
        self.jsonBody = jsonBody
    }
}

public struct ProviderMultipartRequest: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
    public let fields: [String: String]
    public let files: [String: MultipartFile]

    public init(url: URL, headers: [String: String], fields: [String: String], files: [String: MultipartFile]) {
        self.url = url
        self.headers = headers
        self.fields = fields
        self.files = files
    }
}

public struct MultipartFile: Sendable, Equatable {
    public let filename: String
    public let contentType: String
    public let data: Data

    public init(filename: String, contentType: String, data: Data) {
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }
}

// MARK: - Capability protocols

public protocol MathOCRProviding {
    func solve(imagePNG: Data, recognizedText: String) async throws -> MathOCRResult
}

public protocol TranscriptionProviding {
    func transcribe(wav: Data, language: String?) async throws -> TranscriptionResult
}

public protocol BackgroundRemovalProviding {
    func removeBackground(imagePNG: Data) async throws -> Data
}

public protocol QuizGenerating {
    func generateQuiz(transcript: String, notes: String) async throws -> Quiz
}

// MARK: - Result models

public struct MathOCRResult: Codable, Equatable, Sendable {
    public var latex: String
    public var expression: String
    public var result: String
    public var steps: [String]
    public var variables: [String: Double]

    public init(latex: String, expression: String, result: String, steps: [String], variables: [String: Double]) {
        self.latex = latex
        self.expression = expression
        self.result = result
        self.steps = steps
        self.variables = variables
    }
}

public struct TranscriptionSegment: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct TranscriptionResult: Codable, Equatable, Sendable {
    public var segments: [TranscriptionSegment]
    public var fullText: String

    public init(segments: [TranscriptionSegment], fullText: String) {
        self.segments = segments
        self.fullText = fullText
    }
}

public struct QuizQuestion: Codable, Equatable, Sendable {
    public var question: String
    public var choices: [String]
    public var answerIndex: Int
    public var explanation: String

    public init(question: String, choices: [String], answerIndex: Int, explanation: String) {
        self.question = question
        self.choices = choices
        self.answerIndex = answerIndex
        self.explanation = explanation
    }
}

public struct Quiz: Codable, Equatable, Sendable {
    public var questions: [QuizQuestion]

    public init(questions: [QuizQuestion]) {
        self.questions = questions
    }
}

// MARK: - Errors

public enum AIProviderError: Error, Equatable {
    /// No API key configured (Phase 13 onboarding not completed).
    case notConfigured
    /// Response body wasn't the expected shape.
    case invalidResponse
    /// Transport-level failure (URLSession, status codes, etc.).
    case transportFailure(String)
    /// Non-2xx status code.
    case statusCode(Int)
}

// MARK: - JSON helpers

public enum ProviderJSON {
    public static func stringify(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }

    public static func stringify(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
