# Build Plan

Each feature ships with tests run immediately (spec §: "write and run a test
immediately after each feature"). Pure logic lives in `NotabilityCore` (Linux-
testable); Apple-only rendering/audio/vision code is tested on macOS CI.

**Gate discipline**: `swift test` must pass before a phase is considered done.
CI runs it before producing any `.ipa`.

| Phase | Scope | Status |
|---|---|---|
| 1 | Notebook/Record CRUD, block model + store, bare PKCanvasView, core 20 tests | ✅ Done (20/20 green) |
| 2 | Text / image / PDF block types, block placement & editing UI | ⬜ |
| 3 | Custom stroke rendering — PencilKit capture + Metal renderer + `StrokeRenderer` protocol | ⬜ |
| 4 | WebDAV/ownCloud sync — block-level change log + LWW diff (GRDB) | ⬜ |
| 5 | Inline calculator block (rational arithmetic in core, unit-tested) | ⬜ |
| 6 | Ink-to-text + ink-to-definition (Core ML / Apple frameworks) | ⬜ |
| 7 | Audio recording + Groq/DeepInfra transcription, transcript UI | ⬜ |
| 8 | Photo insert + background removal (BYOK OpenAI-compatible API) | ⬜ |
| 9 | PDF import + annotation + export | ⬜ |
| 10 | Handwriting recognition recovery + writing-sound-on-ink MSP | ⬜ |
| 11 | Text-to-speech + magic pen | ⬜ |
| 12 | Settings/onboarding (provider keys in Keychain, per-task providers) | ⬜ |
| 13 | Notability Import (parser) | ⬜ |

## Product decisions (from planning sessions)

- **Persistence**: GRDB/SQLite. Plain SQLite is byte-identical on iOS + Linux,
  so core tests mirror the shipped store; block diff sync maps onto SQL.
- **Min iOS**: 17. **Renderer**: Metal (no JIT needed on iOS), behind
  `StrokeRenderer` protocol.
- **Transcription**: Groq Whisper (`whisper-large-v3`, free) default; DeepInfra
  alternate. Onboarding: single-provider OR per-task providers.
- **Math OCR**: self-hosted pix2tex (MIT) default; Mathpix API key optional.
- **Background removal**: any OpenAI-compatible endpoint; self-hosted shim
  included.
- **Audio from recording while canvas visible**, transcript mapped to record.
- **Sync**: WebDAV (ownCloud/oCIS), LWW at block level, mtime + sortable UUID.
- **Distribution**: unsigned `.ipa` for LiveContainer via GitHub prereleases.