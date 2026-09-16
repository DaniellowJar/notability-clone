# Bugs

Live register of ink/canvas bugs: symptom → root cause → fix → verified by.
Fixed entries stay (with commit) so regressions are easy to spot.

| ID | Symptom | Root cause | Fix | Status |
|---|---|---|---|---|
| BUG-001 | Normal mode: nothing visible while painting, line "popped up" only on lift; default (white/`.label`) ink rendered black | Opaque custom ink layer hid PencilKit's native live ink and only drew completed strokes; `hexString` called `getRed` on unresolved dynamic colors | Coordinator mirrors the full live drawing; `hexString` resolves against the trait collection with a CGColor fallback (`App/Sources/Ink/UIColorHex.swift`); see `6728181` | ✅ fixed |
| BUG-002 | Same pop-on-lift returned after the custom layer went opaque again | Custom layer covered native ink in all modes | Native ink restored for normal mode; custom fading renderer only covers the canvas in Letter Mode (`opacity` toggle in `App/Sources/Views/RecordCanvasView.swift`); see `9a60977` | ✅ fixed |
| BUG-003 | Letter Mode: white picker ink draws black; other colors appear only after lifting the pencil | Touch-tracked preview sampled `canvas.tool` once per stroke and resolved the color against ambient `UITraitCollection.current` (wrong during touch dispatch, stale `#000000` default); end-of-stroke reset sat behind the drawable guard; no PencilKit stroke-begin/end safety net | `snapshotLiveTool(from:)` resolves against `canvas.traitCollection` on every touch event; `canvasViewDidBeginUsingTool` pre-snapshots color/width and clears stale points; `ended` resets before the drawable guard; `canvasViewDidEndUsingTool` clears stale preview state; DEBUG overlay shows `live=<hex>` (`App/Sources/Views/RecordCanvasView.swift`, `App/Sources/Ink/UIColorHex.swift`) | ✅ fixed, needs device check |
| BUG-004 | Scribble looks blurry/pixelated on zoom — "painting in PNG, not SVG" | Zoom is a parent `.scaleEffect` bitmap magnification (PK tiles are 1x, custom layer re-rasterizes a frame late); custom renderer is a uniform-width `addLine` polyline with no smoothing or pressure taper; capture round-trip keeps only raw control points and forces `.pen` | Planned: vector-quality renderer (curve fit + variable-width ribbon + tool/opacity in `StrokeData`) and zoom that re-rasterizes instead of stretching (UIScrollView host or CTM-scale draw) | ◑ open |

## How to report a new entry

Add a row: what you did, what you expected, what you saw (photo helps),
mode (normal/Letter), light/dark, pen color, zoom %. Keep the root-cause
column empty until investigated — don't guess in the register.
