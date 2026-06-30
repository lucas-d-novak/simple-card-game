#!/usr/bin/env bash
# Orchestrates: build web -> serve -> headless Edge -> CDP screenshot.
# Usage: scripts/capture_live.sh [outPath] [skip-build]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-screenshots/live_board.png}"
SKIP_BUILD="${2:-}"
PORT=8123
DBG=9222
FLUTTER=/c/Users/rldun/code/flutter/bin/flutter
EDGE="C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
URL="http://localhost:${PORT}/?board=1"

if [ "$SKIP_BUILD" != "skip-build" ]; then
  echo "== building web =="
  "$FLUTTER" build web --release 2>&1 | tail -3
fi

# free the python server port + any prior debug-Edge on DBG port
for P in "$PORT" "$DBG"; do
  for pid in $(netstat -ano 2>/dev/null | grep ":${P} " | grep LISTENING | awk '{print $NF}' | sort -u); do
    taskkill //F //PID "$pid" >/dev/null 2>&1 || true
  done
done
sleep 1

echo "== serving build/web on :${PORT} =="
python -m http.server "$PORT" --directory build/web >/tmp/httpserver.log 2>&1 &
SERVER_PID=$!
sleep 2

echo "== launching headless Edge =="
EDGE_PROFILE=$(mktemp -d)
"$EDGE" --headless=new --remote-debugging-port=${DBG} \
  --window-size=1310,604 --hide-scrollbars --no-first-run \
  --user-data-dir="$EDGE_PROFILE" "about:blank" >/tmp/edge.log 2>&1 &
EDGE_PID=$!
sleep 3

echo "== capturing =="
export NODE_PATH="C:/Users/rldun/code/simple-card-game/node_modules"
node scripts/capture_board.mjs "$URL" "$OUT"
RC=$?

kill "$EDGE_PID" >/dev/null 2>&1 || true
kill "$SERVER_PID" >/dev/null 2>&1 || true
# kill only the debug-Edge listening on DBG port (not the user's browser)
for pid in $(netstat -ano 2>/dev/null | grep ":${DBG} " | grep LISTENING | awk '{print $NF}' | sort -u); do
  taskkill //F //PID "$pid" >/dev/null 2>&1 || true
done
rm -rf "$EDGE_PROFILE" >/dev/null 2>&1 || true
echo "== done (rc=$RC) -> $OUT =="
exit $RC
