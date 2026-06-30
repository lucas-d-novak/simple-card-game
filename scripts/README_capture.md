# Live screenshot capture (visual-iteration loop)

`capture_board.mjs` drives a headless Chrome via the DevTools Protocol to
screenshot the running Flutter web build, so UI work can be compared against the
design reference in `ai-docs/design_reference/`.

## One-time setup

```bash
# from repo root
npm init -y
npm install chrome-remote-interface
```

## Each iteration

1. **Serve the app** (terminal A) — pick one:
   ```bash
   flutter run -d web-server --web-port 8123 --release
   # or
   flutter build web && (cd build/web && python -m http.server 8123)
   ```

2. **Launch headless Chrome** (terminal B) — use Chrome or Edge:
   ```bash
   # Windows (Edge):
   "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
     --headless=new --remote-debugging-port=9222 \
     --window-size=1310,604 --hide-scrollbars
   # or Chrome:
   chrome --headless=new --remote-debugging-port=9222 \
     --window-size=1310,604 --hide-scrollbars
   ```

3. **Capture** (terminal C):
   ```bash
   node scripts/capture_board.mjs http://localhost:8123 screenshots/live_board.png
   ```

4. **Compare** `screenshots/live_board.png` against
   `ai-docs/design_reference/01_board_playall.png` (same 2.17:1 aspect), note
   gaps (positions, colors, chrome), refine the Flutter UI, repeat from step 3
   (hot-reload keeps terminal A running).

## Notes
- The capture is 1310×604 @2x DPR — half the mockup's pixel size, identical
  aspect, so side-by-side comparison is 1:1 in layout.
- If the Flutter view isn't detected within 30s the script still captures
  (you'll see a WARN) — useful for catching a blank/boot-failed page.
- Golden tests (`test/screenshot_test.dart`) remain the deterministic,
  CI-excluded check; this live capture is for *design matching* (real fonts,
  real card art), not regression gating.
