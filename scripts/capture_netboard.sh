#!/usr/bin/env bash
# Capture the networked board (?netboard=1 fixture) for visual iteration.
# Usage: scripts/capture_netboard.sh [outPath] [skip-build]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-screenshots/net_board.png}"
SKIP_BUILD="${2:-}"
PORT=8123
DBG=9222
FLUTTER=/c/Users/rldun/code/flutter/bin/flutter
EDGE="C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
URL="http://localhost:${PORT}/?netboard=1"

if [ "$SKIP_BUILD" != "skip-build" ]; then
  echo "== building web =="
  "$FLUTTER" build web --release 2>&1 | tail -2
fi

# free ports
for P in "$PORT" "$DBG"; do
  for pid in $(netstat -ano 2>/dev/null | grep ":${P} " | grep LISTENING | awk '{print $NF}' | sort -u); do
    taskkill //F //PID "$pid" >/dev/null 2>&1 || true
  done
done
sleep 1

echo "== serving build/web on :${PORT} =="
python -m http.server "$PORT" --directory build/web >/tmp/net_httpserver.log 2>&1 &
SERVER_PID=$!
# wait until the server actually answers
for i in $(seq 1 20); do
  if curl -s "http://localhost:${PORT}/" >/dev/null 2>&1; then break; fi
  sleep 0.5
done

echo "== launching headless Edge =="
EDGE_PROFILE=$(mktemp -d)
"$EDGE" --headless=new --remote-debugging-port=${DBG} \
  --window-size=1310,604 --hide-scrollbars --no-first-run \
  --user-data-dir="$EDGE_PROFILE" "about:blank" >/tmp/net_edge.log 2>&1 &
EDGE_PID=$!
sleep 3

echo "== capturing $URL =="
export NODE_PATH="${ROOT}/node_modules"
node scripts/capture_board.mjs "$URL" "$OUT"
RC=$?

kill "$EDGE_PID" >/dev/null 2>&1 || true
kill "$SERVER_PID" >/dev/null 2>&1 || true
for pid in $(netstat -ano 2>/dev/null | grep ":${DBG} " | grep LISTENING | awk '{print $NF}' | sort -u); do
  taskkill //F //PID "$pid" >/dev/null 2>&1 || true
done
rm -rf "$EDGE_PROFILE" >/dev/null 2>&1 || true
echo "== done (rc=$RC) -> $OUT =="
exit $RC
