---
name: agent-workbench-runner
description: Classify an agent-workbench task into direct Codex-to-Claude Code collaboration or a high-risk managed runner path; run first-time workspace setup when needed. Use when the user invokes $agent-workbench-runner, asks to use the agent workbench, or wants sandboxed Codex-plan / Claude-execute runs.
---

# Agent Workbench Runner

Portable front door for Codex-plan / Claude-execute workflows.

- **Skill package** (`{baseDir}`): classification rules + bundled scripts + contract docs (treat as read-only logic).
- **Runtime workspace**: project `.agent-workbench/` or user `~/.agent-workbench/` — config, task file, sandbox, run artifacts.

Invoking this skill starts **classification**, not a mandatory delegate run.

## Resolve paths

1. `{baseDir}` = directory containing this `SKILL.md`.
2. Scripts always run from `{baseDir}/scripts/` (never a workspace fork):
   - `claude-delegate.ps1`
   - `claude-cli-discovery.ps1` (dot-sourced by delegate)
   - `codex-route.ps1`
   - `list-delegate-runs.ps1`
3. Contract docs live at `{baseDir}/docs/`.
4. Workspace config lookup (first hit wins):
   1. `$PWD/.agent-workbench/config.json`
   2. `$HOME/.agent-workbench/config.json` (Windows: `%USERPROFILE%\.agent-workbench\config.json`)

If no valid config exists, **stop** and run [references/setup/first-time-setup.md](references/setup/first-time-setup.md). Do not classify or execute managed runs until setup finishes.

From config:

- `workspace_root` — absolute workspace path
- `sandbox_path` — absolute, or relative to `workspace_root` (default `./sandbox`)
- `permission_profile_default` — default `default`
- `claude_path` — optional; `null` means auto-discover

Resolve `sandbox_abs` = absolute sandbox directory. Prefer managed `-AddDir` and CWD against `sandbox_abs` / `workspace_root`, never against author-machine paths.

## Purpose

Use **direct** Codex ↔ Claude Code collaboration for ordinary bounded work. Escalate to the **managed runner** only when its controls and evidence are required.

## Core Rule

The planner agent owns planning, routing, scope control, and **final acceptance**. Invoking `$agent-workbench-runner` only requests classification; it does not by itself select `claude-delegate.ps1`.

Default direct work does not require a six-section task file or delegate artifacts. Keep command, result, usage, and final-verification facts in the closeout when they matter beyond the current exchange.

Use `{baseDir}/scripts/claude-delegate.ps1` only when at least one holds:

- The user explicitly requests a managed sandbox or a delegate run.
- The task needs root guidance validation, conflict blocking, or confirmed-experience projection.
- The completion claim requires native-web telemetry or inspectable run artifacts.
- Work must occur in a disposable clone/sandbox to protect the main worktree.

Do not run real delegate tasks against the user's main project worktree unless they explicitly allow it. Default target is `sandbox_abs`.

## Workflow

1. **Ensure workspace** — config lookup; else first-time-setup (blocking).
2. **Classify** after invoke:
   - Ordinary bounded implementation, reading, or review with no managed/audit need → collaborate directly; verify the diff or answer.
   - Any Core Rule trigger → continue managed path below.
3. Confirm managed work should use `sandbox_abs` (report if missing or dirty in a way that affects the task).
4. Set working directory to `sandbox_abs` when invoking managed scripts (or pass explicit paths).
5. Inspect rules before routing (prefer workspace copies if present, else skill package):
   - `{workspace_root}/AGENTS.md` or `{baseDir}/templates/workspace/AGENTS.md`
   - `{baseDir}/docs/workflow-learning-cases.md`
   - `{baseDir}/docs/claude-delegate-workflow.md`
   - `{baseDir}/docs/execution-boundary-matrix.md`
6. Use `{baseDir}/scripts/codex-route.ps1` only when `scan` / `plan` / `review` / `delegate` preview helps.
7. Before real delegation, ensure the task file has all six sections (template: `{baseDir}/docs/task-templates.md`; working file often `{workspace_root}/docs/task.md`):
   - `Goal`
   - `Allowed Scope`
   - `Forbidden Actions`
   - `Acceptance Criteria`
   - `Verification`
   - `Report Requirements`
8. Prefer `-DryRun` first when the task file, `AddDir`, permission profile, or run name changed.
9. After any run, the planner inspects artifacts and decides acceptance. Claude Code does not get final acceptance authority.

## Upstream contracts and reviewable reports

A stage contract from an upstream goal/dispatch protocol is delegate-ready only when it maps to the six sections above.

When a delegate result may hit an evidence gate or `$fake-pass`, ask the task report to expose:

- `claim` — exact claim to trust
- `evidence tier` — syntax / artifact / wrapper / report / behavior / recovery / …
- `trust boundary` — what the evidence proves and does **not** prove
- `missing evidence` — smallest gap that would change trust
- `conclusion consistency` — status matches failures, skips, and caveats

A complete delegate artifact is not final claim acceptance. Artifact health and claim trust are separate checks.

If Claude must run local validation commands, do not assume `PermissionProfile=default` is enough. Either leave validation for planner final verification, or choose a verified profile before the run (`permission_profile_default` in config is only a default).

## Commands

Replace `{baseDir}`, `{workspace_root}`, and `{sandbox_abs}` with resolved absolute paths. On Windows PowerShell:

Route preview:

```powershell
& "{baseDir}\scripts\codex-route.ps1" -TaskText "<task>"
```

Delegate dry run:

```powershell
& "{baseDir}\scripts\claude-delegate.ps1" `
  -TaskFile "{workspace_root}\docs\task.md" `
  -AddDir "{sandbox_abs}" `
  -Name <name> `
  -DryRun
```

Real delegate run:

```powershell
& "{baseDir}\scripts\claude-delegate.ps1" `
  -TaskFile "{workspace_root}\docs\task.md" `
  -AddDir "{sandbox_abs}" `
  -Name <name>
```

List recent runs (from the directory that owns `.delegate-runs`, usually workspace or sandbox — pass paths consistently with how you launched the run):

```powershell
& "{baseDir}\scripts\list-delegate-runs.ps1" -Latest 10
```

Optional: `-ClaudePath` from config when `claude_path` is set.

## Safety checks

- Keep run artifacts under the workspace/sandbox `.delegate-runs/` layout used by the scripts; do not scatter them into unrelated repos.
- Treat `PermissionProfile` names as execution settings only when `{baseDir}/docs/execution-boundary-matrix.md` says they are enforced.
- Treat `WorkflowLearningCase` as metadata and decision evidence; it does not change Claude arguments by itself.
- If a task would modify the main project worktree, stop and ask.
- If the sandbox is missing or dirty in a way that affects the task, report before running.
- Never require author-only paths such as `F:\agent-workbench` on other machines.

## Closeout

Report:

- Workspace root and sandbox path used
- Route or delegate command used (with `{baseDir}` scripts)
- Run artifact path, if any
- Verification result
- Whether the main project worktree remained untouched
