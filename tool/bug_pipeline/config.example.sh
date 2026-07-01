# Bug-pipeline configuration — copy to config.sh (gitignored) and edit.
#   cp tool/bug_pipeline/config.example.sh tool/bug_pipeline/config.sh
#
# Sourced by run_pipeline.sh. Every value has a safe default; override as needed.

# --- Repo / branch -----------------------------------------------------------
# Absolute path to the repo checkout the runner operates on (must have the
# Flutter/Dart toolchain installed — this is the DEV MACHINE, not the Pi).
REPO_ROOT="${REPO_ROOT:-$HOME/code/simple-card-game}"
# The ONLY branch the pipeline may merge into. main is out of bounds, always.
TARGET_BRANCH="rld-mvp-sprint"

# --- Merge behavior (the alpha auto-merge dial) ------------------------------
# 1 = auto-merge fixes that clear BOTH gates (§5). 0 = open a draft PR instead
# and stop (Phase 3 behavior). Flip to 0 anytime to take agents out of the merge.
AUTO_MERGE="${AUTO_MERGE:-0}"
# Hard cap on auto-merges per UTC day. Overflow → draft PR labeled needs-human.
MAX_AUTO_MERGES_PER_DAY="${MAX_AUTO_MERGES_PER_DAY:-5}"
# Global kill switch: if this file exists, the runner refuses to do anything.
PAUSE_FILE="${PAUSE_FILE:-$REPO_ROOT/tool/bug_pipeline/.PAUSED}"

# --- Agent CLI ---------------------------------------------------------------
# Headless Claude Code invocation used for the investigate/implement/verify
# stages. Must accept a prompt on stdin and print the model's final text.
# Adjust flags to your installed CLI version.
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CLAUDE_ARGS="${CLAUDE_ARGS:--p --output-format text}"

# --- Verify gate (mechanical) ------------------------------------------------
# Commands that MUST exit 0 for a fix to pass the mechanical gate. Card-DB
# validation is only run when assets/card_db/cards.json changed.
ANALYZE_CMD="flutter analyze"
TEST_CMD="flutter test --exclude-tags golden"
SERVER_TEST_CMD="cd server && dart test"
CARDDB_VALIDATE_CMD="dart run tool/validate_card_db.dart"

# --- Deploy trigger (§7b) ----------------------------------------------------
# How the runner tells the Pi to rebuild+redeploy after a merge.
#   none  = do nothing (rely on the Pi's own pull-based cron)
#   ssh   = ssh to the Pi and run the rebuild command
#   http  = POST to an authenticated deploy webhook on the Pi
DEPLOY_MODE="${DEPLOY_MODE:-none}"
DEPLOY_SSH_TARGET="${DEPLOY_SSH_TARGET:-pi@raspberrypi.local}"
DEPLOY_SSH_CMD="${DEPLOY_SSH_CMD:-cd ~/simple-card-game && git fetch origin && git reset --hard origin/$TARGET_BRANCH && bash scripts/build_web.sh}"
DEPLOY_HTTP_URL="${DEPLOY_HTTP_URL:-}"          # e.g. https://alpha.example.com/deploy
DEPLOY_HTTP_TOKEN="${DEPLOY_HTTP_TOKEN:-}"       # shared secret sent as a bearer token

# --- Discord ingestion (for start_from_discord.sh, the on-demand trigger) -----
# A bot token with "Read Message History" on the bug-reports channel, and the
# channel id. Used ONLY to READ reports on demand (least privilege — the bot
# needs no repo/shell access). Leave empty until you stand up the bot.
DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
DISCORD_BUGREPORTS_CHANNEL_ID="${DISCORD_BUGREPORTS_CHANNEL_ID:-}"

# --- Discord status posting (optional; Phase 1+) -----------------------------
# When set, the runner POSTs status back to the report's thread. Empty = quiet.
DISCORD_STATUS_WEBHOOK="${DISCORD_STATUS_WEBHOOK:-}"
