We are trying to make a card game ("Fragments of Boundlessness") that can run on:
Windows, iOS, Android, and web.

**Start here:** [`CLAUDE.md`](CLAUDE.md) is the architecture + workflow source of
truth (project structure, subsystems, testing, deploy); [`README.md`](README.md)
is the quick-start; [`ai-docs/bug_patterns.md`](ai-docs/bug_patterns.md) is the
field guide to recurring bug shapes, and
[`ai-docs/bug_fix_workflow.md`](ai-docs/bug_fix_workflow.md) is our principal
method for fixing card/mechanic bugs (the parallel find-and-stamp-out loop —
use it whenever a card or mechanic bug comes in).

When adding/changing behavior: write or update tests first; don’t change tests unless requirements changed; run targeted tests after each change; keep edits small and incremental; stop when tests are green and summarize what changed.

When making plans: please make plans with checkpoints in mind. Checkpoints are areas where we can run tests and update our progression in our plan.