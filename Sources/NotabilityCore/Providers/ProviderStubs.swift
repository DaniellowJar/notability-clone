import Foundation

/// Deterministic placeholder providers shipped by default. The live providers
/// (app target, URLSession transport) throw `.notConfigured` until Phase 13
/// onboarding stores a key; these make the app fully usable with zero network
/// and keep CI deterministic.
public struct StubMathOCRProvider: MathOCRProviding {
    public init() {}

    public func solve(imagePNG: Data, recognizedText: String) async throws -> MathOCRResult {
        MathOCRResult(
            latex: recognizedText.isEmpty ? "x^2" : recognizedText,
            expression: recognizedText,
            result: "",
            steps: ["TODO: configure DeepInfra API key in Settings (Phase 13 onboarding)"],
            variables: [:]
        )
    }
}

public struct StubTranscriptionProvider: TranscriptionProviding {
    public init() {}

    public func transcribe(wav: Data, language: String?) async throws -> TranscriptionResult {
        TranscriptionResult(
            segments: [
                TranscriptionSegment(start: 0, end: 2.5, text: "This is the stub transcription."),
                TranscriptionSegment(start: 2.5, end: 5.0, text: "Configure an API key to enable real speech-to-text."),
            ],
            fullText: "This is the stub transcription. Configure an API key to enable real speech-to-text."
        )
    }
}

public struct StubBackgroundRemovalProvider: BackgroundRemovalProviding {
    public init() {}

    public func removeBackground(imagePNG: Data) async throws -> Data {
        imagePNG // identity — deterministic, no network
    }
}

public struct StubQuizProvider: QuizGenerating {
    public init() {}

    public func generateQuiz(transcript: String, notes: String) async throws -> Quiz {
        Quiz(questions: [
            QuizQuestion(
                question: "What is 300 x 2?",
                choices: ["300", "600", "900", "1200"],
                answerIndex: 1,
                explanation: "Stub provider — configure an API key in Settings to generate real quizzes."
            ),
            QuizQuestion(
                question: "What does this app use for on-device ink recognition?",
                choices: ["Vision", "CloudKit", "Core Data", "ARKit"],
                answerIndex: 0,
                explanation: "Phase 4 uses Apple Vision for handwriting text recognition."
            ),
            QuizQuestion(
                question: "How are notes synced?",
                choices: ["iCloud", "WebDAV/OwnCloud", "AirDrop", "FTP"],
                answerIndex: 1,
                explanation: "Phase 11 syncs via WebDAV/OwnCloud, not iCloud."
            ),
        ])
    }
}
