#!/usr/bin/env bash
# Deploy trigger (pipeline stage 7 / §7b): tell the Pi to rebuild + redeploy the
# web app after a fix has merged to rld-mvp-sprint. The client-side cache-bust
# (web/index.html polling version.json) then hard-reloads every player within
# ~30s — see scripts/build_web.sh + web/index.html. This script only fires the
# REBUILD; it does not itself build.
#
# Usage:  bash tool/bug_pipeline/deploy_trigger.sh <merged_sha>
# Reads DEPLOY_MODE + targets from config.sh (see config.example.sh).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${HERE}/config.sh" 2>/dev/null || source "${HERE}/config.example.sh"

SHA="${1:-unknown}"

case "${DEPLOY_MODE}" in
  none)
    echo "[deploy] DEPLOY_MODE=none — skipping push trigger."
    echo "[deploy] The Pi's pull-based cron will pick up ${SHA} on its next tick."
    ;;
  ssh)
    echo "[deploy] ssh ${DEPLOY_SSH_TARGET} → rebuild for ${SHA}"
    ssh "${DEPLOY_SSH_TARGET}" "${DEPLOY_SSH_CMD}"
    echo "[deploy] Pi rebuild triggered."
    ;;
  http)
    if [[ -z "${DEPLOY_HTTP_URL}" ]]; then
      echo "[deploy] ERROR: DEPLOY_MODE=http but DEPLOY_HTTP_URL is empty." >&2
      exit 1
    fi
    echo "[deploy] POST ${DEPLOY_HTTP_URL} for ${SHA}"
    curl -fsS -X POST "${DEPLOY_HTTP_URL}" \
      -H "Authorization: Bearer ${DEPLOY_HTTP_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"sha\":\"${SHA}\",\"branch\":\"${TARGET_BRANCH}\"}"
    echo "[deploy] Deploy webhook fired."
    ;;
  *)
    echo "[deploy] ERROR: unknown DEPLOY_MODE='${DEPLOY_MODE}'" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Pull-based fallback (run this ON THE PI as a cron/systemd-timer, every ~1 min).
# It self-heals the alpha to the latest merged SHA even if the push trigger is
# missed. Copy into a Pi-side script; it is inert here.
#
#   #!/usr/bin/env bash
#   set -euo pipefail
#   cd ~/simple-card-game
#   git fetch --quiet origin rld-mvp-sprint
#   LOCAL=$(git rev-parse HEAD); REMOTE=$(git rev-parse origin/rld-mvp-sprint)
#   if [[ "$LOCAL" != "$REMOTE" ]]; then
#     git reset --hard "$REMOTE"
#     bash scripts/build_web.sh                 # stamps version.json with the SHA
#     rsync -a --delete build/web/ /var/www/alpha/   # atomic-ish swap of served dir
#   fi
# ---------------------------------------------------------------------------
