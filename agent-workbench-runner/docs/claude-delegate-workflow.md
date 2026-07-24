# Claude Delegate Workflow

`scripts/claude-delegate.ps1` is the optional high-risk handoff wrapper from Codex to Claude Code CLI.

## Goals

- Keep Codex as planner, supervisor, and final verifier.
- Keep Claude Code scoped to controlled execution.
- Preserve small, inspectable run artifacts in `.delegate-runs/`.

## When To Use The Runner

Direct Codex-to-Claude Code collaboration is the default for ordinary bounded implementation, reading, and review. It does not require a six-section task file or delegate run; Codex keeps the command, result, usage, and final-verification facts needed for the claim in its closeout.

Invoking `$agent-workbench-runner` starts workbench classification; it does not by itself select this runner. Use this runner only when the user explicitly asks for a managed sandbox or delegate run, or the task requires one of these controls:

- Managed local-guidance validation, conflict blocking, or confirmed-experience projection.
- Native-web telemetry as a completion condition.
- A disposable execution workspace that protects the main worktree.
- Inspectable delegate artifacts for an audit, handoff, or later claim review.

Do not use the runner merely to improve ordinary Claude Code output quality. The runner adds a six-section task contract, a dry-run expectation, and `.delegate-runs/` artifacts; those costs are justified only when the extra controls are required.

## Runtime Baseline

- Default interactive shell: PowerShell 7 (`pwsh`).
- Compatibility target: scripts should remain compatible with both PowerShell 7 and Windows PowerShell 5.1.
- Fallback meaning: PowerShell 5.1 is a supported fallback environment, not an automatic in-script downgrade mechanism.
- Validation note: when stdin redirection behavior matters, prefer validating with `pwsh -File`.

## Claude CLI Discovery

`claude-delegate.ps1`, `test-delegate-preflight.ps1`, and controlled rescue preflight no longer default to a hard-coded VS Code extension version. When `-ClaudePath` is omitted, they resolve Claude CLI in this order:

1. Explicit `-ClaudePath` parameter.
2. `CLAUDE_CLI_PATH` environment variable.
3. Newest installed `anthropic.claude-code-*` native binary under common editor extension roots.
4. `claude.exe`, `claude.cmd`, or `claude.bat` on `PATH`.

Dry runs, real runs, command metadata, and preflight reports record both `claudePath` and `claudePathSource` so reviewers can see whether the executable came from a parameter, environment variable, extension discovery, or `PATH`.

## Task Modes

Phase 1 uses three explicit delegated task modes:

- `implement`: apply a decided change with narrow execution scope.
- `review`: inspect an existing change for defects, regressions, or missing validation.
- `rescue`: recover from a blocked, partial, or failed delegated run.

Shared task-file shape lives in [task-templates.md](./task-templates.md).
Before running the delegate script, copy the matching template into a working file such as `docs/task.md` and fill in the shared task sections. The delegate script and preflight gate require the same six headings for `-TaskFile`, `-TaskText`, and stdin task sources:

- `Goal`
- `Allowed Scope`
- `Forbidden Actions`
- `Acceptance Criteria`
- `Verification`
- `Report Requirements`

For a compact map of what is enforced by scripts versus only recorded as metadata or task intent, see [execution-boundary-matrix.md](./execution-boundary-matrix.md).

## Managed Sandbox Guidance

Use `-ManagedSandboxPath <sandbox-root>` only for a sandbox initialized by the `workflow-governance` managed-sandbox bootstrap. The runner reads root `CLAUDE.md` and `PROGRESS.md` as strict UTF-8 inputs before resolving or invoking Claude. Both files must be non-empty, contain `## Guidance`, and contain one `## Managed Constraints` JSON block with `schema_version: 1`.

The task remains a six-section contract and adds the task-side constraints block from [task-templates.md](./task-templates.md). The runner compares its `requested_*` values with guidance `forbidden_*` values, confirms required permissions, and blocks conflicts before invocation. `PROGRESS.md` can add prohibitions but cannot require permissions. A task records an ordinary ambiguity under `stricter_interpretations`; otherwise it declares an empty array.

Managed `brief.md` includes `## Local Guidance` with a versioned manifest for both files. A managed result becomes an accepted candidate only when `## Applied Constraints` has one row each for `CLAUDE.md` and `PROGRESS.md`, each with the manifest SHA-256, the exact guidance `report_rule`, a concrete application, and the matching task-declared stricter interpretation (or `None identified`). This remains a candidate for Codex final acceptance, not final acceptance itself.

## Usage

Route-first usage:

```powershell
.\scripts\codex-route.ps1 -TaskText "请先读几个文件并总结当前的 delegate 流程。"
.\scripts\codex-route.ps1 -TaskText "方案已确定，请按既定方案执行 README 改动。"
.\scripts\codex-route.ps1 -TaskText "Please read a few files and summarize the current delegate flow."
.\scripts\codex-route.ps1 -TaskText "The plan is fixed; apply the decided README change."
```

Use `codex-route.ps1` when a managed task needs a preview of `scan`, `plan`, `review`, or `delegate`. Use `claude-delegate.ps1` only after the task is explicitly delegated and meets the runner conditions above.
Route decisions are appended to `.delegate-runs/route-decisions.jsonl`; real runs also record `executionExitCode` in that JSONL log.

## Workflow Learning Cases

Before routing or delegating a task, check [workflow-learning-cases.md](./workflow-learning-cases.md) for a matching case.

Use a matching case to choose the route mode, permission profile, task template, timeout budget, or verification requirement. When a case is used, mention the case id in the task brief or final report so the decision is traceable.

If no case matches, keep the smallest default strategy. If the run fails in a reusable way, add or update a case after collecting evidence from `command.json`, `stdout.json`, `result.md`, `metadata.json`, route logs, or interactive transcript files.

Cases are guidance, not automation. A case should be reused in 2-3 real tasks before it is promoted into a script parameter, template default, hook, skill, or plugin behavior.

## Permission Profiles

`claude-delegate.ps1` supports explicit permission profiles. Profiles are selected by Codex or the caller; the script does not auto-detect the right profile from task text.

```powershell
.\scripts\claude-delegate.ps1 `
  -TaskFile .\docs\task.md `
  -AddDir {workspace_root} `
  -Name example `
  -PermissionProfile skill-mechanic-readonly `
  -WorkflowLearningCase permission/skill-mechanic-readonly `
  -DryRun
```

Available profiles:

- `default`: preserves the original behavior, using `--permission-mode acceptEdits` with no extra allowed tools.
- `skill-mechanic-readonly`: adds `--allowedTools Bash,Glob` for read-only mechanical skill checks that need shell/glob access.
- `claude-html-write-one-file`: records a one-file HTML writing intent while keeping the same permissions as `default`; it does not enforce file-level write limits.
- `reflect-readonly-scout`: adds `--allowedTools Read,Bash,Glob` for read-only scouting before any real `/reflect` run.

A permission profile proves only the requested Claude tools and directories were passed to the CLI. It does not prove the tool actually succeeded. For any delegated task that claims native web research, Codex must inspect `claude-output.json.usage.server_tool_use.web_search_requests` and `web_fetch_requests` before calling the task web-researched. If both counters are `0`, treat the result as blocked, local-only, or fallback evidence according to the task contract; do not describe it as successful native web research.

`deep-research-web` remains sandbox-experimental until a real run shows non-zero native web telemetry and the fallback rules are stable. Do not add it to the main workbench profile list or task templates merely because a sandbox task used that name.

`-WorkflowLearningCase` accepts one or more case ids and writes them to run metadata only. It does not change the Claude CLI arguments, permission mode, allowed directories, or task behavior.

`reflect-real-run` is intentionally not automated. A real `/reflect` run still needs a separate confirmation because it may read `~\.claude\projects` and write to `~\.claude\experiences`.

Create and check a human approval token for bounded actions:

```powershell
.\scripts\new-human-approval-token.ps1 `
  -Action delegate-run `
  -Scope {workspace_root} `
  -Reason "Run approved delegate task" `
  -ApprovedBy "<name>" `
  -ApprovalPhrase "I approve this bounded action" `
  -OutputPath .\docs\human-approval-token-latest.json

.\scripts\test-human-approval-token.ps1 `
  -TokenPath .\docs\human-approval-token-latest.json `
  -ExpectedAction delegate-run `
  -ExpectedScope {workspace_root}
```

Human approval tokens are explicit evidence for a later bounded action. The token check validates schema, action, scope, expiry, required approval phrase, and safety boundaries. These scripts do not call Claude, create delegate runs, modify evidence artifacts, modify workflow cases, rerun work, rescue work, select `PermissionProfile`, infer `AddDir`, change delegate parameters, or execute the approved action.

Run delegate preflight before a delegate call:

```powershell
.\scripts\test-delegate-preflight.ps1 `
  -TaskFile .\docs\task.md `
  -AddDir {workspace_root} `
  -TaskMode implement `
  -PermissionProfile default
```

`test-delegate-preflight.ps1` checks delegate inputs before `claude-delegate.ps1` is allowed to run. It validates the task source, required task sections, `TaskMode`, explicit `AddDir` paths, `ClaudePath`, `PermissionProfile`, and any supplied `WorkflowLearningCase` ids. It writes Markdown and JSON reports with `status` set to `pass`, `warning`, or `fail`; `fail` exits with code 1 after writing the reports.

The preflight does not call Claude, create a delegate run, modify evidence artifacts, modify workflow cases, rerun work, rescue work, select `PermissionProfile`, infer `AddDir`, or change delegate parameters. A warning is not final approval; Codex still decides whether the delegate call is acceptable.

Task file mode:

```powershell
.\scripts\claude-delegate.ps1 -TaskFile .\docs\task.md -AddDir {workspace_root} -Name example
```

For every task source, the script validates these required headings before Claude is invoked:

- `Goal`
- `Allowed Scope`
- `Forbidden Actions`
- `Acceptance Criteria`
- `Verification`
- `Report Requirements`

Recommended task-file sources:

- `docs/task-templates.md` for the shared `implement`, `review`, and `rescue` templates
- `docs/task.md` as a disposable working copy for the current delegated task

Inline text mode for PowerShell:

```powershell
$task = Get-Content .\docs\task.md -Raw
.\scripts\claude-delegate.ps1 -TaskText $task -AddDir {workspace_root} -Name example
```

stdin mode for redirected callers:

```powershell
Get-Content .\docs\task.md -Raw | pwsh -File .\scripts\claude-delegate.ps1 -AddDir {workspace_root} -Name example
```

dry-run mode:

```powershell
.\scripts\claude-delegate.ps1 -TaskFile .\docs\task.md -AddDir {workspace_root} -Name example -DryRun
```

Outer timeout guidance:

- Run `-DryRun` first when the task file, `AddDir`, or run name just changed.
- Keep outer wrappers short only for small read-only tasks.
- Give document/spec execution tasks a wider outer timeout than lightweight summaries.

Recommended outer timeout budgets:

- `10-30s`: `-DryRun`
- `2-3m`: small read-only summary, validation, or narrow review
- `5-10m`: documentation edits, spec execution, or other multi-step but bounded tasks
- `10m+`: implementation or test-heavy delegated runs

If an outer wrapper times out, inspect the run directory before retrying:

- If only `brief.md` and `command.json` exist, the wrapper was interrupted before Claude returned.
- If `claude-output.json`, `result.md`, and `metadata.json` exist, treat the run as complete and review the result before rerunning.
- Do not assume a timeout means "no work happened"; check the target diff and `.delegate-runs/<run>/` contents first.

The current batch delegate harness is synchronous: Codex or the calling shell starts `claude.exe`, waits for it to return, then records artifacts. Do not present this path as reliable detached execution after Codex or the terminal is closed. If a task requires unattended continuation after the caller exits, design a separate detached executor or background supervisor before promising that behavior.

Phase 2 metadata fields:

```powershell
.\scripts\claude-delegate.ps1 `
  -TaskFile .\docs\task.md `
  -AddDir {workspace_root} `
  -Name example `
  -TaskMode implement `
  -WorkflowId workflow-docs-example `
  -TaskId readme-task-modes `
  -Role implementer
```

Safe defaults:

- `TaskMode`: `implement`
- `Role`: `implementer`
- `WorkflowId`: generated from timestamp and run name when omitted
- `TaskId`: defaults to the safe run name when omitted

List recent delegate runs:

```powershell
.\scripts\list-delegate-runs.ps1 -Latest 10
```

Inspect one delegate run:

```powershell
.\scripts\inspect-delegate-run.ps1 -RunDir .\.delegate-runs\20260706-150042-v12-ordinary-smoke-review
```

`inspect-delegate-run.ps1` is a read-only evidence inspector for a single batch run directory. It summarizes run identity, task metadata, permission profile evidence, required artifact completeness, exit code, Claude API error status, permission denials, stderr content, and a short result or error summary.

The inspector classification is only an acceptance hint. It may return `accepted-candidate`, `dry-run`, `blocked-429`, `permission-denial`, `incomplete-artifacts`, `failed-exit`, or `needs-review`; Codex still performs the final acceptance check on diff, tests, and artifacts.

Recommended use:

- after an outer timeout, before deciding whether to rerun
- after a 429, to confirm the API error and any permission denial evidence
- after permission denial, to list denied tools
- before or after release smoke checks, to separate dry runs from real runs

The inspector does not call Claude, modify run artifacts, select permission profiles, infer `AddDir`, rescue a run, or start workflow orchestration.

## Interactive Transcript Naming

When a delegated task uses the interactive Claude Code CLI path instead of `claude-delegate.ps1`, store transcript evidence in `tmp/` with one shared base name:

- `tmp/<task-slug>-result.md`
- `tmp/<task-slug>-stdout.json`
- `tmp/<task-slug>-stderr.txt`

Rules:

- `<task-slug>` must be the same across all three files for one run.
- `result.md` stores the human-readable summary or transcript digest.
- `stdout.json` stores the captured raw stdout artifact when available.
- `stderr.txt` stores captured stderr text when available.
- If one artifact is unavailable, the report must state which file is missing and why; do not rename the remaining files to a different base name.

Inspect one interactive transcript triplet:

```powershell
.\scripts\inspect-interactive-transcript.ps1 -Slug interactive-profile-transcript-review -TmpDir {tmp_dir}
```

`inspect-interactive-transcript.ps1` is a read-only validator for the interactive transcript triplet. It checks `<slug>-result.md`, `<slug>-stdout.json`, and `<slug>-stderr.txt`, then summarizes transcript completeness, Claude result subtype, error status, API error status, permission denials, stderr content, and a short result summary.

The validator classification is only an acceptance hint. It may return `success`, `missing-transcript`, `api-error`, `permission-denial`, `stderr-warning`, `failed`, or `needs-review`; Codex still performs the final acceptance check on task results and transcript evidence.

This validator does not replace `inspect-delegate-run.ps1` for batch `.delegate-runs\` artifacts. It does not call Claude, modify transcript files, create missing artifacts, select permission profiles, infer `AddDir`, rerun a task, or start workflow orchestration.

List recent evidence status across batch and interactive runs:

```powershell
.\scripts\list-evidence-status.ps1 -LatestBatch 10 -LatestInteractive 10
```

`list-evidence-status.ps1` is a read-only evidence index. It calls the batch run inspector and interactive transcript validator, then returns one row per recent evidence item with `Kind`, `Id`, `Classification`, `Signal`, completeness, path, and timestamp.

The evidence index is only a summary view. It does not replace the single-run inspectors, call Claude, modify artifacts, create tasks, rescue runs, rerun work, select permission profiles, infer `AddDir`, or start workflow orchestration. Codex still performs the final acceptance check from the underlying evidence.

Check recent evidence health:

```powershell
.\scripts\test-evidence-health.ps1 -LatestBatch 10 -LatestInteractive 10
```

`test-evidence-health.ps1` is a read-only health gate over the evidence index. It summarizes recent evidence into `pass`, `warning`, or `fail`, with problem and warning lists. It does not replace the index or single-item inspectors, and it does not call Claude, modify artifacts, rerun work, rescue runs, select permission profiles, infer `AddDir`, or start workflow orchestration. Codex keeps final acceptance authority.

Generate a human-readable evidence triage report:

```powershell
.\scripts\new-evidence-triage-report.ps1 -LatestBatch 10 -LatestInteractive 10
```

`new-evidence-triage-report.ps1` writes a Markdown report from the health gate and evidence index. The report summarizes problems, warnings, healthy evidence, suggested next steps, and boundaries. It does not replace the health gate, evidence index, or single-item inspectors, and it does not call Claude, modify artifacts, rerun work, rescue runs, select permission profiles, infer `AddDir`, or start workflow orchestration. Codex keeps final acceptance authority.

Generate a rescue task draft from failed or blocked evidence:

```powershell
.\scripts\new-rescue-task-draft.ps1 -RunDir .\.delegate-runs\20260706-150042-v12-ordinary-smoke-review
.\scripts\new-rescue-task-draft.ps1 -Slug interactive-profile-transcript-review -TmpDir {tmp_dir}
```

`new-rescue-task-draft.ps1` calls the matching read-only inspector and writes a standard rescue task draft to `docs\task-rescue-<safe-id>-<yyyyMMdd-HHmmss>.md` unless `-OutputPath` is supplied. The draft keeps the six standard sections: `Goal`, `Allowed Scope`, `Forbidden Actions`, `Acceptance Criteria`, `Verification`, and `Report Requirements`.

The rescue draft generator does not call Claude, modify evidence artifacts, rerun work, perform rescue actions, select permission profiles, infer `AddDir`, or increase permissions. For `blocked-429` / `api-error`, it states that permission upgrades are not the fix. For `permission-denial`, it requires checking denied tools and workflow learning cases before any permission decision. For `missing-transcript` / `incomplete-artifacts`, it requires confirming the evidence gap before considering a rerun.

Generate a profile recommendation report:

```powershell
.\scripts\new-profile-recommendation-report.ps1 -LatestBatch 10 -LatestInteractive 10
```

`new-profile-recommendation-report.ps1` reads recent evidence through `list-evidence-status.ps1`, reads `docs\workflow-learning-cases.md`, and writes a Markdown report to `docs\profile-recommendation-report-<yyyyMMdd-HHmmss>.md` unless `-OutputPath` is supplied. The report is a human decision aid for candidate profiles only: `default`, `skill-mechanic-readonly`, `claude-html-write-one-file`, and `reflect-readonly-scout`.

The recommendation report does not call Claude, modify evidence artifacts, modify workflow learning cases, select `PermissionProfile`, infer `AddDir`, or automatically upgrade permissions. It only explains evidence sources, matching workflow signals, candidate profile risks, and whether the evidence is insufficient for a specialized recommendation.

Generate an evidence decision gate report:

```powershell
.\scripts\new-evidence-decision-gate.ps1 -LatestBatch 10 -LatestInteractive 10
.\scripts\new-evidence-decision-gate.ps1 -LatestBatch 10 -LatestInteractive 10 -JsonOutputPath .\docs\evidence-decision-gate-latest.json
```

`new-evidence-decision-gate.ps1` reads recent evidence through `list-evidence-status.ps1`, reads `docs\workflow-learning-cases.md`, and writes a Markdown report to `docs\evidence-decision-gate-<yyyyMMdd-HHmmss>.md` unless `-OutputPath` is supplied. It also writes a machine-readable JSON contract to `docs\evidence-decision-gate-<yyyyMMdd-HHmmss>.json` unless `-JsonOutputPath` is supplied. It returns one of the fixed decisions: `accept-candidate`, `repair-evidence`, `wait-api-quota`, `inspect-permission`, `needs-rescue-draft`, or `manual-review`.

The decision gate JSON contract uses `schemaVersion: 2.1` and includes `decision`, `confidence`, `summary`, `inputs`, `primaryEvidence`, `evidenceCount`, `matchedWorkflowCases`, `recommendedAction`, `recommendedNextCommand`, and `boundaries`. `recommendedAction` is one of `inspect-delegate-run`, `inspect-interactive-transcript`, `profile-recommendation-report`, `rescue-task-draft`, `codex-final-acceptance`, `manual-review`, or `wait-api-quota`.

Each decision gate run appends a JSONL entry to `.delegate-runs\decision-ledger.jsonl` unless `-LedgerPath` is supplied with another path or an empty value. Ledger entries use `ledgerSchemaVersion: 2.4` and record the decision, confidence, recommended action, primary evidence, matched workflow cases, output paths, and safety boundaries.

The decision gate is a human decision aid. It does not call Claude, modify evidence artifacts, modify workflow learning cases, rerun work, rescue work, generate rescue drafts, select `PermissionProfile`, infer `AddDir`, or change delegate parameters. Codex still keeps final acceptance authority over diffs, tests, and artifacts.

Run one allowed command from a decision gate JSON contract:

```powershell
.\scripts\invoke-evidence-decision-command.ps1 -DecisionJsonPath .\docs\evidence-decision-gate-latest.json
```

`invoke-evidence-decision-command.ps1` consumes only the v2.1 JSON contract and writes an assisted command report to `docs\evidence-decision-command-<yyyyMMdd-HHmmss>.md` unless `-OutputPath` is supplied. It does not parse the Markdown report and does not recompute the decision.

The runner reads `configs\evidence-automation-policy.json` unless `-PolicyPath` is supplied. The v2.5 policy is deny-by-default and allows only `inspect-delegate-run`, `inspect-interactive-transcript`, and `profile-recommendation-report`. It denies `rescue-task-draft`, `codex-final-acceptance`, `manual-review`, and `wait-api-quota`.

Run one assisted decision loop:

```powershell
.\scripts\invoke-evidence-decision-loop.ps1 -LatestBatch 10 -LatestInteractive 10
```

`invoke-evidence-decision-loop.ps1` runs the v2.1 decision gate, passes the generated JSON to `invoke-evidence-decision-command.ps1`, runs the v2.1 decision gate again, and writes a before/after loop report to `docs\evidence-decision-loop-<yyyyMMdd-HHmmss>.md` unless `-OutputPath` is supplied.

The loop also appends its before/command/after summary to `.delegate-runs\decision-ledger.jsonl` unless `-LedgerPath` is supplied with another path or an empty value. The two internal decision gate calls append their own gate entries to the same ledger path, so a normal loop records before gate, after gate, and loop summary events.

The loop passes `-PolicyPath` through to the assisted command runner. It does not call Claude, rerun delegated work, rescue work, select `PermissionProfile`, infer `AddDir`, or add new execution authority beyond the policy-gated runner. It is a one-cycle read-only/report-only automation loop for making the current evidence state clearer.

Run policy-gated safe auto-run:

```powershell
.\scripts\invoke-evidence-safe-auto-run.ps1 -MaxSteps 3
```

`invoke-evidence-safe-auto-run.ps1` repeatedly runs a preflight decision gate, checks that the recommended action is one of the low-risk actions allowed by policy (`inspect-delegate-run`, `inspect-interactive-transcript`, or `profile-recommendation-report`), executes that fixed decision JSON through `invoke-evidence-decision-command.ps1`, then runs the decision gate again to compare before/after state. It stops on policy denial, no execution, no before/after change, a non-auto action, or `-MaxSteps`.

Safe auto-run does not call Claude, rerun delegated work, rescue work, generate rescue drafts, select `PermissionProfile`, infer `AddDir`, or execute commands outside the policy-gated assisted command runner.

Generate one rescue draft from a decision gate JSON contract:

```powershell
.\scripts\invoke-evidence-rescue-draft-command.ps1 `
  -DecisionJsonPath .\docs\evidence-decision-gate-latest.json `
  -AllowRescueDraftWrite
```

`invoke-evidence-rescue-draft-command.ps1` consumes only the v2.1 decision JSON contract. It does not parse Markdown and does not recompute the decision. It writes a rescue task draft only when `recommendedAction` is `rescue-task-draft` and `-AllowRescueDraftWrite` is supplied. The generated draft still comes from `new-rescue-task-draft.ps1` and keeps the standard rescue task sections.

This assisted rescue draft mode does not call Claude, rerun delegated work, execute rescue work, modify evidence artifacts, select `PermissionProfile`, infer `AddDir`, or change delegate parameters. It intentionally does not run inside safe auto-run.

Prepare a controlled rescue package from a decision gate JSON and human approval token:

```powershell
$decision = ".\docs\evidence-decision-gate-latest.json"

.\scripts\new-human-approval-token.ps1 `
  -Action controlled-rescue-orchestrator `
  -Scope (Resolve-Path $decision).Path `
  -ApprovedBy "<name>" `
  -ApprovalPhrase "I approve this bounded action" `
  -OutputPath .\docs\controlled-rescue-approval-token.json

.\scripts\invoke-controlled-rescue-orchestrator.ps1 `
  -DecisionJsonPath $decision `
  -ApprovalTokenPath .\docs\controlled-rescue-approval-token.json `
  -AddDir {workspace_root} `
  -WorkflowLearningCase timeout/check-before-rerun
```

`invoke-controlled-rescue-orchestrator.ps1` consumes an existing v2.1 decision JSON where `decision=needs-rescue-draft` and `recommendedAction=rescue-task-draft`. It confirms the v2.5 policy remains deny-by-default for automatic rescue draft execution, validates the v2.9 human approval token against the decision JSON path, generates one rescue task draft through the v2.7 assisted rescue draft command, then runs the v2.8 delegate preflight on the generated draft. Preflight must return `pass`; `warning` is not accepted as a controlled rescue gate pass.

The controlled rescue orchestrator does not call Claude, create delegate runs, rerun delegated work, execute rescue work, modify evidence artifacts, modify workflow cases, select `PermissionProfile`, infer `AddDir`, or change delegate parameters. It may write one rescue task draft only after the decision, policy, and approval token gates pass. With `-DryRun`, it validates decision, policy, and approval token gates but writes no rescue draft and runs no delegate preflight. Codex still keeps final acceptance authority before any actual delegated rescue execution.

## Verification Checklist

- `brief.md` is written from task text.
- `command.json` records the exact Claude invocation.
- Dry runs write `metadata.json` with `dryRun: true` and `invokedClaude: false`.
- Task source is recorded as a file path, `parameter`, or `stdin`.
- `codex-route.ps1` appends route decisions to `.delegate-runs/route-decisions.jsonl`, and real runs include `executionExitCode`.
- Phase 2 metadata records `taskMode`, `workflowId`, `taskId`, and `role`.
- Permission profile metadata records `permissionProfile`, `workflowLearningCases`, `permissionMode`, and `allowedTools`.
- Task files fail fast before Claude invocation when required sections are missing.
- Real runs write `claude-output.json`, `result.md`, and `claude-stderr.txt`.
- Recent runs can be listed with `scripts/list-delegate-runs.ps1`.
- Single-run evidence can be inspected with `scripts/inspect-delegate-run.ps1 -RunDir <run-dir>`.
- Interactive transcript triplets can be inspected with `scripts/inspect-interactive-transcript.ps1 -Slug <task-slug>`.
- Recent batch and interactive evidence can be indexed with `scripts/list-evidence-status.ps1`.
- Recent evidence health can be checked with `scripts/test-evidence-health.ps1`.
- Evidence triage reports can be generated with `scripts/new-evidence-triage-report.ps1`.
- Rescue task drafts can be generated with `scripts/new-rescue-task-draft.ps1`.
- Profile recommendation reports can be generated with `scripts/new-profile-recommendation-report.ps1`.
- Evidence decision gate reports can be generated with `scripts/new-evidence-decision-gate.ps1`.
- One allowed decision command can be run with `scripts/invoke-evidence-decision-command.ps1`.
- One assisted decision loop can be run with `scripts/invoke-evidence-decision-loop.ps1`.
- Policy-gated safe auto-run can be run with `scripts/invoke-evidence-safe-auto-run.ps1`.
- One explicit assisted rescue draft can be generated with `scripts/invoke-evidence-rescue-draft-command.ps1`.
- Delegate inputs can be checked with `scripts/test-delegate-preflight.ps1`.
- Human approval tokens can be generated and checked with `scripts/new-human-approval-token.ps1` and `scripts/test-human-approval-token.ps1`.
- Controlled rescue packages can be prepared with `scripts/invoke-controlled-rescue-orchestrator.ps1`.
- Codex performs the final acceptance check on diff, tests, and artifacts.
