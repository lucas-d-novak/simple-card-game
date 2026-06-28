# Visual Iteration System: Automated Screenshot-Driven Development

> Research document for the simple-card-game Flutter project.
> Last updated: 2026-06-27
>
> **Cross-references**: Target aesthetic defined by faction colors/themes in `frontend_assets_research.md` Section 7. Game layout requirements derived from card anatomy in `shards_of_infinity_mechanics.md` Section 11.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Screenshot Capture in Flutter](#2-screenshot-capture-in-flutter)
3. [Golden Testing in Flutter](#3-golden-testing-in-flutter)
4. [Headless Browser Screenshot Tools](#4-headless-browser-screenshot-tools)
5. [Visual Comparison Approaches](#5-visual-comparison-approaches)
6. [Automated Visual QA Workflows](#6-automated-visual-qa-workflows)
7. [Claude Code Screenshot Capabilities](#7-claude-code-screenshot-capabilities)
8. [End-to-End Loop Design](#8-end-to-end-loop-design)
9. [Recommended Toolchain](#9-recommended-toolchain)
10. [Step-by-Step Workflow](#10-step-by-step-workflow)
11. [Research Confidence](#11-research-confidence)
12. [Known Limitations and Fallbacks](#12-known-limitations-and-fallbacks)

---

## 1. Executive Summary

The goal is a loop where an AI agent can: build the Flutter web app, capture screenshots, visually evaluate them against the Shards of Infinity aesthetic (sci-fi/fantasy, dark backgrounds, glowing effects, faction colors), suggest and implement improvements, and repeat.

**Recommended approach**: Playwright (via npm) for headless browser screenshot capture of the Flutter web build, combined with Claude Code's native image reading capability for visual evaluation. Flutter golden tests serve as a complementary regression safety net. The full loop is orchestrated by shell scripts that Claude Code can invoke.

---

## 2. Screenshot Capture in Flutter

### Option A: Flutter Golden Tests (widget-level)

Flutter's test framework can render widgets to images and compare them against saved "golden" PNG files.

```dart
// In a test file
testWidgets('card renders correctly', (tester) async {
  await tester.pumpWidget(MyCardWidget(card: testCard));
  await expectLater(
    find.byType(MyCardWidget),
    matchesGoldenFile('goldens/card_widget.png'),
  );
});
```

**How it works:**
- `matchesGoldenFile()` renders the found widget to a PNG image.
- On first run (with `--update-goldens`), it saves the image as the reference.
- On subsequent runs, it compares the current render against the saved golden pixel-by-pixel.
- Run with: `flutter test --update-goldens` to generate/update, `flutter test` to compare.

**Limitations:**
- Renders widgets in a test environment, not a real browser. Text rendering, font loading, and platform-specific rendering may differ from the actual web app.
- Cannot capture the full app in a realistic browser context (scrolling, responsive layout, web-specific rendering).
- Font rendering differs across platforms (Linux CI vs Windows dev vs macOS). This is a well-known pain point -- golden files generated on Windows will fail on Linux CI and vice versa.

**Best for:** Component-level visual regression (individual cards, buttons, dialogs). Not for full-app visual evaluation.

### Option B: Flutter Integration Tests with Screenshots

Flutter's `integration_test` package can drive the real app and take screenshots.

```dart
// integration_test/screenshot_test.dart
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture initial state', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('initial_state');
  });

  testWidgets('capture after drawing cards', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('draw-card-button')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('after_draw');
  });
}
```

**Running for web:**
```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d chrome
```

**Limitations:**
- `takeScreenshot()` support for web is limited. On Android/iOS it works reliably; on web it depends on the driver setup and ChromeDriver.
- Requires ChromeDriver to be installed and running separately for web targets.
- Output format and file destination vary by platform.

**Best for:** Full-app screenshots on mobile. Workable for web but Playwright is simpler.

### Option C: Headless Browser (Playwright/Puppeteer) -- RECOMMENDED for Web

Build the Flutter web app, serve it with a static file server, and use a headless browser tool to navigate and screenshot. See Section 4 for details.

---

## 3. Golden Testing in Flutter

### How the Golden System Works

1. **Generate goldens**: `flutter test --update-goldens` renders each `matchesGoldenFile()` call and saves the PNG.
2. **Compare goldens**: `flutter test` (without the flag) renders again and diffs against the saved PNG. If pixels differ beyond the tolerance, the test fails.
3. **Tolerance**: By default the tolerance is 0 (exact match). You can customize with `goldenFileComparator`:

```dart
void main() {
  // Allow up to 0.5% pixel difference
  goldenFileComparator = _TolerantComparator(0.005);
}

class _TolerantComparator extends LocalFileComparator {
  final double tolerance;
  _TolerantComparator(this.tolerance) : super(Uri.parse('test/'));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    return result.passed || result.diffPercent <= tolerance;
  }
}
```

### Cross-Platform Golden Challenges

The biggest practical issue with Flutter goldens is **platform-dependent text rendering**. A golden generated on Windows will not match on Linux (CI) or macOS. Solutions:

- **Ahem font trick**: Use the `Ahem` test font (all characters render as squares) for layout-only testing. Not useful for visual evaluation.
- **Platform-specific goldens**: Store separate golden directories per platform (`goldens/windows/`, `goldens/linux/`). High maintenance.
- **CI-only goldens**: Generate and compare goldens only on CI (Ubuntu), never locally. Developers update goldens via CI.
- **`alchemist` package**: Third-party package that wraps golden testing with platform-aware comparison and CI helpers. Generates goldens in a controlled rendering environment.

### Using Goldens for Full App Testing

You can golden-test the full `MaterialApp`:

```dart
testWidgets('full app golden', (tester) async {
  await tester.pumpWidget(DeckDrawApp());
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(DeckDrawApp),
    matchesGoldenFile('goldens/full_app_initial.png'),
  );
});
```

This captures the full widget tree rendered at the test surface size (default 800x600). You can change the surface size:

```dart
tester.view.physicalSize = Size(1920, 1080);
tester.view.devicePixelRatio = 1.0;
addTearDown(() => tester.view.resetPhysicalSize());
```

**Verdict**: Goldens are excellent for regression detection ("did something change?") but not for aesthetic evaluation ("does this look good?"). Use them as a safety net, not as the primary visual evaluation tool.

---

## 4. Headless Browser Screenshot Tools

### Playwright (RECOMMENDED)

Playwright is a browser automation framework from Microsoft. It downloads and manages its own browser binaries (Chromium, Firefox, WebKit), so no separate Chrome/ChromeDriver setup is needed.

**Install:**
```bash
npm init -y                    # if no package.json exists
npm install playwright         # installs Playwright + browser binaries
npx playwright install         # downloads Chromium, Firefox, WebKit
```

**Capture script (`scripts/capture_screenshots.mjs`):**
```javascript
import { chromium } from 'playwright';
import { mkdirSync } from 'fs';

const SCREENSHOTS_DIR = './screenshots';
mkdirSync(SCREENSHOTS_DIR, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

// Navigate to the Flutter web app (assumed to be served at localhost:8080)
await page.goto('http://localhost:8080');

// Wait for Flutter to fully render (Flutter web takes a moment to boot)
// The 'flutter-initialized' event or a visible element are good signals.
await page.waitForSelector('flt-glass-pane', { timeout: 30000 });
await page.waitForTimeout(2000); // extra settle time for animations

// Capture initial state
await page.screenshot({ path: `${SCREENSHOTS_DIR}/01_initial_state.png`, fullPage: true });

// Interact: click the draw button
// Flutter web renders to a canvas, so we need to click by coordinates or use
// Semantics mode. For accessibility-enabled Flutter web apps, semantic elements
// are in the DOM.
//
// Option 1: Enable semantics and find by label
// Flutter web in --web-renderer=html mode renders accessible DOM elements.
// Flutter web in --web-renderer=canvaskit renders to canvas (harder to automate).
//
// Option 2: Click by coordinates (works with any renderer)
// Find the "Draw 2 cards" button position and click it.

// For CanvasKit renderer, use coordinate-based clicking:
// You'd need to know where the button is, or use Flutter's integration test
// approach instead.

// For HTML renderer with semantics:
await page.click('text=Draw 2 cards');
await page.waitForTimeout(1000);
await page.screenshot({ path: `${SCREENSHOTS_DIR}/02_after_draw.png`, fullPage: true });

await browser.close();
```

**Key consideration -- Flutter web renderer:**

- **HTML renderer** (`--web-renderer html`): Renders using HTML/CSS/Canvas. DOM elements are inspectable and clickable by Playwright using text selectors, ARIA labels, etc. Easier to automate. Lower visual fidelity.
- **CanvasKit renderer** (`--web-renderer canvaskit`, default in recent Flutter): Renders everything to a single `<canvas>` element using Skia compiled to WASM. The DOM is essentially one canvas -- Playwright cannot find individual UI elements by text. You must either:
  - Enable semantics (adds an accessibility DOM overlay) and interact with those elements.
  - Use coordinate-based clicking.
  - Use Flutter's own integration test driver instead of Playwright for interaction.
- **Skwasm renderer** (newer Flutter): Similar to CanvasKit but uses WebAssembly more aggressively. Same automation challenges.

**For screenshot-only (no interaction needed)**: Any renderer works fine. Playwright just needs to take a picture. This is the primary use case for visual iteration.

**For screenshots + interaction**: Use the HTML renderer, or combine Playwright screenshots with Flutter integration test interaction.

**Windows compatibility**: Playwright works on Windows. `npm install playwright` and `npx playwright install` handle everything. No special configuration needed.

### Puppeteer

Similar to Playwright but Chrome/Chromium only. Slightly older, larger community.

**Install:**
```bash
npm install puppeteer   # downloads Chromium automatically
```

**Capture script:**
```javascript
import puppeteer from 'puppeteer';

const browser = await puppeteer.launch();
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 900 });
await page.goto('http://localhost:8080');
await page.waitForTimeout(3000); // wait for Flutter to boot
await page.screenshot({ path: 'screenshots/initial.png', fullPage: true });
await browser.close();
```

**vs Playwright**: Playwright is preferred because it manages multiple browser engines, has better API design, and is more actively developed. Puppeteer is fine if you already use it.

### Selenium WebDriver

Heavier-weight, requires separate browser driver management (ChromeDriver). Not recommended for this use case -- Playwright does everything Selenium does with less setup.

### dart:io + Chrome DevTools Protocol

You can use Dart directly to control headless Chrome via the Chrome DevTools Protocol (CDP). The `puppeteer-dart` package or `chrome_dev_tools` package provide Dart bindings.

```bash
flutter pub add --dev puppeteer
```

This keeps everything in Dart but the packages are less maintained than the JS equivalents. Not recommended unless you want to avoid Node.js entirely.

---

## 5. Visual Comparison Approaches

### Pixel-Level Diff Tools

**`pixelmatch`** (npm): Fast pixel-level image comparison.

```bash
npm install pixelmatch pngjs
```

```javascript
import { readFileSync, writeFileSync } from 'fs';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';

const img1 = PNG.sync.read(readFileSync('screenshots/before.png'));
const img2 = PNG.sync.read(readFileSync('screenshots/after.png'));
const { width, height } = img1;
const diff = new PNG({ width, height });

const numDiffPixels = pixelmatch(
  img1.data, img2.data, diff.data, width, height,
  { threshold: 0.1 }
);

writeFileSync('screenshots/diff.png', PNG.sync.write(diff));
console.log(`Different pixels: ${numDiffPixels} (${(numDiffPixels / (width * height) * 100).toFixed(2)}%)`);
```

**Use case**: Detect regressions between iterations. "Did my change affect only the area I intended?"

### Perceptual Diff Tools

**`looks-same`** (npm, from Yandex/Gemini): Perceptual comparison that ignores anti-aliasing differences.

```bash
npm install looks-same
```

Better than raw pixel diff for Flutter web because anti-aliasing can vary slightly between builds.

### AI-Based Visual Evaluation (RECOMMENDED for aesthetic judgment)

For evaluating whether screenshots match a design vision (sci-fi aesthetic, dark backgrounds, faction colors), pixel diff is useless. You need a model that understands visual design.

**Approach: Feed screenshots directly to Claude Code.**

Claude Code (and the Claude model it runs on) can read PNG/JPG images natively. The workflow:

1. Capture screenshots to `screenshots/` directory.
2. Claude Code reads the screenshots using its `Read` tool.
3. Claude evaluates against the design goals (provided as text context in CLAUDE.md or a design doc).
4. Claude suggests specific code changes.

This is the core of the visual iteration loop. See Section 7 for details.

### Hybrid: Pixel Diff + AI Evaluation

Use pixel diff to quantify what changed between iterations. Feed both the screenshot and the diff image to Claude for evaluation:
- "Here is the current screenshot and a diff showing what changed since the last iteration. Evaluate whether the changes improved the visual design toward our Shards of Infinity aesthetic goals."

---

## 6. Automated Visual QA Workflows

### BackstopJS

Visual regression testing tool built on Puppeteer. Captures screenshots, compares against references, generates HTML reports with diff overlays.

```bash
npm install -g backstopjs
backstop init
backstop test
backstop approve   # accept current screenshots as new references
```

**Configuration (`backstop.json`):**
```json
{
  "id": "simple_card_game",
  "viewports": [
    { "label": "desktop", "width": 1280, "height": 900 },
    { "label": "mobile", "width": 375, "height": 812 }
  ],
  "scenarios": [
    {
      "label": "Initial State",
      "url": "http://localhost:8080",
      "delay": 3000,
      "misMatchThreshold": 0.1
    }
  ],
  "engine": "puppeteer"
}
```

**Pros**: Purpose-built for visual regression. HTML report with side-by-side comparison. Good for CI.
**Cons**: No aesthetic judgment -- only detects changes, not whether they look good. Requires the app to be served.

### Percy (BrowserStack)

Cloud-based visual testing service. Captures screenshots, stores them, provides a web UI for review.

```bash
npm install @percy/cli @percy/playwright
```

**Pros**: Cross-browser snapshots, team review UI, good CI integration.
**Cons**: Cloud service (requires account), costs money at scale, overkill for a single-developer project. Adds latency to the iteration loop because screenshots are uploaded to their cloud.

### Chromatic (Storybook ecosystem)

Designed for React/Storybook component testing. Not directly applicable to Flutter.

### Flutter-Specific: `alchemist` Package

```bash
flutter pub add --dev alchemist
```

Provides enhanced golden test infrastructure:
- Platform-aware golden generation (uses `GoldenTestGroup` and `GoldenTestScenario`)
- Can group multiple widget variants into a single golden image
- CI-friendly (generates goldens in CI, stores them as artifacts)

**Best for**: Component-level visual regression within Flutter's test framework.

### Recommended for This Project

- **Primary**: Playwright screenshots + Claude Code evaluation (aesthetic judgment).
- **Secondary**: Flutter golden tests with `alchemist` for component-level regression.
- **Optional**: BackstopJS if you want an HTML report with diff overlays for before/after comparison during iteration.

---

## 7. Claude Code Screenshot Capabilities

### How Claude Code Reads Images

Claude Code's `Read` tool can read image files (PNG, JPG, etc.). When it reads an image, the contents are presented visually to the Claude model, which is multimodal. This means Claude can:

- Describe what it sees in a screenshot
- Evaluate layout, color, typography, spacing
- Compare a screenshot against a textual description of desired aesthetics
- Identify specific UI elements and suggest CSS/widget-level changes
- Compare two screenshots and describe differences

### Optimal Screenshot Pipeline for Claude Code

1. **File format**: PNG (lossless). Screenshots from Playwright default to PNG.
2. **Resolution**: 1280x900 or similar desktop viewport. Avoid extremely large screenshots (>4000px wide) as they may be downscaled by the model.
3. **File location**: Store in `screenshots/` directory in the project root. Use descriptive filenames: `01_initial_state.png`, `02_after_draw.png`, etc.
4. **Context**: Provide a design brief in CLAUDE.md or a separate `ai-docs/design_goals.md` that describes the target aesthetic. Example:

```markdown
## Visual Design Goals

Target aesthetic: Shards of Infinity card game
- Dark background (deep space / void theme): #0a0a1a to #1a1a2e
- Glowing effects on cards and buttons (box shadows with faction colors)
- Faction colors:
  - Wraethe (red/orange): #ff4444, #ff6600
  - Homodeus (blue/cyan): #00aaff, #00ffff
  - Order (gold/white): #ffd700, #ffffff
  - Undergrowth (green): #00cc44, #44ff88
- Card frames: Dark metallic with colored borders matching faction
- Typography: Sharp, angular sci-fi fonts for titles; clean sans-serif for body
- UI chrome: Minimal, translucent panels with subtle glow edges
- Animations: Card play should have energy burst effects; purchases should shimmer
```

5. **Evaluation prompt pattern**: When Claude Code reads a screenshot, pair it with a directive:
   - "Read `screenshots/01_initial_state.png` and evaluate how well it matches our design goals in `ai-docs/design_goals.md`. Suggest 3-5 specific code changes to improve the visual design."

### Feeding Multiple Screenshots

For comparing before/after:
1. Capture "before" screenshot.
2. Make code changes.
3. Rebuild and recapture "after" screenshot.
4. Have Claude read both and compare.

Claude can read multiple images in a conversation. The model will see them and can compare them.

### Limitations

- Claude cannot execute code to generate screenshots itself -- it needs a tool (Playwright script) to do the capture, then it reads the resulting file.
- Very subtle color differences (e.g., #1a1a2e vs #1b1b2f) may not be distinguishable in a screenshot viewed by the model.
- The model sees a rasterized image, not the widget tree. It can suggest "make this button bigger" but may not know the exact widget path without also reading the code.

---

## 8. End-to-End Loop Design

### Architecture

```
+------------------+     +------------------+     +-------------------+
|  1. Build        | --> |  2. Serve        | --> |  3. Capture       |
|  flutter build   |     |  static server   |     |  Playwright       |
|  web             |     |  on port 8080    |     |  screenshots      |
+------------------+     +------------------+     +-------------------+
                                                           |
                                                           v
+------------------+     +------------------+     +-------------------+
|  6. Rebuild      | <-- |  5. Implement    | <-- |  4. Evaluate      |
|  (go to step 1)  |     |  Code changes    |     |  Claude reads     |
|                  |     |  (Claude Code)   |     |  screenshots      |
+------------------+     +------------------+     +-------------------+
```

### Script: `scripts/build_and_serve.sh`

```bash
#!/bin/bash
# Build Flutter web app and serve it locally
set -e

echo "Building Flutter web app..."
flutter build web --web-renderer canvaskit --release

echo "Serving on http://localhost:8080..."
# Use npx serve (static file server) or Python's http.server
# Option 1: Node.js serve
npx serve build/web -l 8080 &
SERVER_PID=$!

# Option 2: Python (if available)
# cd build/web && python -m http.server 8080 &
# SERVER_PID=$!

echo "Server PID: $SERVER_PID"
echo $SERVER_PID > .server_pid

# Wait for server to be ready
sleep 2
echo "Server ready at http://localhost:8080"
```

### Script: `scripts/capture_screenshots.mjs`

```javascript
import { chromium } from 'playwright';
import { mkdirSync, existsSync } from 'fs';
import { join } from 'path';

const SCREENSHOTS_DIR = './screenshots';
const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const outputDir = join(SCREENSHOTS_DIR, timestamp);
mkdirSync(outputDir, { recursive: true });

const browser = await chromium.launch({ headless: true });

// Desktop viewport
const desktopPage = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await desktopPage.goto('http://localhost:8080');
await desktopPage.waitForTimeout(4000); // Flutter boot time
await desktopPage.screenshot({ path: join(outputDir, 'desktop_initial.png') });

// Mobile viewport
const mobilePage = await browser.newPage({ viewport: { width: 375, height: 812 } });
await mobilePage.goto('http://localhost:8080');
await mobilePage.waitForTimeout(4000);
await mobilePage.screenshot({ path: join(outputDir, 'mobile_initial.png') });

await browser.close();

console.log(`Screenshots saved to ${outputDir}`);
// Write latest path for easy reference
import { writeFileSync } from 'fs';
writeFileSync(join(SCREENSHOTS_DIR, 'latest'), outputDir);
```

### Script: `scripts/stop_server.sh`

```bash
#!/bin/bash
if [ -f .server_pid ]; then
  kill $(cat .server_pid) 2>/dev/null
  rm .server_pid
  echo "Server stopped."
else
  echo "No server PID found."
fi
```

### Full Iteration Cycle (Manual via Claude Code)

The AI agent (Claude Code) would execute these steps in sequence:

1. **Build**: Run `flutter build web --web-renderer canvaskit`
2. **Serve**: Run `npx serve build/web -l 8080 &` (background process)
3. **Capture**: Run `node scripts/capture_screenshots.mjs`
4. **Evaluate**: Read the captured screenshots with the `Read` tool, compare against design goals
5. **Implement**: Edit Dart source files based on evaluation
6. **Loop**: Kill server, go to step 1

### Dev Server Lifecycle Management

**Option A: Rebuild each iteration** (simple, reliable)
- Kill server, rebuild, re-serve, recapture.
- ~30-60 seconds per iteration depending on build speed.
- Most reliable -- no stale state.

**Option B: Flutter web dev server with hot reload** (faster, less reliable for screenshots)
- Run `flutter run -d chrome --web-port=8080` which supports hot reload.
- After code changes, hot reload updates the running app.
- Take screenshots without rebuilding.
- Risk: hot reload can sometimes leave stale state. Full restart needed occasionally.
- Faster iteration: ~5-10 seconds per cycle.

**Option C: `flutter build web` + watch mode** (middle ground)
- Use a file watcher (e.g., `chokidar`) to rebuild on source changes.
- Not natively supported by Flutter -- would need a wrapper script.

**Recommendation**: Start with Option A for reliability. Move to Option B once the workflow is proven and speed becomes the bottleneck. The `flutter run -d chrome` approach is actually the simplest for a human developer but harder for an AI agent to manage because the dev server is a long-running interactive process.

---

## 9. Recommended Toolchain

### Core Tools

| Tool | Purpose | Install |
|------|---------|---------|
| **Flutter SDK** | Build the app | Already installed (v3.41.5) |
| **Node.js + npm** | Run Playwright and helper scripts | Install from nodejs.org or `winget install OpenJS.NodeJS.LTS` |
| **Playwright** | Headless browser screenshots | `npm install playwright && npx playwright install chromium` |
| **serve** (npm) | Static file server for built web app | `npm install serve` (or use as `npx serve`) |
| **Claude Code** | Visual evaluation + code changes | Already available |

### Optional / Enhancement Tools

| Tool | Purpose | Install |
|------|---------|---------|
| **pixelmatch + pngjs** | Pixel-level diff between screenshots | `npm install pixelmatch pngjs` |
| **BackstopJS** | Visual regression reports with HTML diff UI | `npm install backstopjs` |
| **alchemist** (pub.dev) | Enhanced Flutter golden tests | `flutter pub add --dev alchemist` |

### Setup Commands (One-Time)

```bash
# From project root
cd C:/Users/rldun/code/simple-card-game

# Initialize npm (if no package.json)
npm init -y

# Install Playwright (with Chromium only to save disk space)
npm install playwright
npx playwright install chromium

# Install static file server
npm install serve

# Optional: pixel diff tools
npm install pixelmatch pngjs

# Create directories
mkdir -p scripts screenshots
```

### .gitignore Additions

```
# Visual iteration system
screenshots/
node_modules/
.server_pid
```

---

## 10. Step-by-Step Workflow

### Prerequisites

1. Flutter SDK installed and on PATH (v3.41.5)
2. Node.js and npm installed and on PATH
3. Playwright installed (`npm install playwright && npx playwright install chromium`)
4. `serve` installed (`npm install serve`)

### Workflow for AI Agent (Claude Code)

#### Phase 1: Capture Current State

```
Step 1: Build the web app
  $ flutter build web --web-renderer canvaskit

Step 2: Start the server
  $ npx serve build/web -l 8080 &

Step 3: Wait for server readiness (2 seconds)

Step 4: Run screenshot capture
  $ node scripts/capture_screenshots.mjs

Step 5: Stop the server
  $ kill %1   (or use the PID)
```

#### Phase 2: Evaluate

```
Step 6: Read the screenshots
  Use Claude Code's Read tool on each PNG in screenshots/latest/

Step 7: Compare against design goals
  Reference ai-docs/design_goals.md (to be created) for target aesthetic.
  Evaluate: colors, layout, typography, spacing, overall vibe.

Step 8: Identify top 3-5 improvements
  Prioritize highest-impact visual changes.
```

#### Phase 3: Implement

```
Step 9: Edit source files
  Modify lib/ui/ files, lib/main.dart theme, widget styling.

Step 10: Verify the build compiles
  $ flutter build web --web-renderer canvaskit

Step 11: If errors, fix and retry.
```

#### Phase 4: Verify

```
Step 12: Re-serve and recapture (repeat Phase 1)

Step 13: Read new screenshots and compare against previous iteration.

Step 14: Evaluate improvement. If satisfactory, stop. If not, loop to Phase 3.
```

### Workflow for Human Developer

1. Run `flutter run -d chrome` for live preview.
2. Ask Claude Code to evaluate specific screens: "Read `screenshots/current_state.png` and suggest visual improvements for the Shards of Infinity aesthetic."
3. Apply Claude's suggestions.
4. Manually screenshot (or use Playwright script) and ask Claude to compare.

---

## 11. Research Confidence

| Area | Confidence | Notes |
|------|-----------|-------|
| **Flutter golden tests** | HIGH | Well-documented Flutter feature. Cross-platform font rendering pain is well-known. Suitable for regression, not aesthetic evaluation. |
| **Playwright on Windows** | HIGH | Playwright has first-class Windows support. Self-contained Chromium download. Widely used in web testing. |
| **Flutter web renderer + Playwright interaction** | MEDIUM | CanvasKit renders to a single `<canvas>` element -- Playwright cannot find individual widgets. For screenshot-only (no interaction), this is not a problem. For interaction, HTML renderer or Flutter integration tests are needed. |
| **Claude Code image reading** | HIGH | Documented capability of Claude Code's `Read` tool. Multimodal model can evaluate visual design from PNG images. |
| **Pixel diff tools (pixelmatch)** | HIGH | Mature, well-maintained npm packages. Straightforward API. |
| **BackstopJS** | MEDIUM-HIGH | Established tool but depends on Puppeteer, which occasionally has compatibility issues on Windows. Playwright-based alternatives may be more reliable. |
| **Flutter integration_test screenshots on web** | MEDIUM-LOW | This area is less mature. `takeScreenshot()` is primarily designed for mobile platforms. Web support requires ChromeDriver and has rough edges. Playwright is more reliable for web screenshots. |
| **End-to-end loop automation** | MEDIUM | The individual pieces are well-proven. The orchestration (server lifecycle, timing, error handling) requires careful scripting. The main risk is Flutter web build time (~30-60s) making the loop slow. |
| **Hot reload in automation loop** | LOW | Hot reload with `flutter run -d chrome` works for humans but is harder to drive programmatically. The dev server is interactive and its state management during automated screenshot capture is unpredictable. |
| **`alchemist` package** | MEDIUM | Third-party package -- API may change. Need to verify current version compatibility with Flutter 3.41.5. |

---

## 12. Known Limitations and Fallbacks

### Limitation 1: Flutter Web Boot Time

**Problem**: Flutter web apps (especially CanvasKit) take 2-5 seconds to boot in a browser. Screenshots taken too early will show a blank page or loading indicator.

**Mitigation**: Use `page.waitForTimeout(4000)` in Playwright, or better, wait for a specific DOM element:
```javascript
// Wait for Flutter's glass pane to appear
await page.waitForSelector('flt-glass-pane', { timeout: 30000 });
// Then wait extra for rendering to settle
await page.waitForTimeout(2000);
```

**Fallback**: If timing is unreliable, take 3 screenshots at 2s, 4s, 6s and use the last one.

### Limitation 2: CanvasKit Interaction

**Problem**: With CanvasKit renderer, Playwright cannot click buttons by text or ARIA role because the DOM is a single `<canvas>`.

**Mitigation for screenshot-only**: Not a problem -- just capture the visual.

**Mitigation for interaction**: Either:
1. Build with `--web-renderer html` for Playwright interaction.
2. Use Flutter integration tests for interaction, Playwright for screenshots only.
3. Use coordinate-based clicking (`page.click({ position: { x: 500, y: 300 } })`), though this is brittle.

**Fallback**: For the visual iteration loop, interaction is often unnecessary. The AI agent can modify code to set specific game states directly (e.g., inject a `DeckService` in a known state) and screenshot those states without needing to click buttons.

### Limitation 3: Build Speed

**Problem**: `flutter build web` takes 30-60 seconds. Each iteration of the loop requires a full rebuild.

**Mitigation**: Use `flutter build web --debug` for faster builds (no tree-shaking/minification). Visual appearance is identical.

**Fallback**: Use `flutter run -d chrome --web-port=8080` for hot reload during rapid iteration, falling back to full rebuild for final screenshots.

### Limitation 4: Font Rendering Differences

**Problem**: Text may render slightly differently between local dev (Windows) and CI (Linux) or between debug and release builds.

**Mitigation**: Accept minor font differences. Use `looks-same` instead of `pixelmatch` for perceptual comparison. Focus AI evaluation on layout, colors, and overall design rather than pixel-perfect text rendering.

**Fallback**: Run the full capture pipeline in CI (Linux) for consistent results across team members.

### Limitation 5: Claude Code Cannot Run Long-Lived Processes Easily

**Problem**: The build-serve-capture loop requires a background server process. Claude Code's bash tool may have timeout limitations or difficulty managing background processes across calls.

**Mitigation**: Use a single script that builds, serves, captures, and kills the server in one invocation:
```bash
#!/bin/bash
set -e
flutter build web --web-renderer canvaskit
npx serve build/web -l 8080 &
SERVER_PID=$!
sleep 3
node scripts/capture_screenshots.mjs
kill $SERVER_PID
```

**Fallback**: Have the human developer start the server manually (`flutter run -d chrome`) and have Claude Code only run the Playwright capture script against the already-running server.

### Limitation 6: Screenshot File Size

**Problem**: Full-page screenshots at high resolution can be several MB. Multiple screenshots per iteration add up.

**Mitigation**: Use standard viewport sizes (1280x900). Crop to specific areas of interest when possible. Clean up old screenshot directories periodically.

**Fallback**: Reduce viewport size or use JPEG format (lossy but smaller) for intermediate iterations, PNG for final captures.

---

## Appendix A: Alternative Approach -- Flutter Driver Screenshots

If Playwright proves problematic, Flutter's own `flutter_driver` (deprecated in favor of `integration_test`) or `integration_test` can capture screenshots natively:

```yaml
# pubspec.yaml additions
dev_dependencies:
  integration_test:
    sdk: flutter
```

```dart
// integration_test/visual_capture_test.dart
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_card_game/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture all states', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // The binding.takeScreenshot method works on Android/iOS.
    // For web, this requires ChromeDriver.
    await binding.takeScreenshot('initial');
  });
}
```

Run with:
```bash
# Requires ChromeDriver running on port 4444
chromedriver --port=4444 &
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/visual_capture_test.dart \
  -d web-server --web-port=8080
```

This is more complex to set up than Playwright but stays entirely within the Flutter ecosystem.

## Appendix B: Design Goals Template

Create this file at `ai-docs/design_goals.md` to guide visual evaluation:

```markdown
# Visual Design Goals: Shards of Infinity Digital Edition

## Overall Aesthetic
- Sci-fi/fantasy fusion: advanced technology meets cosmic mysticism
- Dark, atmospheric backgrounds suggesting deep space or dimensional rifts
- Glowing accent effects: neon edges, particle trails, energy auras

## Color Palette
- Background: Deep void (#0a0a1a), dark purple-blue (#1a1a2e)
- Text: White (#ffffff) with occasional faction-colored highlights
- Faction colors:
  - Wraethe: Crimson red (#cc2244) to fiery orange (#ff6600)
  - Homodeus: Electric blue (#0088ff) to cyan (#00ffff)
  - Order: Radiant gold (#ffd700) to pure white (#ffffff)
  - Undergrowth: Forest green (#00aa44) to toxic green (#44ff88)

## Card Design
- Dark card frames with thin glowing borders in faction color
- Card art area: central illustration zone
- Card cost: top-left gem/crystal icon
- Card name: bottom, bold sci-fi font
- Card effect text: smaller, clean sans-serif

## UI Chrome
- Translucent panels with subtle backdrop blur
- Minimal borders -- use glow/shadow instead of hard lines
- Buttons: Dark with glowing faction-colored borders on hover
- Health/mastery counters: Circular with radial glow

## Typography
- Headings: Angular, techy sans-serif (e.g., Orbitron, Exo 2, Rajdhani)
- Body text: Clean sans-serif (e.g., Inter, Source Sans Pro)
- Card names: Bold, slightly condensed
- Numbers: Monospace or tabular for alignment

## Animations (future)
- Card draw: Slide from deck with slight rotation
- Card play: Energy burst particle effect
- Purchase: Shimmer wave across card
- Damage: Screen shake + red flash
- Mastery level-up: Radial pulse + color shift
```
