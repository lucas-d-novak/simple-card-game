# Cloudflare Tunnel deploy — hosted alpha runbook

Stand up the **public alpha** of Shards of Infinity behind a custom domain with
TLS, on a low-budget always-on box (a Raspberry Pi or any spare machine) using a
**Cloudflare Tunnel**. The end state: an invitee opens `https://play.example.com`,
types a **name** + the **shared access code**, and plays — no app install, no
port-forwarding, no exposed home IP.

This is the public sibling of [`../server/LAN_DEMO.md`](../server/LAN_DEMO.md)
(local-network demo, plain `http`/`ws`, no TLS). Read that first if you just want
two laptops on the same Wi-Fi. This doc adds: a real domain, TLS at the edge, an
access-code gate, and an origin allowlist. The architecture behind it is in
[`multiplayer_architecture.md`](multiplayer_architecture.md) §1 (topology) and §9
(deploy/ops).

Throughout, the example domain is **`play.example.com`** and the example access
code is **`alpha-7Q2K`**. Substitute your own.

---

## 0. How the pieces fit (read this once)

Three processes run on the box, plus Cloudflare at the edge:

```
 Invitee browser
   │  https://play.example.com          (page + assets)
   │  wss://play.example.com            (WebSocket upgrade, SAME host, no port)
   ▼
 Cloudflare edge  ── TLS terminated here; free DNS + DDoS ──┐
   ▲  encrypted, outbound-only tunnel                       │
   │                                                        ▼
 ┌────────────────────────────── the box (Pi/PC) ──────────────────────┐
 │  cloudflared (tunnel)                                                │
 │     ├─ http://localhost:8123  → static web app (build/web)          │
 │     └─ http://localhost:8080  → Dart game server (WebSocket + /health)│
 └─────────────────────────────────────────────────────────────────────┘
```

**The one constraint that drives the whole tunnel config** comes from the client.
In [`lib/main.dart`](../lib/main.dart), `_defaultServerUrl()` derives the
WebSocket URL **from the page's own host and scheme**:

- On an **`https://`** page it returns **`wss://<host>`** with **NO explicit port**
  (so the edge/tunnel routes the upgrade on 443).
- On an **`http://`** page it returns `ws://<host>:8080` (the LAN/dev path).
- `localhost` / empty host falls back to `ws://localhost:8080`.

So when the app is served from `https://play.example.com`, the client opens
**`wss://play.example.com`** — the *same* host, no port. **The tunnel must route
the WebSocket upgrade for that host to the Dart server on `localhost:8080`, while
routing normal page/asset requests to the static web app.** That split is the
heart of §5 below.

An explicit `?server=` query param overrides this derivation — it's the escape
hatch for the dedicated-subdomain topology (§5, option B).

---

## 1. Prerequisites

On the box:

- **Flutter 3.41.5 + Dart** (the repo is pinned to 3.41.5; CI enforces it — see
  [`README.md`](../README.md) "Flutter version policy"). Verify with
  `flutter --version`. You need Flutter to *build* the web app; you need Dart to
  run the server (Flutter bundles Dart).
- The repo checked out, on the working branch (`rld-mvp-sprint`).
- A **static file server** of your choice: `python3 -m http.server` (zero install)
  or `nginx` / `caddy` (nicer for always-on). Examples below use Python.

In Cloudflare:

- A **Cloudflare account** (free tier is fine).
- A **domain managed by Cloudflare** (its nameservers point at Cloudflare). You
  do not need to buy from Cloudflare; any registrar works as long as the zone is
  on Cloudflare.

Tooling:

- **`cloudflared`** installed on the box. Install per Cloudflare's docs
  (`apt`/`brew`/`.deb`/binary). Verify with `cloudflared --version`.

---

## 2. Build the web app

From the repo root:

```bash
flutter pub get
flutter build web --release
# → static files written to build/web/
```

`build/web/` is a self-contained static site (the compiled Flutter web app). It
talks to no build-time server URL — the server URL is derived **at runtime** from
the page host (§0), so the *same* build works on LAN or behind any domain.

Rebuild this whenever you change client code; the static server (§3) just serves
whatever is in `build/web/`.

---

## 3. Serve the web app (static files)

Serve `build/web/` on a local port — **8123** in these examples — bound to
localhost (cloudflared connects locally, so it never needs to be on the LAN):

```bash
# from the repo root
python3 -m http.server 8123 --bind 127.0.0.1 --directory build/web
```

Notes:

- **Bind to `127.0.0.1`**, not `0.0.0.0`. Only `cloudflared` (same box) needs to
  reach it; binding to localhost keeps it off your LAN entirely. (The LAN demo
  binds wider on purpose; the tunnel deploy does not need to.)
- For always-on, use `nginx`/`caddy` serving `build/web` on `:8123` instead, and
  run it as a service. Any static server works.

---

## 4. Run the game server

The server is a pure-Dart `dart:io` WebSocket server
([`../server/bin/server.dart`](../server/bin/server.dart)). It binds
**`0.0.0.0:<port>`** (default **8080**), serves a **`/health`** endpoint, and
upgrades everything else to a WebSocket. Run it from the `server/` directory (it
reads the card DB at `../assets/card_db/cards.json`, relative to `server/`).

### Dev / quick run

```bash
cd server
dart pub get        # first time only
SHARDS_ACCESS_TOKEN=alpha-7Q2K \
SHARDS_ALLOWED_ORIGINS=https://play.example.com \
dart run bin/server.dart 8080
```

### Compiled (recommended for the box)

Compile once to a single self-contained native binary (no Dart runtime needed to
run it — ideal for a Pi). The source header documents this:

```bash
cd server
dart pub get
dart compile exe bin/server.dart -o build/shards-server
# run it (same env vars; run from server/ so the ../assets path resolves):
SHARDS_ACCESS_TOKEN=alpha-7Q2K \
SHARDS_ALLOWED_ORIGINS=https://play.example.com \
./build/shards-server 8080
```

On a healthy start you'll see lines like:

```
Access token REQUIRED (clients must present SHARDS_ACCESS_TOKEN).
Origin allowlist: https://play.example.com
Loaded card DB: 183 records, 96 unique market cards, 29 Destinies (separate supply).
Player-stats telemetry enabled.
Persistence enabled at data (no games to restore).
Shards server listening on ws://0.0.0.0:8080
```

### Every env var / flag, and why to set it for a public deploy

| Var / arg | Default | What it does | For a public deploy |
|-----------|---------|--------------|---------------------|
| **`SHARDS_ACCESS_TOKEN`** | *(unset → OPEN)* | The shared **access code**. When set, every client must present a matching `token` in its first `identify` message or the server **closes the connection** (constant-time compare; close code `4001`). When unset/empty the server is **OPEN — anyone can connect.** | **ALWAYS SET THIS.** This *is* the "shared access code" invitees type. The startup log prints `Access token REQUIRED` vs the `WARNING: no access token set — server is OPEN` banner — read it on every start to confirm. |
| **`SHARDS_ALLOWED_ORIGINS`** | *(unset → any origin)* | Comma-separated **origin allowlist** checked on the WebSocket upgrade. A browser page whose `Origin` header isn't in the set gets `403` and can't open a socket — blocks cross-site WebSocket hijacking. | Set to **the exact https origin your app is served from**, e.g. `https://play.example.com`. Must match scheme + host (no trailing slash, no port for 443). Multiple allowed: comma-separate. |
| **`SHARDS_DATA_DIR`** | `server/data` (gitignored) | Directory for **game persistence** — one JSON snapshot per game, so in-progress games survive a restart. Degrades to in-memory-only if unwritable (never crashes). | Default is fine. Point it at a roomier/persistent disk if you want, e.g. `SHARDS_DATA_DIR=/opt/shards/data`. Back this up (§8). |
| **`SHARDS_STATS_DB`** | `server/data/stats.db` | SQLite path for **player-stats / ML telemetry**. Graceful: if it can't open, telemetry is silently disabled and the server still runs. | Default is fine. Move it with the data dir if you relocate persistence. |
| **port** (positional arg) | `8080` | TCP port the server binds (`0.0.0.0:<port>`). | Keep **8080** to match the tunnel examples below, or change both together. |

> **The single most important line in this whole runbook:** set
> `SHARDS_ACCESS_TOKEN`. Without it the server is OPEN and anyone who finds the
> domain can play / occupy seats. The token is the entire access model for the
> alpha.

---

## 5. Cloudflare Tunnel config (the routing)

### Create + name the tunnel, route DNS

```bash
cloudflared tunnel login                       # browser auth; pick your zone
cloudflared tunnel create shards               # prints a TUNNEL UUID + creds json
cloudflared tunnel route dns shards play.example.com   # CNAME play → tunnel
```

`tunnel create` writes a credentials JSON (path printed in the output, e.g.
`~/.cloudflared/<UUID>.json`). You'll reference it in `config.yml`.

### The routing problem

You must route, **on the same hostname `play.example.com`**:

1. normal HTTPS requests (`GET /`, JS/wasm/asset fetches) → the **static web app**
   on `localhost:8123`, **and**
2. the **WebSocket upgrade** (the `wss://play.example.com` the client opens, §0) →
   the **Dart server** on `localhost:8080`.

cloudflared ingress matches by **hostname and path** (and serves WebSockets to
whatever backend a rule selects — it proxies the `Upgrade` transparently). There
is **no built-in "match the `Upgrade` header" ingress rule**, so you can't split
GET-page-vs-WS purely by header. That leaves two clean topologies.

---

### Option A — one hostname, split by **path** *(recommended)*

Serve the app at `play.example.com/` and reach the game server at a path the
client is told to use, e.g. `play.example.com/ws`. cloudflared routes by path:

```yaml
# ~/.cloudflared/config.yml   (or /etc/cloudflared/config.yml)
tunnel: <TUNNEL_UUID>
credentials-file: /home/pi/.cloudflared/<TUNNEL_UUID>.json

ingress:
  # WebSocket upgrade → Dart game server. Path-prefix match wins over "/".
  - hostname: play.example.com
    path: /ws*
    service: http://localhost:8080
  # Everything else on this host → static web app (build/web).
  - hostname: play.example.com
    service: http://localhost:8123
  # Fallthrough.
  - service: http_status:404
```

**The catch:** the current client (`_defaultServerUrl`) opens `wss://<host>` with
**no path** — it targets `wss://play.example.com`, which Option A's path rules
send to the *static* app, not the game server. So to use the clean path split you
must point the client at the `/ws` path explicitly via the **escape hatch**:

```
https://play.example.com/?server=wss://play.example.com/ws
```

That `?server=` wins over the host-derived default (see `_defaultServerUrl` —
"an explicit `?server=` wins"). Share *that* URL with invitees (or set it as the
default link). The server upgrades any non-`/health` request to a WebSocket, so it
happily accepts the upgrade at `/ws`.

Tradeoff: **one hostname, one TLS cert, one DNS record** — operationally the
simplest box-side. The cost is the slightly longer invite URL with the `?server=`
param. This is the recommended topology.

---

### Option B — dedicated WebSocket subdomain

Give the game server its own hostname, e.g. `ws.example.com`, and keep
`play.example.com` purely static:

```yaml
ingress:
  - hostname: play.example.com
    service: http://localhost:8123     # static web app
  - hostname: ws.example.com
    service: http://localhost:8080     # Dart game server
  - service: http_status:404
```

Route both names: `cloudflared tunnel route dns shards play.example.com` **and**
`cloudflared tunnel route dns shards ws.example.com`.

Because the app is on `play.example.com` but the server is on `ws.example.com`,
the client's host-derived default (`wss://play.example.com`) would hit the static
site — so you **must** use the escape hatch again, pointing at the other host:

```
https://play.example.com/?server=wss://ws.example.com
```

And set `SHARDS_ALLOWED_ORIGINS=https://play.example.com` (the *page* origin, not
the WS host — the allowlist checks the browser's `Origin`, which is the page).

Tradeoff: cleaner separation and a no-path WS URL, but **two DNS records / two
hostnames** to manage, and you still can't rely on the bare-host default — the
`?server=` param is required either way.

---

### Why Option A is recommended

Both options need the `?server=` escape hatch given the current client URL
derivation, so neither lets you ship a truly bare `https://play.example.com` link
that "just works" for the WebSocket. Given that, **Option A wins on operational
simplicity**: one hostname, one DNS record, one ingress block. Option B's only
advantage (a path-less WS URL) is moot because you're already passing `?server=`.

> **The only no-escape-hatch path** would be a future client change so that on
> `https` it derives `wss://<host>/ws` (adding the `/ws` path itself). With that,
> Option A's bare `https://play.example.com` link would route the WS upgrade to
> `/ws` → `:8080` automatically, no query param. That's a one-line change in
> `_defaultServerUrl` if you decide the bare link matters. **Until then, ship the
> `?server=` invite link.** (See "Open questions" at the end.)

### Run the tunnel

```bash
cloudflared tunnel run shards
# for always-on, install it as a service:
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

---

## 6. TLS

You don't manage any certificates. **Cloudflare terminates TLS at its edge**, so:

- The browser speaks `https://` and `wss://` to `play.example.com` — secure,
  with a valid cert Cloudflare provisions for your zone.
- Inside the tunnel, the origin is **plain `http`/`ws` on localhost** — that's why
  `config.yml` points at `http://localhost:8123` / `http://localhost:8080` and the
  server only ever needs to listen plain. The tunnel link itself is encrypted.

The browser blocks `ws://` from an `https://` page (mixed content), but the client
already emits **`wss://`** on https pages (§0), so this is handled — don't override
`?server=` with a `ws://` URL on a public https deploy (§9 troubleshooting).

---

## 7. Verify

Work through these in order:

1. **Health endpoint (origin).** On the box: `curl http://localhost:8080/health`
   → `ok`. Through the edge: `curl https://play.example.com/ws/health`
   (Option A) or `curl https://ws.example.com/health` (Option B) → `ok`. The
   server answers `/health` with `200 ok` on any path tail that reaches it.
2. **Static app loads.** Open `https://play.example.com/` — the Flutter web app
   renders (the lobby screen).
3. **Server status indicator.** The lobby shows a **"Server: online / offline"**
   status (a connectivity check on the derived/`?server=` WS URL). "online"
   confirms the browser reached the game server through the tunnel with the right
   routing. If it shows **offline**, jump to §9.
4. **Connect with the access code.** Enter a **name** + the **access code**
   (`alpha-7Q2K`) → Connect. A wrong/blank code is rejected at `identify`
   (close code `4001`) and the client re-prompts.
5. **Cross-device game.** On device 1, **Create (2p)**; on device 2 (open the same
   invite URL, enter a different name + the same code), the game appears →
   **Join**. Seats fill → both drop into the shared board. Take turns. Confirm
   each device sees only its own hand (hidden info is enforced server-side).

The invite URL you actually share (Option A):

```
https://play.example.com/?server=wss://play.example.com/ws
```

---

## 8. Operations

### Rotate the access code

The token is just an env var. To rotate:

1. Restart the server with a new `SHARDS_ACCESS_TOKEN` (e.g.
   `SHARDS_ACCESS_TOKEN=alpha-9F4L ./build/shards-server 8080`).
2. Existing connections that re-identify with the old code are rejected
   (`4001`); the client **auto-reprompts** for the code on rejection.
3. Tell invitees the new code. If a client has the old code saved, it offers
   **"Forget saved code"** and re-prompts — so a rotation just means "re-enter the
   new code once."

Rotating only changes who can *connect*; in-progress games persist across the
restart (below).

### Where the data lives + backups

- **`server/data/`** (or your `SHARDS_DATA_DIR`) holds: one **JSON snapshot per
  in-progress game** + **`stats.db`** (SQLite telemetry, or your `SHARDS_STATS_DB`).
- Back it up by copying the directory while the server is idle, or snapshot
  `stats.db` with SQLite's `VACUUM INTO`. The data is small and writes are
  infrequent (turn-based), so a nightly `rsync`/copy off-box is plenty.

### Restart behavior

- **Persistence restores in-progress games.** On boot the server loads every
  persisted game; reconnecting clients resync to the current snapshot. A restart
  (deploy a new binary, crash + `Restart=on-failure`) resumes games from their
  last saved state.
- **A restart clears the same-turn undo stack.** Undo is an in-memory per-game
  rollback that is *cleared at every turn boundary* and not persisted — so after a
  restart, players keep their game but lose the ability to undo the current turn's
  moves up to that point. (The board state itself is intact; only the in-turn
  rollback buffer is gone.)

### Updating the deploy

1. `flutter build web --release` (if client changed) and/or rebuild the server
   exe (`dart compile exe ...`).
2. Stop the server (in-flight games are persisted; clients see a brief
   disconnect — forgiving for turn-based).
3. Swap the static files / binary, restart. Clients reconnect and resync.

---

## 9. Troubleshooting

**"Can't connect" / lobby shows Server: offline.** Walk the chain:

1. **Status indicator + `/health`.** Is the server process up? `curl` `/health`
   on localhost (origin healthy?) and through the edge (tunnel routing the WS host
   to `:8080`?). If localhost works but the edge doesn't, it's a **routing**
   problem (§5) — the upgrade isn't reaching `:8080`.
2. **Access code (REQUIRED vs OPEN).** Read the server's startup log. If it says
   `Access token REQUIRED`, the client **must** send the matching code; a wrong
   code closes with `4001`. If it unexpectedly says `WARNING: ... server is OPEN`,
   your `SHARDS_ACCESS_TOKEN` didn't get set (typo / not exported into the process
   env).
3. **Origin allowlist.** A `403` on the WebSocket upgrade means the browser's
   `Origin` isn't in `SHARDS_ALLOWED_ORIGINS`. It must be the **exact** https
   origin of the page: `https://play.example.com` — correct scheme, host, **no
   trailing slash, no `:443`**. The log prints `Origin allowlist: ...` on start;
   confirm it matches what the browser sends.
4. **Tunnel forwards the WS upgrade.** Confirm `config.yml` routes the WS host/path
   to `http://localhost:8080` (not to the static `:8123`). In Option A, the
   `path: /ws*` rule must come **before** the catch-all `/` rule, and the invite
   URL must carry `?server=wss://play.example.com/ws`.

**Mixed-content error in the browser console (`ws://` blocked from `https://`).**
The client already emits **`wss://`** on https pages, so this only happens if you
**overrode `?server=` with a `ws://` URL**. On a public https deploy, never pass a
`ws://` `?server=` — use `wss://` (the edge handles TLS, §6).

**Game state looks stale after a restart.** Expected for undo only — the board
restores from persistence, but the same-turn undo buffer is cleared on restart
(§8). The game itself is intact; just re-sync (reopen the tab) if the client
didn't auto-resync.

---

## Open questions for the operator

1. **Which tunnel topology?** Option A (one hostname, path split, recommended) vs
   Option B (dedicated WS subdomain). Both currently need the `?server=` invite
   link — pick based on whether you'd rather manage one DNS record (A) or keep a
   clean path-less WS URL on a second host (B).
2. **Bare-link goal?** If you want `https://play.example.com` to work with **no**
   `?server=` param, that requires a one-line client change so `_defaultServerUrl`
   derives `wss://<host>/ws` on https (then Option A's bare link routes the upgrade
   to `/ws` → `:8080` automatically). Decide whether the cleaner invite link is
   worth that small code change. **This doc does not change code** — until then,
   ship the `?server=` link.
3. **`cloudflared` path-matching support.** Confirm your installed `cloudflared`
   version supports `path:` ingress matching (modern versions do). If not, fall
   back to Option B (host-based), which needs no path matching.
