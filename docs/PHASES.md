# Build Plan

Each feature ships with tests run immediately (spec §0). Pure logic lives in
`NotabilityCore` (Linux-testable); Apple-only rendering/audio/vision code is
tested on the macOS/iPad-simulator CI job. CI runs `swift test` as a required
gate before producing any `.ipa`.

| Phase | Scope | Status |
|---|---|---|
| 1 | Data model + Notebook/Record CRUD; bare PKCanvasView; stroke persistence (drawing blob); pencil-locks touch off | ✅ Done (48 core + app + UI tests green) |
| 2 | Text / image / PDF-attachment blocks + canvas layout (area-select text, tap-to-place, font stepper, library+camera, PDFKit viewer) | ✅ Done (in CI) |
| 3 | Custom stroke rendering — PencilKit capture + Core Graphics/Metal renderer behind `StrokeRenderer`; migrate blob → stroke blocks | ⬜ |
| 4 | Background Vision text recognition on strokes (accurate mode), stored alongside strokes | ⬜ |
| 5 | Baseline/slant geometric correction ("beautify v1") | ⬜ |
| 6 | Letter Mode (gradient aging of old strokes, edge distance indicator) | ⬜ |
| 7 | Inline calculator + AI math fallback with editable variables (DeepInfra vision, BYOK) | ⬜ |
| 8 | Audio recording + DeepInfra Whisper transcription (chunked WAV), per-block timestamps | ⬜ |
| 9 | Dual-tab transcript UI with click-to-sync both directions | ⬜ |
| 10 | PDF extract mode (rasterize, zoom, crop, background removal) | ⬜ |
| 11 | OwnCloud/WebDAV sync (LWW per block, change log) | ⬜ |
| 12 | Quiz generation from transcript + notes (DeepInfra, BYOK) | ⬜ |
| 13 | Onboarding flow (OwnCloud login, DeepInfra key in Keychain, permissions) | ⬜ |

## Product decisions (from planning sessions + overnight decisions)

- **Persistence**: GRDB/SQLite; byte-identical on iOS + Linux so core tests
  mirror the shipped store. Dates as Double (`timeIntervalSinceReferenceDate`).
- **Min iOS**: 17. **Renderer**: Metal/Core Graphics behind `StrokeRenderer`.
- **AI (BYOK, keys in Keychain only)**: DeepInfra primary.
  - Math OCR/solve: DeepInfra vision chat (`Qwen/Qwen3-VL-235B-A22B-Instruct`),
    strict JSON schema; local `ExpressionEvaluator` runs first.
  - Transcription: DeepInfra Whisper `openai/whisper-large-v3-turbo`
    (OpenAI-compatible `/audio/transcriptions`, WAV chunks; m4a not accepted).
  - Quiz: DeepInfra chat `deepseek-ai/DeepSeek-V4-Flash-0731`, strict JSON.
  - Background removal: any OpenAI-compatible endpoint (self-hosted rembg shim
    in `shims/` must run on a machine with spare CPU — NOT the 2-core harness).
  - Network calls are stubbed behind `AIProvider` protocols by default; live
    providers throw `.notConfigured` until Phase 13 stores a key.
- **Sync**: WebDAV/OwnCloud client-side only (no server on the 2-core host);
  LWW per block on `modifiedAt`; `changeLog` table + pure `SyncDiffEngine`.
- **Canvas**: PKCanvasView is input-capture-only; custom rendering from Phase 3.
  Strokes stored as `.stroke` blocks; existing blob drawings migrate on open.
- **Distribution**: unsigned `.ipa` for LiveContainer via GitHub prereleases.

## Open items / notes

- Provider "integration points" are built (request builders + parsers, Linux-
  tested against fixtures) but live calls are stubs until keys exist.
- UI tests use DEBUG hooks (`canvasDebug` label, `-inMemoryStore`) because
  PhotosPicker/fileImporter/PencilKit pixels aren't scriptable from XCUITest.
