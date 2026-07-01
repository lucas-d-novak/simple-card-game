#!/usr/bin/env bash
# =============================================================================
# On-demand Discord trigger — "start auto bug fixing from feedback in Discord".
#
# The pipeline is NOT a daemon. You run THIS when you want it to go: it reads new
# messages from the #bug-reports channel, normalizes each into a report record,
# and drains them through run_pipeline.sh (investigate → fix → verify → PR →
# auto-merge → deploy). It only processes messages NEWER than the last one it
# handled (a watermark), so re-running just picks up "unattended" reports.
#
# Usage:
#   bash tool/bug_pipeline/start_from_discord.sh            # drain new reports
#   bash tool/bug_pipeline/start_from_discord.sh --since 0  # reprocess ALL history
#   bash tool/bug_pipeline/start_from_discord.sh --dry-run  # list, don't run
#
# Needs (in config.sh): DISCORD_BOT_TOKEN (a bot with Read Message History on the
# channel) + DISCORD_BUGREPORTS_CHANNEL_ID. This is the manual-trigger front door;
# a future always-on bot (design §1 Option A) would call run_pipeline.sh the same
# way — only the trigger differs.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${HERE}/config.sh" 2>/dev/null || source "${HERE}/config.example.sh"

log()  { printf '\033[1;36m[discord]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[discord] FATAL:\033[0m %s\n' "$*" >&2; exit 1; }

DRY_RUN=0; SINCE_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    --since)   SINCE_OVERRIDE="$2"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done

[[ -f "${PAUSE_FILE}" ]] && die "PAUSE_FILE present — pipeline paused."
command -v jq   >/dev/null || die "jq not found"
command -v curl >/dev/null || die "curl not found"
[[ -n "${DISCORD_BOT_TOKEN:-}" ]]            || die "DISCORD_BOT_TOKEN not set in config.sh"
[[ -n "${DISCORD_BUGREPORTS_CHANNEL_ID:-}" ]] || die "DISCORD_BUGREPORTS_CHANNEL_ID not set in config.sh"

API="https://discord.com/api/v10"
WATERMARK_FILE="${HERE}/.discord-watermark.${DISCORD_BUGREPORTS_CHANNEL_ID}"
AFTER="${SINCE_OVERRIDE:-$(cat "${WATERMARK_FILE}" 2>/dev/null || echo 0)}"
TMP_REPORTS="$(mktemp -d)"; trap 'rm -rf "${TMP_REPORTS}"' EXIT

log "fetching #bug-reports messages after id=${AFTER} …"
# Discord returns newest-first; `after` pages forward in time. We ask for up to
# 100 and process oldest→newest so the watermark advances monotonically. (For a
# big backlog, loop with `after` = last id until an empty page — TODO.)
MESSAGES="$(curl -fsS -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  "${API}/channels/${DISCORD_BUGREPORTS_CHANNEL_ID}/messages?limit=100&after=${AFTER}")" \
  || die "Discord API fetch failed (token scope / channel id?)"

COUNT="$(jq 'length' <<<"${MESSAGES}")"
[[ "${COUNT}" -gt 0 ]] || { log "no new reports."; exit 0; }
log "found ${COUNT} new message(s)."

NEWEST="${AFTER}"
# oldest → newest
while IFS= read -r msg; do
  MID="$(jq -r '.id' <<<"${msg}")"
  IS_BOT="$(jq -r '.author.bot // false' <<<"${msg}")"
  CONTENT="$(jq -r '.content // ""' <<<"${msg}")"
  AUTHOR="$(jq -r '.author.username // "unknown"' <<<"${msg}")"
  # Source Discord ref (so the reply-back step can find the exact post later):
  #   channelId = where the message lives (message's channel_id, else the channel
  #               we're reading); messageId = the post; threadId = set if this
  #               message spawned a thread / is a forum post (post replies INTO it).
  MSG_CHANNEL="$(jq -r '.channel_id // ""' <<<"${msg}")"
  [[ -z "${MSG_CHANNEL}" ]] && MSG_CHANNEL="${DISCORD_BUGREPORTS_CHANNEL_ID}"
  THREAD_ID="$(jq -r '.thread.id // ""' <<<"${msg}")"

  NEWEST="${MID}"   # advance watermark even for skipped chatter, so we don't rescan it

  # Cheap pre-filter (design §1): skip bots, empties, and one-word chatter.
  if [[ "${IS_BOT}" == "true" ]] || [[ "$(wc -w <<<"${CONTENT}")" -lt 3 ]]; then
    log "skip ${MID} (bot/too-short)"; continue
  fi

  # Normalize to the intake record schema (design §2). Light Phase-0 normalize:
  # rawText carries the full message; summary seeds triage. (A richer intake
  # agent that splits expected/repro is a TODO.)
  REPORT_FILE="${TMP_REPORTS}/disc-${MID}.json"
  jq -n --arg id "disc-${MID}" --arg who "${AUTHOR}" --arg txt "${CONTENT}" \
    --arg cid "${MSG_CHANNEL}" --arg mid "${MID}" --arg tid "${THREAD_ID}" \
    '{reportId:$id, source:"discord", reporter:$who,
      title:($txt|split("\n")[0]|.[0:80]), summary:$txt,
      expected:"", repro:[], gameId:null, attachments:[], rawText:$txt,
      discord:{channelId:$cid, messageId:$mid,
               threadId:(if $tid=="" then null else $tid end)}}' \
    > "${REPORT_FILE}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "[dry-run] would run pipeline for ${MID}: $(jq -r '.title' "${REPORT_FILE}")"
  else
    log "→ pipeline for ${MID}: $(jq -r '.title' "${REPORT_FILE}")"
    # Each report is independent; one failure must not abort the drain.
    bash "${HERE}/run_pipeline.sh" "${REPORT_FILE}" || log "pipeline FAILED for ${MID} (continuing)"
  fi
done < <(jq -c 'sort_by(.timestamp) | .[]' <<<"${MESSAGES}")

# Persist the watermark so the next run only sees newer reports.
[[ "${DRY_RUN}" == "1" ]] || echo "${NEWEST}" > "${WATERMARK_FILE}"
log "done. watermark=${NEWEST}"
