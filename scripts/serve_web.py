#!/usr/bin/env python3
"""Static file server for build/web with Cache-Control tuned for the Cloudflare
edge — replaces `python3 -m http.server` (which sent NO cache headers, so every
asset was a full Pi round-trip and browser caching was heuristic/unpredictable).

Usage:  serve_web.py [PORT] [ROOT]   (defaults: 8123  build/web)

Cache policy (see docs/serving/ for the motivation):
  * NO-CACHE (always revalidate) — the version-poll set. These must never be
    served stale or the `version.json?ts=` reload / bootstrap breaks:
      index.html, flutter_bootstrap.js, version.json,
      flutter_service_worker.js, manifest.json  (+ "/")
  * REVALIDATE (max-age=0, must-revalidate) — app CODE (main.dart.js etc). It is
    NOT content-hashed, so we cannot cache it long without a Cloudflare purge on
    deploy (no CF API token on the box yet). must-revalidate = the browser sends
    If-Modified-Since and gets a tiny 304 within a version (no 2.99 MB re-download)
    but always picks up fresh code on deploy. SimpleHTTPRequestHandler already
    emits Last-Modified and answers If-Modified-Since with 304, so this Just Works.
  * LONG (max-age=1d) — stable media (card art, fonts, icons, canvaskit): rarely
    changes and Cloudflare already edge-caches it.

When a CF cache-purge token is wired into the deploy, main.dart.js can move to a
long edge TTL (s-maxage) + purge-on-deploy for the full edge-offload win.
"""
import http.server
import os
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8123
ROOT = sys.argv[2] if len(sys.argv) > 2 else "build/web"

# Files that drive the deploy/reload mechanism — must always revalidate.
NO_CACHE = {
    "index.html",
    "flutter_bootstrap.js",
    "version.json",
    "flutter_service_worker.js",
    "manifest.json",
}
LONG_DIRS = ("/assets/", "/canvaskit/", "/icons/")
LONG_EXTS = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".woff", ".woff2",
             ".otf", ".ttf", ".wasm")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        path = self.path.split("?", 1)[0]
        base = os.path.basename(path)
        if path in ("/", "") or base in NO_CACHE:
            self.send_header("Cache-Control", "no-cache")
        elif path.startswith(LONG_DIRS) or base.endswith(LONG_EXTS):
            self.send_header("Cache-Control", "public, max-age=86400")
        else:
            # App code (main.dart.js, other .js/.json). Edge-cached long via
            # s-maxage so Cloudflare serves it WITHOUT hitting the Pi; the
            # browser still revalidates (max-age=0, must-revalidate) so a deploy
            # is picked up immediately. build_web.sh purges the stale edge copy
            # on every deploy (these files are not content-hashed).
            self.send_header(
                "Cache-Control",
                "public, max-age=0, s-maxage=604800, must-revalidate",
            )
        super().end_headers()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", PORT), Handler) as httpd:
        httpd.serve_forever()
