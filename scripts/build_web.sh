#!/usr/bin/env bash
# Build the Flutter web app AND stamp the current git SHA into version.json so
# the client's version-poll (web/index.html) can detect a redeploy and hard-
# reload everyone within ~30s — no manual cache clearing.
#
# Usage:  bash scripts/build_web.sh   (run from the repo root)
#
# After this, deploy the contents of build/web as usual.
set -euo pipefail

cd "$(dirname "$0")/.."

# Resolve a build id: short git SHA (+ "-dirty" if there are uncommitted changes).
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  SHA="${SHA}-dirty"
fi
echo "Build id: ${SHA}"

# Stamp the SOURCE version.json so `flutter build web` copies the stamped file.
printf '{ "build": "%s" }\n' "${SHA}" > web/version.json

# Build.
flutter build web --release

# Belt-and-suspenders: ensure the stamp is present in the output too (in case a
# cached copy was emitted).
printf '{ "build": "%s" }\n' "${SHA}" > build/web/version.json

echo "Done. build/web is stamped with version ${SHA} — deploy it."

# Purge the Cloudflare edge cache so the newly-built (NON-content-hashed) assets
# — main.dart.js et al, which serve_web.py edge-caches via s-maxage — aren't
# served stale from the edge after a deploy. Requires an owner-only
# ~/.cloudflared/sharts-purge.env (CF_PURGE_TOKEN + CF_ZONE_ID); skipped
# gracefully (never fails the build) if absent or on any API error.
PURGE_ENV="${HOME}/.cloudflared/sharts-purge.env"
if [ -f "$PURGE_ENV" ]; then
  # shellcheck disable=SC1090
  source "$PURGE_ENV"
  if [ -n "${CF_PURGE_TOKEN:-}" ] && [ -n "${CF_ZONE_ID:-}" ]; then
    echo "Purging Cloudflare edge cache…"
    resp="$(curl -s -X POST \
      "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
      -H "Authorization: Bearer ${CF_PURGE_TOKEN}" \
      -H "Content-Type: application/json" \
      --data '{"purge_everything":true}' || true)"
    if printf '%s' "$resp" | grep -q '"success":true'; then
      echo "  edge cache purged."
    else
      echo "  WARN: CF purge failed (deploy still OK): ${resp:-<no response>}"
    fi
  else
    echo "Skipping CF purge (env present but CF_PURGE_TOKEN/CF_ZONE_ID unset)."
  fi
else
  echo "Skipping CF purge (no ${PURGE_ENV})."
fi
