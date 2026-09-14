# NotabilityClone

A personal, self-hosted Notability alternative for iPad — SwiftUI, sideloaded via
LiveContainer (free Apple ID, **no Apple Developer Program account required**).

## Structure

| Path | What |
|---|---|
| `Package.swift` | SwiftPM package **NotabilityCore** — platform-pure logic: models, GRDB store, correction math, evaluator, sync diff. Testable on Linux and macOS. |
| `Sources/NotabilityCore/` | The core library. No UIKit/CoreGraphics — geometry is plain `Point/Size/Rect` so tests run anywhere. |
| `Tests/NotabilityCoreTests/` | Phase-driven unit tests run via `swift test`. |
| `App/project.yml` | XcodeGen spec → `xcodegen generate` produces the `.xcodeproj` (deterministic; never committed). |
| `App/Sources/` | iOS app: SwiftUI UI, PencilKit canvas, Metal renderer (phases 3/6), services. |
| `.github/workflows/build.yml` | CI: `swift test` (gate) on Linux → unsigned `.ipa` on macos runner → prerelease per push. |

## Prereqs for local `swift test` (Linux)

- Swift 6.x toolchain (this repo is developed against Swift 6.3.x).
- GRDB links SQLite's **snapshot API** (`sqlite3_snapshot_open`), which distro
  builds omit. Compile a snapshot-enabled libsqlite3:
  `bash .github/scripts/build-sqlite.sh` (installs to `/usr/local/lib` and
  points the dev symlink at it).

## Pushing a build

```sh
swift test                          # local gate
xcodegen generate --spec App/project.yml   # not committed; CI does this
git push origin main                # CI builds, publishes beta release
```

Install the beta: download the attached `.ipa` on the iPad, open in
**LiveContainer**. No signing ceremony — the artifact is intentionally unsigned.

## Product decisions (locked)

- **Persistence**: GRDB/SQLite (plain SQLite = byte-identical on iOS + Linux, so
  local tests mirror the shipped store; block-diff sync maps directly onto SQL).
- **Transcription**: Groq OpenAI-compatible Whisper (`whisper-large-v3`, free).
  DeepInfra is the alternate provider. Per-task provider selection in onboarding.
- **Math OCR**: self-hosted **pix2tex** (`lukasblecher/pix2tex:api`, MIT) preferred,
  **Mathpix** API key as the paid alternative.
- **Background removal**: any OpenAI-compatible endpoint (BYOK); a self-hosted shim
  is included.
- **Custom ink rendering**: Metal (Metal needs no JIT on iOS), behind a
  `StrokeRenderer` protocol so Core Graphics can be swapped in.
- **Sync**: direct WebDAV to the user's ownCloud/oCIS server; block-level
  last-write-wins (no CRDT). Credentials in the Keychain.

## Phases

See `docs/PHASES.md` (creation in progress) — implemented to date: **Phase 1**
(data model + Notebook/Record CRUD + bare PKCanvasView; 20/20 unit tests green).