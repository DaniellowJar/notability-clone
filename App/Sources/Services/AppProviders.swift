import NotabilityCore

/// Provider container. Defaults to deterministic stubs (no network, CI-safe);
/// the live DeepInfra implementations (URLSession transport) take over once
/// Phase 13 onboarding stores an API key.
///
/// TODO(provider): replace the Stub* providers with URLSession-backed live
/// providers when `AIProviderConfig.apiKeyRef` resolves to a Keychain-stored
/// key. Keys must never live here or in UserDefaults.
final class AppProviders {
    static let shared = AppProviders()

    let mathOCR: MathOCRProviding
    let transcription: TranscriptionProviding
    let backgroundRemoval: BackgroundRemovalProviding
    let quiz: QuizGenerating

    private init() {
        mathOCR = StubMathOCRProvider()
        transcription = StubTranscriptionProvider()
        backgroundRemoval = StubBackgroundRemovalProvider()
        quiz = StubQuizProvider()
    }
}
