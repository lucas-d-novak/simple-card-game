# Serving & deploy — Shards (sharts.love)

How the live site is served, and the delivery-performance decisions behind it.
Companion to `docs/perf/delivery_optimization.md` (the research + measurements)
and `docs/perf/profiling_baseline.md` (server-side engine profiling).

## Topology

```
Player browser
   │  HTTPS / WSS
   ▼
Cloudflare edge (free tier)  ──►  cloudflared tunnel  ──►  Raspberry Pi 4B
                                                             ├─ shards-web.service     :8123  (Flutter web build/web)
                                                             └─ shards-server.service  :8080  (Dart WebSocket game server)
```
- `shards-tunnel.service` runs `cloudflared` with `~/.cloudflared/config-sharts.yml`.
- Both origin services bind `127.0.0.1` — only the local tunnel reaches them.

## Static web serving — `scripts/serve_web.py`

`shards-web.service` runs `scripts/serve_web.py` (NOT `python3 -m http.server`).
The stock server sent **no `Cache-Control`**, so browser caching was heuristic and
Cloudflare treated everything as `DYNAMIC` — every asset was a full Pi round-trip.

`serve_web.py` sets `Cache-Control` per path:

| Files | Header | Why |
|---|---|---|
| `index.html`, `flutter_bootstrap.js`, `version.json`, service worker, manifest | `no-cache` | The **version-poll reload** depends on these always revalidating. Never edge-cache them. |
| App code — `main.dart.js`, other `.js`/`.json` | `public, max-age=0, s-maxage=604800, must-revalidate` | Not content-hashed, so the **browser must revalidate** every load (a deploy is picked up instantly; a 304 avoids re-downloading 2.99 MB within a version). `s-maxage` lets the **edge** cache it long — see the Cache Rule below. |
| Static media — `/assets/`, `/canvaskit/`, `/icons/`, images, fonts, wasm | `public, max-age=86400` | Stable content; already edge-cached. |

Rollback: the systemd unit (`~/.config/systemd/user/shards-web.service`) has the
original `python3 -m http.server` line commented for one-line restore.

## Deploy — `scripts/build_web.sh`

1. Stamps the git SHA into `version.json` (drives the client version-poll hard-reload).
2. `flutter build web --release`.
3. **Purges the Cloudflare edge cache** (`purge_everything`) so the freshly-built,
   NON-content-hashed assets are never served stale from the edge.

The purge reads `~/.cloudflared/sharts-purge.env` (owner-only, gitignored by
being outside the repo):
```
CF_PURGE_TOKEN=<Custom token: Zone · Cache Purge · Purge, scoped to sharts.love>
CF_ZONE_ID=<zone Overview → Zone ID>
```
If the file/creds are absent, the purge is **skipped gracefully** — the build never fails.

Then restart the services (`systemctl --user restart shards-web shards-server`).

## Delivery-perf wins (motivation)

Measured baseline: `main.dart.js` is **2.99 MB raw**; Cloudflare already auto-
compresses it to the browser (~920 KB), and CanvasKit loads from Google's CDN
(the bundled `canvaskit/` is dead weight — never hits the Pi).

1. **Version-poll hardened + browser revalidation** *(live).* Deterministic
   `no-cache` on the poll set; `must-revalidate` on app code → returning players
   get a 304 instead of re-downloading 2.99 MB.
2. **Edge-offload of `main.dart.js`** *(needs the Cache Rule below).* Cloudflare
   serves it from the edge (no Pi round-trip on repeat/global loads), kept fresh
   by the deploy-time purge. Cloudflare's free-tier default will **not** edge-cache
   a `max-age=0` response from origin headers alone, so it requires an explicit
   Cache Rule.
3. **Tiered Cache (Web)** *(optional, free dashboard toggle)* — fewer origin
   cache-fills across CF PoPs.

### Required Cache Rule (one-time, Cloudflare dashboard)

Caching → Cache Rules → Create rule:
- **When incoming requests match:** `URI Path` `equals` `/main.dart.js`
- **Then:**
  - Cache eligibility → **Eligible for cache**
  - **Edge TTL → Override origin → 1 month** — this is the load-bearing setting.
    Cloudflare's free-tier default treats our origin `max-age=0` as "don't
    edge-cache" (measured: `cf-cache-status: DYNAMIC` even with `s-maxage`), so
    "Respect origin" does NOT work here — you must **Override**. Safe because
    `build_web.sh` purges the edge on every deploy.
  - **Browser TTL → Respect origin** (keeps `max-age=0` → browser always
    revalidates → a deploy is picked up immediately).

This flips `main.dart.js` from `cf-cache-status: DYNAMIC` → `HIT` (the Pi stops
serving the 2.99 MB file on repeat/global loads). Targeting `/main.dart.js`
specifically keeps `flutter_bootstrap.js`/`version.json` on their `no-cache`
path so the version-poll reload is unaffected. (A dashboard click because the
deploy token is Cache-Purge-only, not Rulesets-Edit.)

## Verifying
```
curl -sI https://sharts.love/version.json | grep -iE 'cache-control|cf-cache-status'   # no-cache / DYNAMIC (correct)
curl -sI https://sharts.love/main.dart.js | grep -iE 'cache-control|cf-cache-status'   # HIT once the Cache Rule is set
```
