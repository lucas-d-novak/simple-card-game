# tool/bug_pipeline — automated bug-fix runner

The runnable side of [`ai-docs/discord_bug_pipeline.md`](../../ai-docs/discord_bug_pipeline.md).
Takes a structured bug report and drives it through:

```
intake → triage → investigate → implement → verify (mechanical + adversarial)
       → PR → (auto-)merge to rld-mvp-sprint → trigger Pi rebuild/redeploy
```

The INVESTIGATE + IMPLEMENT stages run the same loop documented in
[`ai-docs/bug_fix_workflow.md`](../../ai-docs/bug_fix_workflow.md) (find root cause →
identify the class → minimal fix → repro test).

**This is Phase 0: manual trigger.** You hand it one report JSON; there is no
Discord bot yet. Phases 1+ (the bot) only change the *trigger* — the bot will call
this exact script per accepted report. See the design doc §8 for the phase ladder.

## Where it runs

On the **dev machine** (or any host with the Flutter + Dart toolchain), because
the VERIFY mechanical gate runs `flutter analyze` / `flutter test` / `dart test`.
The Raspberry Pi that serves the alpha does **not** have the toolchain — it only
receives the deploy trigger (§7b). If you run this where flutter is absent, every
fix falls back to a draft PR (the mechanical gate can't go green).

## Requirements

- `git`, `gh` (GitHub CLI, authenticated with push + PR + merge rights on the repo)
- `jq`
- the agent CLI (`claude`, headless) — see `CLAUDE_BIN`/`CLAUDE_ARGS` in config
- Flutter 3.41.5 + Dart (for the verify gate)

## Setup

```bash
cp tool/bug_pipeline/config.example.sh tool/bug_pipeline/config.sh
$EDITOR tool/bug_pipeline/config.sh      # set REPO_ROOT, AUTO_MERGE, DEPLOY_MODE, …
```

`config.sh` is gitignored (it can hold a deploy secret). `config.example.sh` is the
committed, documented template.

## Run

**One report (manual):**

```bash
bash tool/bug_pipeline/run_pipeline.sh tool/bug_pipeline/reports/example.json
```

The report JSON schema is the intake record from the design doc §2 (see
`reports/example.json`): `reportId`, `title`, `summary`, `expected`, `repro[]`,
optional `gameId`, `attachments[]`, `rawText`, and a `discord` source ref
(`channelId` / `messageId` / `threadId`) used to reply back to the reporter.

**Drain the Discord channel on demand** (the "start auto bug fixing from Discord
feedback" trigger — NOT a daemon; you run it when you want it to go):

```bash
bash tool/bug_pipeline/start_from_discord.sh            # process only NEW reports
bash tool/bug_pipeline/start_from_discord.sh --dry-run  # list what it would run
bash tool/bug_pipeline/start_from_discord.sh --since 0  # reprocess ALL history
```

It reads `#bug-reports` (needs `DISCORD_BOT_TOKEN` + `DISCORD_BUGREPORTS_CHANNEL_ID`
in config), normalizes each new message to a report record, and runs each through
`run_pipeline.sh`. A **watermark** (`.discord-watermark.*`) tracks the last handled
message, so re-running only picks up *unattended* reports. A future always-on bot
would call `run_pipeline.sh` the same way — only the trigger differs.

Each report also captures a `discord` source ref (`channelId` / `messageId` /
`threadId`) so the pipeline can reply back on the exact post later (see below).

## Reply back to the reporter (PR opened / merged → Discord notice)

When a PR is opened (draft) **or** merged, the runner posts a comment on the
**original Discord post** so the reporter knows their bug was picked up:

```
🔧 Potentially addressed in PR #123 — https://github.com/…/pull/123
```

This is [`discord_reply.sh`](discord_reply.sh), wired into `run_pipeline.sh` after
`gh pr create` in both the auto-merge and draft-PR branches. It reads the report's
`discord` block (captured at intake by `start_from_discord.sh`) and picks the right
Discord endpoint:

- **normal channel message** → a reply that *references* the player's message
  (`message_reference`), so the notice threads off their report;
- **forum / thread post** (`threadId` set) → a message posted *into the thread*.

It is **best-effort and fail-graceful**: a missing token/ref, a disabled toggle
(`DISCORD_REPLY_ENABLED=0`), or any API error logs one line and exits 0 — it never
crashes the pipeline. Config: `DISCORD_REPLY_ENABLED`, `DISCORD_REPLY_TEMPLATE`
(`{number}`/`{url}` substituted), reusing `DISCORD_BOT_TOKEN`.

> **Bot permissions:** the reply step means the bot needs **Send Messages** (and
> **Send Messages in Threads** for forum posts) in the bug-reports channel, on top
> of the "Read Message History" it already uses for ingestion. Still no repo/shell
> access — the reply contains only the public PR link.

## The two gates (what lets a fix auto-merge)

A fix auto-merges **only if BOTH pass**:

1. **Mechanical** — `flutter analyze`, `flutter test --exclude-tags golden`,
   `dart test`, plus `validate_card_db.dart` when `cards.json` changed. Any red → no merge.
2. **Adversarial** — an independent verifier agent prompted to *refute* the fix
   (real bug fixed? test meaningful? regressions? minimal?). A refute → no merge.

Fail either gate → the fix still opens as a **draft PR** labeled `needs-human`
(you see the attempt; nothing lands blind).

## The auto-merge dial (alpha stance: intentionally unsafe, reversible)

| `AUTO_MERGE` | Behavior |
|---|---|
| `0` (default in the template) | Both gates still run; a passing fix opens a **normal PR** for you to merge. Good for building trust first. |
| `1` | A fix that clears both gates **squash-merges to `rld-mvp-sprint`** and fires the deploy trigger. No human in the merge. |

Extra brakes, always on:
- `MAX_AUTO_MERGES_PER_DAY` — overflow → draft PR (not merge).
- `PAUSE_FILE` (`.PAUSED`) — create it to halt the runner instantly.
- Target branch is hard-pinned to `rld-mvp-sprint`; the runner **refuses** `main`.
- Every merge is an isolated squash with a linked PR + kept `bugfix/*` branch →
  a bad fix is one `git revert <sha>` + rebuild away.

## Deploy (§7b)

On a successful merge, `deploy_trigger.sh <sha>` tells the Pi to rebuild
(`scripts/build_web.sh`, which stamps the git SHA into `version.json`). The
client-side poll in `web/index.html` then hard-reloads every player within ~30s —
the cache-bust is **already built**, this just fires the rebuild.
`DEPLOY_MODE`: `none` (rely on the Pi's pull cron) | `ssh` | `http` (webhook).

## Files

| File | Role |
|---|---|
| `run_pipeline.sh` | the orchestrator (Phase 0 manual trigger) |
| `config.example.sh` | documented config template → copy to `config.sh` |
| `prompts/investigate.md` | read-only root-cause + identify-the-class agent |
| `prompts/implement.md` | minimal-patch-in-worktree agent |
| `prompts/verify.md` | adversarial refute agent |
| `deploy_trigger.sh` | Pi rebuild trigger (ssh/http) + pull-cron snippet |
| `discord_reply.sh` | reply-back step: notify the reporter's Discord post on PR open/merge |
| `start_from_discord.sh` | on-demand Discord ingestion (reads reports, captures the source ref) |
| `reports/example.json` | sample intake record (incl. the `discord` source ref) |

## Status / TODO

- [x] Phase 0 stage flow, worktree isolation, both gates, auto-merge dial, deploy trigger.
- [x] Discord source-ref capture at intake + reply-back on PR open/merge (`discord_reply.sh`).
- [ ] Triage agent (dedupe against open PRs/issues + severity) — currently a thin validity check.
- [ ] Phase 1 Discord read-only bot (ingestion) → calls this runner per report.
- [ ] Harden agent-CLI JSON extraction against the installed `claude` version's output format.
- [ ] Not yet executed end-to-end (this box lacks the toolchain) — first real run should be with `AUTO_MERGE=0`.
