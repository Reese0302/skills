# Execution Boundary Matrix

This matrix separates declared intent from machine-enforced behavior in the Codex-to-Claude delegate workflow.

## Task Contract

| Control | Enforced By | Current Boundary |
|---|---|---|
| `Goal` section | `scripts/claude-delegate.ps1`, `scripts/test-delegate-preflight.ps1` | Required for `-TaskFile`, `-TaskText`, and stdin task sources. |
| `Allowed Scope` section | `scripts/claude-delegate.ps1`, `scripts/test-delegate-preflight.ps1` | Required for all task sources; actual filesystem access is still controlled by `-AddDir` and Claude permissions. |
| `Forbidden Actions` section | `scripts/claude-delegate.ps1`, `scripts/test-delegate-preflight.ps1` | Required for all task sources; enforced as task instructions, not as filesystem sandbox rules. |
| `Acceptance Criteria` section | `scripts/claude-delegate.ps1`, `scripts/test-delegate-preflight.ps1` | Required for all task sources. |
| `Verification` section | `scripts/claude-delegate.ps1`, `scripts/test-delegate-preflight.ps1` | Required for all task sources. |
| `Report Requirements` section | `scripts/claude-delegate.ps1`, `scripts/test-delegate-preflight.ps1` | Required for all task sources; enforced as task instructions. |

## Permission And Evidence Controls

| Control | Enforced By | Current Boundary |
|---|---|---|
| `PermissionProfile=default` | `scripts/claude-delegate.ps1` | Passes `--permission-mode acceptEdits` with no extra `--allowedTools`. |
| `PermissionProfile=skill-mechanic-readonly` | `scripts/claude-delegate.ps1` | Adds `--allowedTools Bash,Glob`; caller must still choose suitable `-AddDir` paths. |
| `PermissionProfile=claude-html-write-one-file` | Metadata only | Records a one-file HTML intent but does not enforce file-level write limits. |
| `PermissionProfile=reflect-readonly-scout` | `scripts/claude-delegate.ps1` | Adds `--allowedTools Read,Bash,Glob`; does not authorize a real `/reflect` run. |
| Future web-research profile | Not promoted | A future profile may allow `WebSearch` or `WebFetch`, but tool allowance would not prove successful web use; acceptance must inspect `claude-output.json.usage.server_tool_use` counters. |
| `WorkflowLearningCase` | Metadata and preflight existence check | Records selected cases and lets preflight reject unknown ids; it does not change Claude arguments. |
| `AddDir` | `scripts/claude-delegate.ps1` | Resolves existing directories and passes each one to Claude as `--add-dir`. |
| Claude CLI discovery | `scripts/claude-cli-discovery.ps1` | Uses explicit `-ClaudePath`, `CLAUDE_CLI_PATH`, newest Claude Code extension native binary, then PATH lookup; metadata records `claudePathSource`. |
| `.delegate-runs` artifacts | `scripts/claude-delegate.ps1` and inspectors | Records brief, command, metadata, stdout/stderr, and result evidence for review. |

## Routing Controls

| Control | Enforced By | Current Boundary |
|---|---|---|
| `delegate` route | `scripts/codex-route.ps1` | Routes deterministic execution prompts to `claude-delegate.ps1`; auto-adds repo root when no `-AddDir` is supplied. |
| `review` route | `scripts/codex-route.ps1` | Routes review and validation prompts to high-reasoning Codex. |
| `plan` override for non-review prompts | `scripts/codex-route.ps1` | Prompts that explicitly say they are not reviewing an existing diff route to `plan`, matching `routing/research-plan-vs-review`. |
| Route decision log | `scripts/codex-route.ps1` | Appends route decisions and execution exit codes to `.delegate-runs/route-decisions.jsonl`. |
