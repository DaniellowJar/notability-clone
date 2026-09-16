# Letter Mode

Write big, commit small: select an area, it zooms to fill the screen width,
you write at large size, and each settled line is normalized to 12 px in
place on the page.

## Lifecycle

1. **Select** — toolbar Letter tool → `.areaSelect(.letterArea)` marquee
   (`CanvasSessionState.startLetterArea`, `endAreaSelect`).
2. **Enter** — `enterLetterArea(_:)` zooms via `LetterMode.zoomToFit`
   (viewport ÷ area width, clamped 1–4x) and parks the area top at
   `letterTopInset`. `letterArea` non-nil switches the ink layer to the
   fading renderer and makes it opaque over the native canvas.
3. **Write** — each captured point calls `trackLetterWriting`, which pans
   the camera via `LetterMode.followOffset` (parks writing at 70% width),
   extends the area/page downward, and (re)starts the 0.8 s settle timer.
4. **Commit** — `commitLetterLine` scales the line's union box to 12 px tall
   around `letterCursor`, clears stale correction overlays, advances the
   cursor (wraps at the area edge), and bumps `drawingRewriteToken` so the
   canvas rebuilds from the store. Out-of-area strokes are skipped.
5. **Exit** — Done / tool switch commits any settled line and clears the
   area (`exitLetterMode`, `cancelTool`). Zoom stays where it was.

## Rendering

- Committed strokes: `LetterModeStrokeRenderer` groups strokes into letter
  clusters by horizontal gap (`letterGap = 8`) and draws newest at full
  color → 0.55 → 0.25 alpha fading toward gray; older hidden
  (`LetterMode.letterClusters`, `clusterAlpha`, `LetterModeAging`).
- In-progress stroke: ephemeral touch-tracked preview drawn last at full
  color, never persisted — the completed PencilKit stroke replaces it on
  lift (`InkStrokeStore.liveStroke`, `Coordinator.handleLiveTouch`).
- Live color comes from the actual `PKInkingTool`, resolved against the
  canvas's own traits every event, with PencilKit begin/end signals as the
  safety net (see BUG-003 in `docs/BUGS.md`).

## Limits (current)

- Preview and committed strokes use a uniform-width polyline renderer —
  no pressure taper or curve smoothing yet (see BUG-004).
- Simultaneous multi-touch drawing tracks a single path; the one-frame
  polyline jump self-corrects on the next event.
- White ink on a light page background is faithfully invisible — that is
  correctness, not a bug; check the DEBUG `live=<hex>` overlay before
  reporting a color issue.
