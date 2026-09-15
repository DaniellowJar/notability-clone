import Foundation

/// Builds the exact request bodies the providers expect. Pure and
/// Linux-testable: tests assert the JSON/multipart shape.
public enum ProviderRequestBuilders {

    // MARK: - Math OCR / solve (DeepInfra vision chat, strict JSON schema)

    public static func mathOCR(imagePNG: Data, recognizedText: String, config: AIProviderConfig) throws -> ProviderJSONRequest {
        let url = URL(string: config.llmBaseURL)!.appendingPathComponent("chat/completions")
        let body: [String: Any] = [
            "model": config.visionModel,
            "temperature": 0.1,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "math_solution",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "latex": ["type": "string"],
                            "expression": ["type": "string"],
                            "result": ["type": "string"],
                            "steps": ["type": "array", "items": ["type": "string"]],
                            "variables": ["type": "object", "additionalProperties": ["type": "number"]],
                        ],
                        "required": ["latex", "expression", "result", "steps", "variables"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "messages": [
                [
                    "role": "system",
                    "content": "You are a math OCR engine. OCR the equation in the image, produce LaTeX and a plain arithmetic expression, solve it, and list symbolic variables as numbers. Return only JSON matching the schema.",
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(imagePNG.base64EncodedString())"]],
                        ["type": "text", "text": "Vision-recognized text hint: \"\(recognizedText)\""],
                    ],
                ],
            ],
        ]
        return ProviderJSONRequest(
            url: url,
            headers: openAIHeaders(config),
            jsonBody: try ProviderJSON.stringify(body)
        )
    }

    // MARK: - Transcription (DeepInfra Whisper, OpenAI-compatible)

    public static func transcription(wav: Data, language: String?, config: AIProviderConfig) throws -> ProviderMultipartRequest {
        let url = URL(string: config.transcriptionBaseURL)!.appendingPathComponent("audio/transcriptions")
        var fields = ["model": config.transcriptionModel, "response_format": "verbose_json"]
        if let language { fields["language"] = language }
        return ProviderMultipartRequest(
            url: url,
            headers: openAIHeaders(config),
            fields: fields,
            files: ["file": MultipartFile(filename: "chunk.wav", contentType: "audio/wav", data: wav)]
        )
    }

    // MARK: - Quiz generation (DeepInfra chat, strict JSON schema)

    public static func quiz(transcript: String, notes: String, config: AIProviderConfig) throws -> ProviderJSONRequest {
        let url = URL(string: config.llmBaseURL)!.appendingPathComponent("chat/completions")
        let body: [String: Any] = [
            "model": config.chatModel,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "quiz",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "questions": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "question": ["type": "string"],
                                        "choices": ["type": "array", "items": ["type": "string"]],
                                        "answerIndex": ["type": "integer"],
                                        "explanation": ["type": "string"],
                                    ],
                                    "required": ["question", "choices", "answerIndex", "explanation"],
                                    "additionalProperties": false,
                                ],
                            ],
                        ],
                        "required": ["questions"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "messages": [
                ["role": "system", "content": "Generate a short multiple-choice quiz from the lecture transcript and notes. Return only JSON matching the schema."],
                ["role": "user", "content": "TRANSCRIPT:\n\(transcript)\n\nNOTES:\n\(notes)"],
            ],
        ]
        return ProviderJSONRequest(
            url: url,
            headers: openAIHeaders(config),
            jsonBody: try ProviderJSON.stringify(body)
        )
    }

    // MARK: - Background removal (any OpenAI-compatible endpoint, TODO provider)

    /// POST {base}/v1/images/edits with the image as multipart; the response
    /// carries the transparent PNG in b64_json. `backgroundRemovalBaseURL` is
    /// unconfigured until a shim is deployed (TODO in Settings/onboarding).
    public static func backgroundRemoval(imagePNG: Data, config: AIProviderConfig) throws -> ProviderMultipartRequest {
        guard let base = URL(string: config.backgroundRemovalBaseURL) else {
            throw AIProviderError.notConfigured
        }
        let url = base.appendingPathComponent("v1/images/edits")
        return ProviderMultipartRequest(
            url: url,
            headers: openAIHeaders(config),
            fields: [:],
            files: ["image": MultipartFile(filename: "input.png", contentType: "image/png", data: imagePNG)]
        )
    }

    // MARK: - Shared

    /// Builders set only the Content-Type; the live transport injects the
    /// Authorization header from the Keychain at request time (keys never pass
    /// through the request model or logs).
    private static func openAIHeaders(_ config: AIProviderConfig) -> [String: String] {
        ["Content-Type": "application/json"]
    }
}
