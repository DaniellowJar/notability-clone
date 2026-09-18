# Repository & credentials

Read this before asking "which repo is this?" or "where is the key?". It is the
single place that answers both, so it does not have to be repeated.

## What this repo is

- **GitHub**: [`DaniellowJar/notability-clone`](https://github.com/DaniellowJar/notability-clone)
- **Remote**: `origin` → `https://github.com/DaniellowJar/notability-clone.git`
- **Local checkout**: `/home/daniel/projects/notability-clone`
- **What it is**: a personal, self-hosted Notability alternative for iPad —
  SwiftUI + PencilKit, sideloaded with LiveContainer (free Apple ID, no paid
  Developer Program). Product decisions and install steps live in `README.md`.
- **Git identity**: `DaniellowJar <172176605+DaniellowJar@users.noreply.github.com>`

## Where the keys are

Keys are **never** committed. The home `.env` is the source of truth on the dev
machine, and the app's runtime keys live in the iOS Keychain.

| Key | Where it lives | What it is for |
|---|---|---|
| `GITHUB_TOKEN` | `/home/daniel/.env` (dev machine home) | GitHub PAT for `gh` / scripting / CI. `gh` is already authenticated as `DaniellowJar` (token cached in `~/.config/gh/hosts.yml`). |
| `CLOUDFLARE_API_TOKEN` | `/home/daniel/.env` (dev machine home) | Cloudflare Tunnel DNS records that expose the self-hosted AI shims publicly. |
| DeepInfra API key | iOS **Keychain** via app Settings | Live AI providers (transcription / math OCR / quiz). Stored by `AppSecrets`/`SecretsStore` (`App/Sources/Services/SecretsStore.swift`). |
| ownCloud URL / user / password | iOS **Keychain** via app Settings | WebDAV sync (`App/Sources/Sync/`). |
| `SHIM_API_KEY` | `shims/.env` next to `shims/docker-compose.yml` | Shared bearer key for the self-hosted `rembg` / `pix2tex` shim containers. Empty = anonymous on a private LAN. |

To read the home `.env`:

```sh
set -a; . ~/.env; set +a   # then use $GITHUB_TOKEN / $CLOUDFLARE_API_TOKEN
```

`.gitignore` already excludes `.env`, `*.env`, `keys.env`, `.ocis-rclone.env` —
do not remove those rules and do not paste secrets into source, docs, or logs.

## Compiling via GitHub Actions

Workflow: [`.github/workflows/build.yml`](../.github/workflows/build.yml).

- **Triggers**: every push to `main`, plus manual `workflow_dispatch`.
- **Jobs**:
  1. `test-core` (ubuntu-latest) — installs Swift 6.3.3, builds a
     snapshot-enabled libsqlite3, runs `swift test` (required gate).
  2. `build-ios` (macos-15) — `xcodegen generate`, unsigned device build
     (`CODE_SIGNING_ALLOWED=NO`), simulator unit tests, packages an unsigned
     `NotabilityClone.ipa`.
  3. `release` (main only) — publishes a `beta-YYYY.MM.DD-HHMM` prerelease with
     the IPA attached.

Trigger and watch a build:

```sh
git push origin main          # triggers CI
gh run list                   # recent runs
gh run watch                  # follow the current run
gh release list               # published beta builds
```

The `.ipa` is intentionally unsigned and installs through LiveContainer; see
`README.md` for the install steps.

## Local commands

```sh
swift test                          # core gate (NotabilityCore only)
cd App && xcodegen generate         # produce .xcodeproj (never committed)
git push origin main                # CI builds + publishes a beta release
```

## Where else to look

- `README.md` — product decisions, LiveContainer install, seed data.
- `docs/PHASES.md` — build plan and status.
- `docs/BUGS.md` — live ink/canvas bug register.
- `docs/LETTER_MODE.md`, `docs/ACHIEVEMENTS.md`.
- `shims/README.md` — self-hosted AI shim contracts and deployment.
