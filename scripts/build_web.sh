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
