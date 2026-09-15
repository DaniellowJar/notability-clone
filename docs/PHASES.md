# Build Plan

Each feature ships with tests run immediately (spec §0). Pure logic lives in
`NotabilityCore` (Linux-testable); Apple-only rendering/audio/vision code is
tested on the macOS/iPad-simulator CI job. CI runs `swift test` as a required
gate before producing any `.ipa`.

| Phase | Scope | Status |
|---|---|---|
| 1 | Data model + CRUD; bare canvas; stroke persistence (blob); pencil locks touch off | ✅ |
| 2 | Text/image/PDF-attachment blocks + layout (area-select text, tap-to-place, font stepper, library+camera, PDFKit) | ✅ |
| 3 | Custom stroke rendering (capture-only canvas, CG renderer, blob→stroke-block migration) | ✅ |
| 4 | Vision text recognition on strokes (accurate), stored per block | ✅ |
| 5 | Geometric beautify v1 (de-slant shear + baseline snap) | ✅ |
| 6 | Letter Mode (age-faded ink + edge-distance gauge) | ✅ |
| 7 | Inline calculator (local eval) + AI math fallback (stubbed provider) | ✅ |
| 8 | Audio recording (WAV chunks) + transcription pipeline (stubbed provider) | ✅ |
| 9 | Transcript UI with click-to-sync (shared clock) | ✅ |
| 10 | PDF extract mode (high-DPI raster → image block) + background removal (stubbed) | ✅ |
| 11 | OwnCloud/WebDAV sync — LWW diff engine (client transport still TODO) | ◑ |
| 12 | Quiz generation from transcript + notes (stubbed provider) | ✅ |
| 13 | Settings/onboarding (DeepInfra key + OwnCloud creds in Keychain) | ✅ |

Legend: ✅ shipped (core + app, CI-green where CI has run); ◑ core done, app
transport/stub wiring pending.

## Product decisions

- **Persistence**: GRDB/SQLite; byte-identical on iOS + Linux. Dates as Double.
- **Min iOS**: 17. **Renderer**: Core Graphics behind `StrokeRendering`.
- **AI (BYOK, keys in Keychain only)**: DeepInfra primary. Math OCR = DeepInfra
  vision chat (strict JSON schema); transcription = Whisper
  `openai/whisper-large-v3-turbo` (WAV chunks, OpenAI-compatible); quiz = chat
  (`deepseek-ai/DeepSeek-V4-Flash-0731`); background removal = any
  OpenAI-compatible endpoint (self-hosted rembg shim must run on a machine with
  spare CPU — not the 2-core harness). `AppProviders` is the clearly-marked
  swap point; stubs ship by default until an API key is configured.
- **Sync**: WebDAV/OwnCloud client-side (LWW per block on mtime); the diff
  engine is core-tested; the URLSession WebDAV client is TODO. No server runs
  on the 2-core harness.
- **Canvas**: PKCanvasView is input-capture-only; ink renders via the custom
  renderer; strokes persist as `.stroke` blocks; legacy blobs migrate on open.
- **Distribution**: unsigned `.ipa` via GitHub prereleases (LiveContainer).

## Open items / notes

- Live provider network calls are stubs until keys exist; UI tests use DEBUG
  hooks because PhotosPicker/fileImporter/camera/PencilKit pixels aren't
  scriptable from XCUITest.
- Letter Mode viewport auto-pan (narrow 2–3-letter window) is a follow-up; v1
  ships age-fading + edge gauge.
- Deletion propagation in sync needs a change log (tombstones) — v1 is
  upload/download only.
