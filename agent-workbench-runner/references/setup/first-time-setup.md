# First-time setup

Blocking step when no workspace config is found. Do **not** classify or run managed scripts until this finishes.

## Lookup order (stop at first hit)

1. `$PWD/.agent-workbench/config.json` — project workspace  
2. `${HOME}/.agent-workbench/config.json` — user workspace  
   - Windows: `%USERPROFILE%\.agent-workbench\config.json`

If either file exists and is valid JSON with non-empty `workspace_root`, load it and continue the main skill.

## When missing — full setup

Use the runtime's user-question tool (e.g. `AskUserQuestion`) when available; otherwise ask in plain text and wait.

### Q1 — Workspace level

| Option | Path |
| --- | --- |
| User home (recommended for first install) | `~/.agent-workbench/` |
| Current project | `$PWD/.agent-workbench/` |

### Q2 — Sandbox location

| Option | Path |
| --- | --- |
| Embedded (recommended) | `{workspace}/sandbox/` |
| Custom absolute path | user-provided disposable directory |

### Q3 — Language (optional)

`zh` (default) or `en`.

## Materialize workspace

Let `{baseDir}` = directory of this skill's `SKILL.md`.

1. Create the chosen workspace root if missing.  
2. Copy templates (never move from the publisher's machine):

```text
{baseDir}/templates/workspace/AGENTS.md          → {workspace}/AGENTS.md
{baseDir}/templates/workspace/docs/task.md       → {workspace}/docs/task.md
{baseDir}/templates/workspace/sandbox/.gitkeep   → {workspace}/sandbox/.gitkeep   (if embedded sandbox)
{baseDir}/templates/workspace/.delegate-runs/.gitkeep → {workspace}/.delegate-runs/.gitkeep
```

3. Write `{workspace}/config.json`:

```json
{
  "schema_version": 1,
  "workspace_root": "<absolute path to workspace>",
  "sandbox_path": "./sandbox",
  "permission_profile_default": "default",
  "claude_path": null,
  "language": "zh"
}
```

If the user chose a custom sandbox, set `sandbox_path` to that **absolute** path and create the directory if needed.

4. Resolve `sandbox_path`: if relative, join with `workspace_root`. Ensure the directory exists.  
5. Summarize in one short message: workspace path, sandbox path, how to re-run setup (delete config or say「重新初始化 workbench」).  
6. Continue with the main skill workflow.

## Re-init

If the user asks to re-initialize:

1. Confirm they understand existing `docs/task.md` / local notes may be overwritten for templates only (do not delete `.delegate-runs` unless they ask).  
2. Re-run materialize steps; preserve `config.json` keys they want to keep when possible.

## DO NOT

- Do not read or require `F:\agent-workbench` or any other author-machine path.  
- Do not move files out of the skill package or the user's existing repos.  
- Do not copy the author's historical `.delegate-runs` into the new workspace.  
- Do not put executable script forks into the workspace; always invoke `{baseDir}/scripts/*.ps1`.
