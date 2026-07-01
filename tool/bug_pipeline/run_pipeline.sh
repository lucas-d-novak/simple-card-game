#!/usr/bin/env bash
# =============================================================================
# Bug-fix pipeline runner — Phase 0 (manual trigger).
#
# Chains the stages from ai-docs/discord_bug_pipeline.md over a SINGLE report:
#   intake → triage → investigate → implement → verify (mechanical + adversarial)
#   → PR → (auto-)merge → deploy trigger.
#
# Phase 0 = you hand it one report JSON; no Discord bot yet. The bot (Phase 1+)
# only changes the TRIGGER — it will call this same script per accepted report.
#
# Runs on the DEV MACHINE (needs the Flutter/Dart toolchain for the verify gate).
#
# Usage:
#   cp tool/bug_pipeline/config.example.sh tool/bug_pipeline/config.sh   # once
#   bash tool/bug_pipeline/run_pipeline.sh tool/bug_pipeline/reports/example.json
#
# Deps: git, gh (authenticated), jq, and the agent CLI (claude). Plus flutter+dart.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${HERE}/config.sh" 2>/dev/null || { echo "no config.sh — using config.example.sh defaults"; source "${HERE}/config.example.sh"; }

# ---- helpers ----------------------------------------------------------------
log()  { printf '\033[1;36m[pipeline]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pipeline] WARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[pipeline] FATAL:\033[0m %s\n' "$*" >&2; exit 1; }

status() {  # post a status line to the report thread if a webhook is configured
  local msg="$1"
  log "status: ${msg}"
  [[ -n "${DISCORD_STATUS_WEBHOOK}" ]] && \
    curl -fsS -X POST "${DISCORD_STATUS_WEBHOOK}" -H 'Content-Type: application/json' \
      -d "$(jq -n --arg c "${msg}" '{content:$c}')" >/dev/null 2>&1 || true
}

# Run an agent stage: substitute {{VARS}} into a prompt template, pipe to the CLI,
# and echo the model's raw output. Placeholders are passed as NAME=value pairs.
run_agent() {
  local prompt_file="$1"; shift
  local prompt; prompt="$(cat "${prompt_file}")"
  local pair name val
  for pair in "$@"; do
    name="${pair%%=*}"; val="${pair#*=}"
    # shell-safe literal replace of {{NAME}} with $val
    prompt="${prompt//\{\{${name}\}\}/${val}}"
  done
  printf '%s' "${prompt}" | ( cd "${WORKTREE}" && ${CLAUDE_BIN} ${CLAUDE_ARGS} )
}

# Extract the first ```json … ``` fenced block from stdin (agent output).
extract_json() { awk '/^```json/{f=1;next} /^```/{if(f)exit} f'; }

# ---- preflight guards -------------------------------------------------------
[[ -f "${PAUSE_FILE}" ]] && die "PAUSE_FILE present (${PAUSE_FILE}) — pipeline is paused. Remove it to resume."
command -v jq  >/dev/null || die "jq not found"
command -v git >/dev/null || die "git not found"
command -v gh  >/dev/null || die "gh (GitHub CLI) not found / not authenticated"
command -v flutter >/dev/null || warn "flutter not found — the mechanical VERIFY gate cannot run here; fixes will fall back to draft PRs."
[[ -d "${REPO_ROOT}/.git" ]] || die "REPO_ROOT is not a git checkout: ${REPO_ROOT}"
[[ "${TARGET_BRANCH}" != "main" ]] || die "refusing: TARGET_BRANCH must never be main"

REPORT_FILE="${1:-}"
[[ -n "${REPORT_FILE}" && -f "${REPORT_FILE}" ]] || die "usage: run_pipeline.sh <report.json>"
jq -e . "${REPORT_FILE}" >/dev/null 2>&1 || die "report is not valid JSON: ${REPORT_FILE}"

REPORT_JSON="$(cat "${REPORT_FILE}")"
REPORT_ID="$(jq -r '.reportId // "disc-unknown"' <<<"${REPORT_JSON}")"
TITLE="$(jq -r '.title // .summary // "untitled bug"' <<<"${REPORT_JSON}")"
SLUG="$(printf '%s' "${TITLE}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-\+/-/g; s/^-//; s/-$//' | cut -c1-40)"
BRANCH="bugfix/${REPORT_ID}-${SLUG}"

# ---- 1–2. intake + triage ---------------------------------------------------
# Phase 0 triage is a cheap validity check; dedupe/severity via an agent is a
# Phase 2 add-on (TODO). Reject empty/thin reports before spending agent tokens.
[[ "$(jq -r '.summary // ""' <<<"${REPORT_JSON}" | wc -c)" -ge 12 ]] || die "report too thin to act on (need a real summary)"
status "🔎 investigating ${REPORT_ID}: ${TITLE}"

# ---- worktree isolation -----------------------------------------------------
cd "${REPO_ROOT}"
git fetch --quiet origin "${TARGET_BRANCH}"
WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/bugpipe-${REPORT_ID}.XXXX")"
git worktree add --quiet -b "${BRANCH}" "${WORKTREE}" "origin/${TARGET_BRANCH}" \
  || die "could not create worktree/branch ${BRANCH}"
cleanup() { cd "${REPO_ROOT}"; git worktree remove --force "${WORKTREE}" 2>/dev/null || true; }
trap cleanup EXIT
log "worktree ${WORKTREE} on ${BRANCH} (off origin/${TARGET_BRANCH})"

# ---- 3. investigate (read-only) --------------------------------------------
FINDING="$(run_agent "${HERE}/prompts/investigate.md" "REPORT_JSON=${REPORT_JSON}" | extract_json)"
jq -e . <<<"${FINDING}" >/dev/null 2>&1 || die "investigate stage returned no valid JSON finding"
CONF="$(jq -r '.confidence // "low"' <<<"${FINDING}")"
REPRO="$(jq -r '.reproduced // false' <<<"${FINDING}")"
if [[ "${CONF}" == "low" || "${REPRO}" != "true" ]]; then
  status "🤔 couldn't confidently reproduce ${REPORT_ID} — parking for a human. $(jq -r '.needs_info | join("; ")' <<<"${FINDING}")"
  die "investigation low-confidence/not reproduced — stopping before implement (no wasted patch)."
fi
log "root cause: $(jq -r '.root_cause' <<<"${FINDING}")"

# ---- 4. implement (mutates the worktree) ------------------------------------
IMPL="$(run_agent "${HERE}/prompts/implement.md" "FINDING_JSON=${FINDING}" "REPORT_JSON=${REPORT_JSON}" | extract_json)"
jq -e . <<<"${IMPL}" >/dev/null 2>&1 || die "implement stage returned no valid JSON"
( cd "${WORKTREE}" && git diff --quiet HEAD ) && die "implement stage produced no committed changes"
DIFF="$(cd "${WORKTREE}" && git diff "origin/${TARGET_BRANCH}"...HEAD)"
CARDDB_TOUCHED="$(cd "${WORKTREE}" && git diff --name-only "origin/${TARGET_BRANCH}"...HEAD | grep -qx 'assets/card_db/cards.json' && echo true || echo false)"

# ---- 5a. verify — mechanical gate -------------------------------------------
MECH="green"; MECH_LOG=""
run_gate() { log "gate: $*"; ( cd "${WORKTREE}" && eval "$*" ) >>"${WORKTREE}/.gate.log" 2>&1 || { MECH="red"; MECH_LOG="${MECH_LOG} FAILED: $*"; }; }
if command -v flutter >/dev/null; then
  run_gate "${ANALYZE_CMD}"
  run_gate "${TEST_CMD}"
  run_gate "${SERVER_TEST_CMD}"
  [[ "${CARDDB_TOUCHED}" == "true" ]] && run_gate "${CARDDB_VALIDATE_CMD}"
else
  MECH="red"; MECH_LOG="toolchain absent — mechanical gate could not run"
fi
log "mechanical gate: ${MECH}${MECH_LOG:+ (${MECH_LOG})}"

# ---- 5b. verify — adversarial gate ------------------------------------------
VERDICT_JSON="$(run_agent "${HERE}/prompts/verify.md" "FINDING_JSON=${FINDING}" "DIFF=${DIFF}" "MECHANICAL_RESULT=${MECH}${MECH_LOG}" | extract_json)"
VERDICT="$(jq -r '.verdict // "refuted"' <<<"${VERDICT_JSON}" 2>/dev/null || echo refuted)"
log "adversarial gate: ${VERDICT}"

# ---- 6. PR + (auto-)merge ---------------------------------------------------
( cd "${WORKTREE}" && git push --quiet -u origin "${BRANCH}" )
PR_BODY="$(printf 'Automated fix for **%s** (%s).\n\n**Root cause:** %s\n\n**Change:** %s\n\nGates — mechanical: `%s`, adversarial: `%s`.\n\n_Generated by tool/bug_pipeline._' \
  "${TITLE}" "${REPORT_ID}" "$(jq -r '.root_cause' <<<"${FINDING}")" "$(jq -r '.summary' <<<"${IMPL}")" "${MECH}" "${VERDICT}")"

# Daily auto-merge cap (per UTC day).
CAP_FILE="${HERE}/.automerge-count.$(date -u +%F)"
MERGES_TODAY="$(cat "${CAP_FILE}" 2>/dev/null || echo 0)"

if [[ "${MECH}" == "green" && "${VERDICT}" == "confirmed" && "${AUTO_MERGE}" == "1" && "${MERGES_TODAY}" -lt "${MAX_AUTO_MERGES_PER_DAY}" ]]; then
  PR_URL="$(cd "${WORKTREE}" && gh pr create --base "${TARGET_BRANCH}" --head "${BRANCH}" --title "fix: ${TITLE} (${REPORT_ID})" --body "${PR_BODY}")"
  ( cd "${WORKTREE}" && gh pr merge "${BRANCH}" --squash --delete-branch --admin )
  echo $(( MERGES_TODAY + 1 )) > "${CAP_FILE}"
  MERGED_SHA="$(cd "${REPO_ROOT}" && git fetch --quiet origin "${TARGET_BRANCH}" && git rev-parse --short "origin/${TARGET_BRANCH}")"
  status "🔧 fix merged: ${PR_URL} (${MERGED_SHA})"
  # ---- 7. deploy trigger ----------------------------------------------------
  bash "${HERE}/deploy_trigger.sh" "${MERGED_SHA}" && status "🚀 ${REPORT_ID} is live (${MERGED_SHA})."
else
  REASON="AUTO_MERGE=${AUTO_MERGE}"
  [[ "${MECH}"    != "green"     ]] && REASON="mechanical gate red"
  [[ "${VERDICT}" != "confirmed" ]] && REASON="adversarial gate refuted"
  [[ "${MERGES_TODAY}" -ge "${MAX_AUTO_MERGES_PER_DAY}" ]] && REASON="daily auto-merge cap reached"
  PR_URL="$(cd "${WORKTREE}" && gh pr create --draft --base "${TARGET_BRANCH}" --head "${BRANCH}" --title "fix: ${TITLE} (${REPORT_ID})" --body "${PR_BODY}" --label needs-human 2>/dev/null || cd "${WORKTREE}" && gh pr create --draft --base "${TARGET_BRANCH}" --head "${BRANCH}" --title "fix: ${TITLE} (${REPORT_ID})" --body "${PR_BODY}")"
  status "📝 draft PR for a human (${REASON}): ${PR_URL}"
fi

log "done: ${REPORT_ID}"
