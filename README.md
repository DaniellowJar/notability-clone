# NotabilityClone

**Ran out of actions, needed to switch to public repo, WIP!**

A personal, self-hosted Notability alternative for iPad — SwiftUI, sideloaded via
LiveContainer (free Apple ID, **no Apple Developer Program account required**).

> Repo URL, where the keys live (home `.env`), and how GitHub Actions compiles
> it: see [`docs/REPO.md`](docs/REPO.md).

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

## Install with LiveContainer (iPad)

No Apple Developer account needed — the release `.ipa` is unsigned and runs in
LiveContainer.

1. Get **LiveContainer** on the iPad (side-load it the usual way — e.g. with
   AltStore / Sideloadly / a signing service).
2. Open the repo's **Releases** page, download the latest `NotabilityClone.ipa`
   (the `beta-…` prerelease), and open it with **LiveContainer** on the iPad
   (AirDrop/iCloud Drive both work). LiveContainer imports it and it appears in
   the app list; tap to launch.
3. That's it. Notebooks, records, canvas drawings and transcripts are stored in
   the app container's `Documents/notability.sqlite`.

**Optional — seed data (JSON):** LiveContainer exposes the container's
`Documents` folder in its UI. Drop a file named `notability-seed.json` there and
it is imported on the next launch (idempotent — existing ids are skipped). The
schema is the `StoreBackup` envelope: `{version, notebooks, records, blocks,
audioTracks, transcriptSegments}`. Export a template with anything that writes
your own seed file:

```json
{"version":1,"notebooks":[],"records":[],"blocks":[],"audioTracks":[],"transcriptSegments":[]}
```

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