# agent-workbench workspace

This directory is the **runtime workspace** for `agent-workbench-runner`.

## Roles

- **Planner / supervisor / final acceptance:** Codex (or the invoking agent that owns acceptance)
- **Managed executor:** Claude Code via `{skillBaseDir}/scripts/claude-delegate.ps1`
- **Ordinary work:** direct collaboration — no six-section task file required

## Layout

- `config.json` — workspace paths and defaults (portable; no machine-specific secrets)
- `sandbox/` — disposable execution root (default). Override in `config.json` if needed.
- `docs/task.md` — current managed task contract (six sections)
- `.delegate-runs/` — run artifacts; do not commit secrets

## Rules

1. Prefer direct Codex ↔ Claude Code for ordinary bounded work.
2. Use the managed runner only when the skill Core Rule triggers.
3. Run scripts from the **skill package** `scripts/` directory, not from a forked copy in this workspace.
4. Keep main project worktrees clean: managed runs should target `sandbox_path` unless the user explicitly allows otherwise.
5. Final acceptance stays with the planner agent — never with Claude Code alone.
