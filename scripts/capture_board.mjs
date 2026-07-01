// Live screenshot capture of the Flutter web build for visual-iteration.
//
// Prereqs (one-time):
//   npm init -y && npm install chrome-remote-interface
//   # a Chrome/Edge must be reachable (see launch note below)
//
// Usage:
//   1. Start the Flutter web build in another terminal:
//        flutter run -d web-server --web-port 8123 --release
//      (or: flutter build web && serve build/web on :8123)
//   2. Launch Chrome headless with remote debugging on :9222:
//        chrome --headless=new --remote-debugging-port=9222 \
//               --window-size=1310,604 --hide-scrollbars
//   3. node scripts/capture_board.mjs [url] [outPath]
//
// Defaults: url=http://localhost:8123  outPath=screenshots/live_board.png
//
// The script navigates to the app, waits for the Flutter canvas to settle,
// and writes a PNG at the mockup aspect ratio (1310x604 ~= 2.17:1) so it can be
// diffed against ai-docs/design_reference/01_board_playall.png.

import CDP from 'chrome-remote-interface';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const url = process.argv[2] ?? 'http://localhost:8123';
const outPath = process.argv[3] ?? 'screenshots/live_board.png';
const WIDTH = 1310;
const HEIGHT = 604;

async function main() {
  let client;
  try {
    client = await CDP({ port: 9222 });
    const { Page, Runtime, Emulation } = client;
    await Page.enable();
    await Emulation.setDeviceMetricsOverride({
      width: WIDTH,
      height: HEIGHT,
      deviceScaleFactor: 2,
      mobile: false,
    });

    await Page.navigate({ url });
    await Page.loadEventFired();

    // Flutter web boots asynchronously; poll until the canvas/glasspane exists
    // and has painted, then give animations a beat to settle.
    const deadline = Date.now() + 30000;
    let ready = false;
    while (Date.now() < deadline) {
      const { result } = await Runtime.evaluate({
        expression: `(() => {
          const f = document.querySelector('flt-glass-pane, flutter-view, canvas');
          return !!f;
        })()`,
        returnByValue: true,
      });
      if (result.value) { ready = true; break; }
      await new Promise((r) => setTimeout(r, 500));
    }
    if (!ready) console.warn('WARN: Flutter view not detected; capturing anyway.');
    // Give the board a beat to lay out AND decode/paint card-art images.
    await new Promise((r) => setTimeout(r, 3500));

    const { data } = await Page.captureScreenshot({ format: 'png', fromSurface: true });
    mkdirSync(dirname(outPath), { recursive: true });
    writeFileSync(outPath, Buffer.from(data, 'base64'));
    console.log(`Wrote ${outPath} (${WIDTH}x${HEIGHT} @2x)`);
  } catch (err) {
    console.error('Capture failed:', err.message);
    console.error('Is Chrome running with --remote-debugging-port=9222 and the app served at', url, '?');
    process.exitCode = 1;
  } finally {
    if (client) await client.close();
  }
}

main();
