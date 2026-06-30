# LAN multiplayer demo — runbook

Run a real shared game across multiple devices on your local network. No app
install — players just open a URL in their browser.

## What you need
- One "host" machine (your laptop is fine; a Pi later) on the same Wi-Fi/LAN as
  the player devices.
- Flutter 3.41.5 + Dart on the host.

## 1. Find the host's LAN IP
- Windows: `ipconfig` → the IPv4 like `192.168.1.50`.
- macOS/Linux: `ipconfig getifaddr en0` / `hostname -I`.

Use that IP everywhere below as `<HOST_IP>`.

## 2. Start the game server (terminal A)
```bash
cd server
dart pub get        # first time only
dart run bin/server.dart 8080
# -> "Shards server listening on ws://0.0.0.0:8080"
```

## 3. Serve the web app (terminal B)
```bash
flutter build web --release
python -m http.server 8123 --directory build/web
# (any static file server works)
```

## 4. On each device
Open a browser to:
```
http://<HOST_IP>:8123/?online=1
```
The server URL auto-fills to `ws://<HOST_IP>:8080` (derived from the page host).
- Enter a **name** (must be unique per player) → **Connect**.
- One player taps **Create (2p)**; the other sees it appear and taps **Join**.
- When the seats fill, both devices jump into the shared game. Take turns: tap
  hand cards to play, center cards to buy, **End Turn** to pass.

## Notes
- **Plain http/ws is fine on a LAN** — browsers allow `ws://` from an `http://`
  page. No certificates needed. (TLS/`wss://` only matters once you serve the app
  over `https://`, which the future Cloudflare Tunnel handles automatically.)
- **Firewall:** Windows may prompt to allow Dart/Python on private networks —
  allow it (these listen on your LAN only).
- **Hidden info is enforced server-side:** each device only ever receives its own
  hand; opponents' hands and all deck orders never leave the server.
- The server is in-memory for now (no persistence/reconnect yet — Phase 3).
  Restarting the server clears all games.

## Quick local 2-window sanity check (no second device)
Open two browser windows to `http://localhost:8123/?online=1`, use two different
names, Create in one + Join in the other.
