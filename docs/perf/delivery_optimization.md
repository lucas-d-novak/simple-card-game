# Web delivery optimization — Pi + python static server + Cloudflare free tier

Status: read-only measurement pass, captured 2026-07-01 on the deploy Pi
(Raspberry Pi 4B) against the live site `https://sharts.love`. No live service,
systemd unit, build config, or Cloudflare setting was changed. Everything below
is measurements + **proposed** configs to review before applying.

Scope: optimize *delivery* of the Flutter **web** build at this resolution
(Pi → `python3 -m http.server` → Cloudflare Tunnel free tier → client) **without
breaking the version-poll cache-bust** (`web/index.html` polls
`version.json?ts=` every 30 s and hard-reloads on a new build SHA). WebSocket
payload work is out of scope — see `docs/perf/profiling_baseline.md`.

---

## Headline

- **Cloudflare is NOT edge-caching the app code.** Every asset that matters for
  first paint returns `cf-cache-status: DYNAMIC` — `/`, `main.dart.js`,
  `flutter_bootstrap.js`, `version.json`. So **every page load falls through the
  tunnel to the Pi.** (Card images *are* cached: they return `MISS` → will become
  `HIT`.)
- **Biggest transfer = `main.dart.js`, 2,988,720 bytes (2.99 MB) raw.** The Pi
  ships it uncompressed to the CF edge on every load. Cloudflare *does*
  auto-compress it to the browser (zstd → 920 KB), but the Pi→edge hop is the
  full 2.99 MB every time because it isn't cached and python sends no compression.
- **CanvasKit (5.7–7.2 MB wasm) does NOT hit the Pi** — it loads from Google's
  `gstatic.com` CDN (Flutter default), already brotli'd and `immutable`. Leave it.
- **Nothing in the build is content-hashed** (`main.dart.js`,
  `flutter_bootstrap.js`, etc. keep stable names across deploys). This is the
  single constraint that shapes the whole caching strategy: any long edge cache
  on `main.dart.js` **must** be paired with a deploy-time purge, or a redeploy
  serves stale JS and the version-poll reload loads old code.

### Top 3 clean wins

1. **Edge-cache `main.dart.js` (Edge TTL long, Browser TTL 0) + purge on deploy.**
   Turns the biggest transfer from `DYNAMIC` (every visitor pulls 2.99 MB from the
   Pi) into a CF edge `HIT` (Pi serves it ~once per PoP per TTL). Browser TTL stays
   0 so the version-poll reload still picks up new builds. Requires a cache-purge
   step in the deploy.
2. **Swap `python3 -m http.server` → Caddy.** One change delivers correct
   `Cache-Control` per path (enables win 1 with no CF dashboard access),
   gzip/zstd on the origin→edge hop, and HTTP keep-alive (python is HTTP/1.0,
   new TCP per request). ~8-line Caddyfile.
3. **Enable Cloudflare Tiered Cache (Web) — free, zero risk.** One upper-tier PoP
   fills the others, so the Pi answers far fewer cache-fill fetches for the newly
   cacheable JS and the card art.

Everything else (brotli precompression, `--wasm`, deferred loading, card-image
recompression) is either marginal at this resolution or an asset/build change,
not a delivery-config win — detailed at the bottom.

---

## 1. Current serving reality

### Origin: `shards-web.service`

```
ExecStart=/usr/bin/python3 -m http.server 8123 --bind 127.0.0.1 \
          --directory /home/sfg/code/simple-card-game/build/web
```

- Python **3.12.3**. `python -m http.server` here uses **`ThreadingHTTPServer`**,
  so it *does* serve concurrent requests on threads — the "single-threaded"
  assumption is outdated for this Python. (`build/web` disk footprint is 124 MB,
  so the process stays small; peak RSS ~37 MB.)
- **Protocol is HTTP/1.0** (`BaseHTTPRequestHandler.protocol_version = 'HTTP/1.0'`)
  → no keep-alive, a fresh TCP connection per request between cloudflared and the
  origin.
- **Sends no `Cache-Control`** and **no compression** — this is why Cloudflare
  can't tell the app JS is cacheable and why the Pi→edge hop is uncompressed.
- Bound to `127.0.0.1` — only local cloudflared reaches it. Good.

### Tunnel: `shards-tunnel.service` (`config-sharts.yml`)

```
/ws*  → http://localhost:8080   (Dart WebSocket game server)
/     → http://localhost:8123   (this static web app)
```
Path split on one hostname; `www` mirrors apex. Cloudflare Tunnel, FREE tier.

### Loader chain (`web/index.html`)

- `index.html` loads **only** `flutter_bootstrap.js` (async). `flutter.js` is
  **not** referenced separately (the loader is inlined into bootstrap).
- `flutter_bootstrap.js` buildConfig: `renderer: "canvaskit"`,
  `compileTarget: "dart2js"` → loads `main.dart.js` (dart2js output) and
  CanvasKit. `useLocalCanvasKit` is not set, so CanvasKit loads from
  `https://www.gstatic.com/flutter-canvaskit/<engineRevision>/` (CDN), **not**
  the Pi. The bundled `build/web/canvaskit/*` files are dead weight on disk.
- The **version-poll** (inline `<script>` in index.html) fetches
  `version.json?ts=<now>` with `{cache:'no-store'}` every 30 s + on focus/online;
  on a changed `build` SHA it unregisters the SW, clears Cache-API caches, and
  hard-reloads once. **The must-stay-fresh files are: `version.json`,
  `index.html`, and `flutter_bootstrap.js`** (bootstrap carries the
  per-build `serviceWorkerVersion` and the reference to `main.dart.js`).

### Asset inventory + sizes (`build/web`)

| Asset | Bytes | Content-hashed name? | Fetched from Pi on load? |
|---|---:|---|---|
| `index.html` | 4,970 | no (entry) | yes — must stay fresh |
| `flutter_bootstrap.js` | 9,975 | no (changes per build) | yes — must stay fresh |
| `flutter.js` | 9,553 | no | not referenced (unused) |
| `version.json` | 23 | no (poll target) | yes, every 30 s — must stay fresh |
| **`main.dart.js`** | **2,988,720** | **no (stable name!)** | **yes — the big one** |
| `flutter_service_worker.js` | 784 | no | yes (self-unregistering stub) |
| `manifest.json` | 945 | no | yes |
| `assets/NOTICES` | 1,331,405 | no | only if licenses page opened |
| `assets/AssetManifest.bin` | ~16 K | no | yes (small) |
| `assets/fonts/MaterialIcons-Regular.otf` | 11,652 | no (tree-shaken) | yes (small) |
| `assets/assets/cards/*.jpg` | **88 MB / 203 files** | no | on demand (largest weight) |
| `canvaskit/*` (wasm 3.5–7.2 MB) | ~25 MB | no | **NO — loads from gstatic CDN** |

Largest single card images: `carnivorous_vine.jpg` 2.49 MB, `swyft.jpg` 2.23 MB,
`cinder_scars.jpg` 2.20 MB. **No source maps** are emitted (`--release` default),
so that lever is already handled.

---

## 2. What clients actually get through the tunnel (live `curl`)

Measured against `https://sharts.love`, 2026-07-01. `enc=` is with the browser's
`Accept-Encoding` (via `curl --compressed`); browsers always send it.

| Request | HTTP | `cf-cache-status` | `Cache-Control` (from CF) | `Content-Encoding` | Bytes to client |
|---|---|---|---|---|---|
| `/` (index.html) | h2 200 | **DYNAMIC** | *(none)* | zstd | ~2 KB (5 KB raw) |
| **`main.dart.js`** | h2 200 | **DYNAMIC** | *(none)* | **zstd** | **920,093** (2,988,720 raw) |
| `flutter_bootstrap.js` | h2 200 | **DYNAMIC** | *(none)* | zstd | ~4 KB |
| `version.json` | h2 200 | **DYNAMIC** | *(none)* | — | 23 |
| `assets/.../malice.jpg` | h2 200 | **MISS** (→HIT) | `max-age=14400` *(CF-added)* | — (jpeg) | 2,077,067 |
| `canvaskit/chromium/canvaskit.wasm` | h2 200 | DYNAMIC | *(none)* | — | 5,686,836 *(but not requested in normal load — served by gstatic instead)* |

Reading the table:

- **App code = `DYNAMIC` everywhere.** Cloudflare is serving it straight from the
  Pi on every hit and not storing it. The Pi is doing all the work for every
  visitor, worldwide, on every load.
- **Card images = cacheable.** CF added `Cache-Control: max-age=14400` on its own
  and returned `MISS` (first fetch) → subsequent fetches become `HIT` and offload
  the Pi. The 88 MB of card art is already largely handled at the edge.
- **Compression to the browser is already on** — CF free tier auto-compresses
  text/js with **zstd** on the fly (`main.dart.js` 2.99 MB → 920 KB), *even for
  `DYNAMIC` responses*. So the client-facing compression win is mostly already
  realized. What is **not** compressed is the **origin→edge hop**: python sends
  raw bytes, so the Pi pushes the full 2.99 MB to the edge on every `DYNAMIC` hit.

### Compression potential (measured locally; `brotli` not installed, `gzip` is)

| File | raw | gzip -9 | CF zstd (observed) | est. brotli -11 |
|---|---:|---:|---:|---:|
| `main.dart.js` | 2,988,720 | 868,141 | 920,093 | ~750 K |
| `flutter.js` | 9,553 | 3,679 | — | — |
| `index.html` | 4,970 | 2,161 | ~2 K | — |
| `canvaskit/chromium/canvaskit.wasm` | 5,686,836 | 2,157,622 | (from gstatic, br) | — |
| card `.jpg` (already compressed) | 2,077,067 | 2,024,549 | — | **don't compress** |

Takeaway: precompressed brotli would beat CF's on-the-fly zstd by only ~170 KB on
`main.dart.js`. The real prize is **not re-shipping the 2.99 MB from the Pi at
all** (edge caching), not squeezing the last 170 KB.

---

## 3. Prioritized clean wins

| # | Win | Effect | Effort | Risk | Applied where |
|---|---|---|---|---|---|
| 1 | **Edge-cache `main.dart.js`** (Edge TTL long, Browser TTL 0) **+ purge on deploy** | Biggest transfer becomes a CF `HIT`; Pi stops shipping 2.99 MB per visitor; faster first paint (edge-local) | Med | **Med** — stable filename means a deploy without purge serves stale JS → must add purge; must keep index/version/bootstrap uncached | Origin `Cache-Control` (via Caddy) **or** CF Cache Rule; + deploy script |
| 2 | **Caddy instead of `python -m http.server`** | Emits per-path `Cache-Control` (enables #1 with no CF dashboard), gzip/zstd on origin→edge hop, HTTP keep-alive | Low–Med | Low — must scope matchers so version/index/bootstrap get `no-cache` | Pi (systemd `ExecStart`) |
| 3 | **Cloudflare Tiered Cache (Web)** | Upper-tier PoP fills others → fewer origin cache-fill fetches for JS + card art | Low | Very low | CF dashboard (free) |
| 4 | Precompressed `.br`/`.gz` next to assets | ~170 KB smaller `main.dart.js` than CF zstd; smaller origin→edge | Low | Low | Pi (build step + Caddy `precompressed`) |
| 5 | Edge-cache card images explicitly + longer TTL | Already `MISS→HIT`; a rule pins a longer, predictable edge TTL | Low | Low (stable names, rarely change) | CF Cache Rule |
| 6 | Card-image recompression/resize (asset change) | 88 MB → ~25 MB; huge on-demand transfer cut | Med | Med (asset pipeline, visual QA) | repo assets, **not** delivery config |
| 7 | `flutter build web --wasm` (dart2wasm/skwasm) | Potentially faster runtime; needs COOP/COEP for threads | High | Med–High | build + headers — **defer, experiment only** |
| 8 | Drop bundled `build/web/canvaskit/*` from deploy | Saves ~25 MB disk on Pi; unused (CDN default) | Low | Low | deploy/rsync excludes |

**Not worth doing at this resolution:** Auto Minify (Cloudflare *removed* it Aug
2024; Flutter output is already minified — no action), self-hosting CanvasKit
(gstatic CDN is faster and already `immutable`+brotli — leave `useLocalCanvasKit`
off), WebSocket transport tuning (latency is fixed Pi→edge→client; the payload
win is tracked in `profiling_baseline.md`).

---

## 4. Exact recommended `Cache-Control` policy (per file type)

The rule that makes this safe with the version-poll model: **let the EDGE cache
the heavy stable file, but never let the BROWSER cache it** — the browser always
revalidates, so a deploy + edge purge is picked up on the next poll-triggered
reload.

| Path | Cache-Control | Why |
|---|---|---|
| `/`, `/index.html` | `no-cache, no-store, must-revalidate` | Entry point; must reflect new build immediately |
| `/version.json` | `no-cache, no-store, must-revalidate` | Poll target; must be fresh (already `no-store` client-side) |
| `/flutter_bootstrap.js` | `no-cache, no-store, must-revalidate` | Carries per-build `serviceWorkerVersion`; tiny |
| `/flutter_service_worker.js`, `/manifest.json` | `no-cache` | Small, build-specific |
| **`/main.dart.js`** (and `/flutter.js`) | **`public, s-maxage=86400, max-age=0, must-revalidate`** | `s-maxage` → CF edge caches 24 h (offloads Pi); `max-age=0` → browser revalidates so deploys aren't masked by disk cache |
| `/assets/**`, `/icons/**`, `/favicon.png` | `public, max-age=86400` | Fonts/manifests/images; stable within a build. Card `.jpg` are already edge-cached |
| `/canvaskit/**` | `public, max-age=86400` | Only matters if `useLocalCanvasKit` is ever turned on; currently served by gstatic |

Note on `s-maxage`: Cloudflare honors it as the **edge** TTL independently of the
browser `max-age`, which is exactly the split we want. If you prefer to control
edge TTL from the CF dashboard instead, use a Cache Rule (§5.3) and keep the
origin header as plain `no-cache` — but then you *must* set the rule's Edge TTL,
because with no origin `Cache-Control` CF leaves it `DYNAMIC` (today's behavior).

**Whichever path you choose, `main.dart.js` has a stable filename, so a deploy
MUST purge it from the edge (§5.4).**

---

## 5. Proposed configs (ready to review — do NOT apply yet)

### 5.1 Caddy (recommended origin — replaces `python -m http.server`)

Install: `sudo apt install caddy` (or the Caddy apt repo). Then a Caddyfile:

```caddyfile
# /home/sfg/.config/caddy/Caddyfile   (bind localhost; cloudflared is the front)
:8123 {
	root * /home/sfg/code/simple-card-game/build/web
	encode zstd gzip            # compress the origin->edge hop (CF still (re)compresses to client)

	# --- MUST stay fresh: the version-poll cache-bust depends on these ---
	@nocache path / /index.html /version.json /flutter_bootstrap.js /flutter_service_worker.js /manifest.json
	header @nocache Cache-Control "no-cache, no-store, must-revalidate"

	# --- big, stable-named app bundle: edge-cache, browser-revalidate ---
	@appjs path /main.dart.js /flutter.js
	header @appjs Cache-Control "public, s-maxage=86400, max-age=0, must-revalidate"

	# --- heavy static (fonts, images, icons, self-hosted canvaskit if ever used) ---
	@static path /assets/* /icons/* /canvaskit/* /favicon.png
	header @static Cache-Control "public, max-age=86400"

	file_server
}
```

Then, in `shards-web.service` (review before swapping):
```
ExecStart=/usr/bin/caddy run --config /home/sfg/.config/caddy/Caddyfile --adapter caddyfile
```
Keep it bound to `:8123` on localhost; cloudflared config is unchanged. Caddy is
a single static binary, multi-threaded, HTTP-keep-alive, and handles the headers
+ compression the version-poll model needs. **Risk check:** confirm the
`@nocache` matcher covers exactly `version.json` / `index.html` /
`flutter_bootstrap.js` before enabling, or the reload could be masked.

### 5.2 Minimal python wrapper (fallback — keeps python, adds headers only)

If swapping servers is undesirable, this subclass adds the same `Cache-Control`
policy (compression stays with the CF edge). Save as e.g.
`scripts/serve_web.py` and point `ExecStart` at it:

```python
#!/usr/bin/env python3
import functools, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

NO_STORE = {"/", "/index.html", "/version.json",
            "/flutter_bootstrap.js", "/flutter_service_worker.js", "/manifest.json"}

class H(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"           # enable keep-alive
    def end_headers(self):
        p = self.path.split("?", 1)[0]
        if p in NO_STORE:
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        elif p in ("/main.dart.js", "/flutter.js"):
            self.send_header("Cache-Control", "public, s-maxage=86400, max-age=0, must-revalidate")
        elif p.startswith(("/assets/", "/icons/", "/canvaskit/")) or p == "/favicon.png":
            self.send_header("Cache-Control", "public, max-age=86400")
        super().end_headers()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8123
    root = "/home/sfg/code/simple-card-game/build/web"
    ThreadingHTTPServer(("127.0.0.1", port),
        functools.partial(H, directory=root)).serve_forever()
```
Caddy is still preferable (compression + robustness), but this is the low-risk
"keep python" option that unlocks win #1.

### 5.3 Cloudflare Cache Rule (pure CF, no Pi change — alternative to origin headers)

Dashboard → **Caching → Cache Rules → Create rule**:

- Name: `Edge-cache app bundle`
- When incoming requests match (expression editor):
  ```
  (http.request.uri.path eq "/main.dart.js") or (http.request.uri.path eq "/flutter.js")
  ```
- Then:
  - **Cache eligibility:** Eligible for cache
  - **Edge TTL:** Override origin → **1 day**
  - **Browser TTL:** Override origin → **Respect origin** *(or 0 / "No cache")* so the browser revalidates
- Leave `/`, `/version.json`, `/index.html`, `/flutter_bootstrap.js` **out** of
  any cache rule (they stay `DYNAMIC` / fresh — correct).

This flips `main.dart.js` from `DYNAMIC` to `HIT` with **zero** Pi changes. Free
tier allows a small number of Cache Rules — this needs one.

Also, optionally, **Tiered Cache**: Caching → Tiered Cache → enable **Tiered
Cache (Web)** (free). Reduces how often the Pi is asked to refill the edge.

### 5.4 Deploy-time purge (REQUIRED once `main.dart.js` is edge-cached)

Because `main.dart.js` keeps its name across builds, add a purge after copying
`build/web` (free tier supports purge-by-URL). Append to the deploy step:

```bash
# needs a scoped API token (Zone.Cache Purge) + the sharts.love zone id
curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"files":[
     "https://sharts.love/main.dart.js",
     "https://sharts.love/flutter.js",
     "https://www.sharts.love/main.dart.js",
     "https://www.sharts.love/flutter.js"
  ]}'
```

Deploy sequence becomes: `build_web.sh` (stamps `version.json`) → copy to
`build/web` → **purge `main.dart.js`** → (Caddy/CF serve fresh; version-poll
reloads clients within ~30 s). `version.json` and `index.html` are never
edge-cached, so the poll keeps working exactly as today.

---

## 6. Why the version-poll cache-bust stays intact

- `version.json`, `index.html`, `flutter_bootstrap.js` are explicitly
  `no-store` at the origin and excluded from every cache rule → always fresh,
  same as today (they're already `DYNAMIC`).
- `main.dart.js` gets **edge** caching only; **browser** revalidates (`max-age=0`
  / Browser TTL 0). The client's hard-reload re-requests it and, after a deploy
  purge, the edge serves the new file. No stale JS, no reload loop (the existing
  one-shot guard is untouched).
- WebSocket path (`/ws*`) is untouched — none of these headers/rules match it.

## 7. Adjacent (out of delivery-config scope, flagged for later)

- **Card art is the largest raw weight** — 88 MB across 203 JPGs, up to 2.49 MB
  each. They're already edge-cached (`MISS→HIT`), so delivery is handled, but
  resizing to display resolution + quality ~80 would cut on-demand transfer
  ~60–70%. That's an asset-pipeline change with visual QA — not a server/CF knob.
- **Bundled `build/web/canvaskit/*` (~25 MB) is unused** (CanvasKit loads from
  gstatic). Excluding it from the Pi deploy saves disk; harmless to keep.
- **`--wasm`**: the build log's "Wasm dry run succeeded" means it's viable, but
  skwasm multithreading needs `crossOriginIsolated` (COOP/COEP response headers)
  and the payload isn't guaranteed smaller. Treat as a measured experiment, not a
  clean win.
