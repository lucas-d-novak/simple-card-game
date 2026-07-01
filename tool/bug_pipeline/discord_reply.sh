#!/usr/bin/env bash
# =============================================================================
# Reply-back step — notify a Discord bug reporter that their bug was picked up.
#
# Given a bug report JSON (which carries the source Discord reference captured at
# intake by start_from_discord.sh) plus a PR number + URL, this posts a comment
# back on the ORIGINAL Discord post: e.g.
#     🔧 Potentially addressed in PR #123 — https://github.com/…/pull/123
# so the reporter sees their bug was picked up and can follow the fix.
#
# It handles the two shapes a report can come from (design §1):
#   • a normal #bug-reports CHANNEL MESSAGE  → we reply *referencing* that message
#     (POST /channels/{channelId}/messages with a message_reference), so the
#     notification threads directly off the player's post.
#   • a FORUM / THREAD post                  → we post *into the thread*
#     (POST /channels/{threadId}/messages), which is where a forum post lives.
#
# Fail-graceful by design: a missing token, a missing/blank Discord ref, or an
# API error logs ONE clear line and exits 0. Notifying the reporter is a nicety;
# it must NEVER hard-crash the fix pipeline. (Wire callers still add `|| true`.)
#
# Usage:
#   bash tool/bug_pipeline/discord_reply.sh <report.json> <pr_number> <pr_url>
#
# Needs (in config.sh): DISCORD_BOT_TOKEN — a bot with "Send Messages" (and
# "Send Messages in Threads" for forum posts) in the bug-reports channel.
# Message text is templated via DISCORD_REPLY_TEMPLATE ({number}, {url}).
# =============================================================================
# NOTE: intentionally NOT `set -e` — this step is best-effort and must not abort
# the pipeline on any failure. We guard explicitly and always exit 0.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${HERE}/config.sh" 2>/dev/null || source "${HERE}/config.example.sh"

log()  { printf '\033[1;36m[reply]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[reply] SKIP:\033[0m %s\n' "$*" >&2; }

API="${DISCORD_API_BASE:-https://discord.com/api/v10}"

REPORT_FILE="${1:-}"
PR_NUMBER="${2:-}"
PR_URL="${3:-}"

# ---- graceful preconditions (log + exit 0, never crash) ---------------------
if [[ "${DISCORD_REPLY_ENABLED:-1}" != "1" ]]; then
  log "DISCORD_REPLY_ENABLED != 1 — reporter notification disabled."; exit 0
fi
command -v curl >/dev/null 2>&1 || { warn "curl not found — cannot notify reporter."; exit 0; }
command -v jq   >/dev/null 2>&1 || { warn "jq not found — cannot notify reporter."; exit 0; }
if [[ -z "${DISCORD_BOT_TOKEN:-}" ]]; then
  warn "DISCORD_BOT_TOKEN not set — skipping reporter reply for PR #${PR_NUMBER:-?}."; exit 0
fi
if [[ -z "${REPORT_FILE}" || ! -f "${REPORT_FILE}" ]]; then
  warn "no report file given — nothing to reply to."; exit 0
fi
if [[ -z "${PR_NUMBER}" || -z "${PR_URL}" ]]; then
  warn "missing PR number/url — nothing to post."; exit 0
fi

# ---- pull the source Discord reference persisted at intake ------------------
CHANNEL_ID="$(jq -r '.discord.channelId // ""' "${REPORT_FILE}" 2>/dev/null)"
MESSAGE_ID="$(jq -r '.discord.messageId // ""' "${REPORT_FILE}" 2>/dev/null)"
THREAD_ID="$(jq -r '.discord.threadId // ""'  "${REPORT_FILE}" 2>/dev/null)"
# Treat literal "null" (from older/hand-written reports) as blank.
[[ "${THREAD_ID}"  == "null" ]] && THREAD_ID=""
[[ "${CHANNEL_ID}" == "null" ]] && CHANNEL_ID=""
[[ "${MESSAGE_ID}" == "null" ]] && MESSAGE_ID=""

if [[ -z "${THREAD_ID}" && ( -z "${CHANNEL_ID}" || -z "${MESSAGE_ID}" ) ]]; then
  warn "report has no usable Discord ref (channelId/messageId or threadId) — likely a non-Discord source. Skipping."
  exit 0
fi

# ---- render the message text (templated) ------------------------------------
TEMPLATE="${DISCORD_REPLY_TEMPLATE:-}"
# Two-step default: a literal '}' inside ${VAR:-default} closes the expansion early.
[[ -z "${TEMPLATE}" ]] && TEMPLATE='🔧 Potentially addressed in PR #{number} — {url}'
CONTENT="${TEMPLATE//\{number\}/${PR_NUMBER}}"
CONTENT="${CONTENT//\{url\}/${PR_URL}}"

# ---- pick the endpoint + payload by post shape ------------------------------
# Forum/thread post → post INTO the thread. Normal message → reply referencing it.
if [[ -n "${THREAD_ID}" ]]; then
  TARGET="${THREAD_ID}"
  PAYLOAD="$(jq -n --arg c "${CONTENT}" '{content:$c}')"
  KIND="thread ${THREAD_ID}"
else
  TARGET="${CHANNEL_ID}"
  PAYLOAD="$(jq -n --arg c "${CONTENT}" --arg mid "${MESSAGE_ID}" --arg cid "${CHANNEL_ID}" \
    '{content:$c, message_reference:{message_id:$mid, channel_id:$cid, fail_if_not_exists:false}}')"
  KIND="reply to message ${MESSAGE_ID} in channel ${CHANNEL_ID}"
fi

log "notifying reporter (${KIND}) → PR #${PR_NUMBER}"
HTTP_CODE="$(curl -sS -o /tmp/discord_reply.$$ -w '%{http_code}' \
  -X POST "${API}/channels/${TARGET}/messages" \
  -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" 2>/dev/null)"
HTTP_CODE="${HTTP_CODE:-000}"

if [[ "${HTTP_CODE}" =~ ^2 ]]; then
  log "posted reporter reply (HTTP ${HTTP_CODE})."
else
  # Best-effort: surface the error but do NOT fail the pipeline.
  warn "Discord API returned HTTP ${HTTP_CODE} — reporter not notified (check bot perms: Send Messages / Send Messages in Threads). $(head -c 300 /tmp/discord_reply.$$ 2>/dev/null)"
fi
rm -f "/tmp/discord_reply.$$" 2>/dev/null || true
exit 0
