# Achievements

Shipped, working capabilities worth protecting. Each entry names the
behavior and where it lives, so refactors don't silently regress it.

## Ink

- **Native live ink in normal mode** — the PencilKit canvas renders strokes
  live with correct tool color/width; the custom layer stays hidden
  (`opacity = 0`) unless Letter Mode is active
  (`App/Sources/Views/RecordCanvasView.swift`).
- **Stroke persistence** — every completed stroke is converted to `StrokeData`
  and stored as a `.stroke` block on drawing-change count increase, with an
  end-of-tool flush as backup (`Coordinator.canvasViewDrawingDidChange`,
  `canvasViewDidEndUsingTool`).
- **Legacy blob migration** — per-record `PKDrawing` blobs convert to stroke
  blocks once, idempotently (`App/Sources/Ink/DrawingMigrator.swift`).
- **Dynamic pen color resolution** — `.label`/dynamic ink resolves to a
  concrete hex instead of garbage black (`App/Sources/Ink/UIColorHex.swift`).
- **Retina ink backing** — the custom ink view scales its raster store with
  `screenScale × zoom` (`App/Sources/Ink/InkCanvasView.swift`,
  `CanvasTransform.rasterScale`).

## Letter Mode v2

- **Write-zoom-commit** — marquee area zooms to fit, the camera follows
  writing at 70% viewport width, the line settles (0.8 s) and commits
  normalized to 12 px in place with stable block IDs
  (`App/Sources/Views/Canvas/CanvasSessionState.swift`).
- **Trailing-3-letter fading** — newest cluster full color, two fading
  predecessors, older hidden (`Sources/NotabilityCore/Text/LetterMode.swift`,
  `LetterModeAging.swift`, `App/Sources/Ink/StrokeRenderer.swift`).
- **Live preview under the opaque layer** — touch-tracked ephemeral stroke
  plus PencilKit begin/end signals, so ink shows while painting
  (`Coordinator.handleLiveTouch`, `canvasViewDidBeginUsingTool`).

## Page & canvas

- **Infinite page + zoom** — screen-width page with borders and creation-date
  header, vertical growth from ink *and* viewport panning, pinch 100–400%
  with snap, two-finger Maps-style zoom+pan
  (`CanvasSessionState`, `ZoomPanOverlay`, `CanvasTransform`).
- **Vector page textures** — 6 patterns drawn in canvas coordinates
  (`PageTextureView`, `PageTexture`).
- **Vector PDF blocks** — zoom-bucketed re-render with tile cache + debounce
  (`PDFVectorRenderer`, `PDFTile`, `PDFBlockView`).
- **Text/image/PDF/calc blocks** — area-select, tap-to-place, drag by
  location deltas in canvas space, font stepper
  (`CanvasBlockLayer`, `CanvasSessionState`).

## Everything else

- **Audio + transcription pipeline** (WAV chunks, stubbed Whisper provider),
  transcript UI with click-to-sync, quiz generation (stubbed), inline
  calculator (local eval + AI fallback) — see `docs/PHASES.md` phases 7–9, 12.
- **OwnCloud/WebDAV sync** — LWW block diff engine, core-tested; client
  transport pending (phase 11).
- **Settings/onboarding** — provider keys in Keychain, finger toggle (live
  applied), page header alignment + date/time formats with live preview.
- **Distribution** — unsigned `.ipa` per push via CI, installed through
  LiveContainer; UIKit photo-library picker (PhotosPicker transferable
  loading fails under LiveContainer).
