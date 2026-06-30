// Zero-click capture of the polished networked board via the ?netgame= route.
// A WS seeder (bob) must already be hosting a waiting game on the server.
// This navigates the browser as a joiner; it auto-joins, the game starts, and
// we screenshot the polished NetworkGameScreen.
//
// Usage: node scripts/capture_net_auto.mjs [outPath] [name]
import CDP from 'chrome-remote-interface';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const out = process.argv[2] ?? 'screenshots/net_board.png';
const name = process.argv[3] ?? 'alice';
const URL = `http://localhost:8123/?netgame=1&name=${name}&host=0&server=ws://localhost:8080`;
const W = 1310, H = 640;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const client = await CDP({ port: 9222 });
  const { Page, Runtime, Emulation } = client;
  await Page.enable();
  await Runtime.enable();
  await Emulation.setDeviceMetricsOverride({ width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await Page.navigate({ url: URL });
  await Page.loadEventFired();
  for (let i = 0; i < 60; i++) {
    const { result } = await Runtime.evaluate({
      expression: `!!document.querySelector('flt-glass-pane, flutter-view, canvas')`,
      returnByValue: true,
    });
    if (result.value) break;
    await sleep(500);
  }
  // Give it time to connect, join, start, and for bob to play+end his turn.
  await sleep(5000);
  const { data } = await Page.captureScreenshot({ format: 'png', fromSurface: true });
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, Buffer.from(data, 'base64'));
  console.log('wrote', out);
  await client.close();
}

main().catch((e) => { console.error('capture failed:', e); process.exitCode = 1; });
