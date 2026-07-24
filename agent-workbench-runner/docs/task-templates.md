# Delegate Task Templates

Use this file as the shared source for delegated task shape in Phase 1.

Recommended workflow:

1. Copy the template that matches the task mode.
2. Save it as a working task file such as `docs/task.md`.
3. Fill in the placeholders before calling `scripts/claude-delegate.ps1`.

## Standard Sections

Every delegated task should keep these sections:

- `Goal`: the exact outcome Claude Code should achieve.
- `Allowed Scope`: files or directories Claude Code may edit.
- `Forbidden Actions`: explicit non-goals and safety limits.
- `Acceptance Criteria`: observable conditions for success.
- `Verification`: checks Claude Code should run or explain.
- `Report Requirements`: what the final execution report must include.

## Managed Sandbox Addition

When invoking `claude-delegate.ps1 -ManagedSandboxPath <sandbox-root>`, add exactly one `## Managed Constraints` JSON block to the six standard sections:

```json
{
  "schema_version": 1,
  "requested_paths": [],
  "requested_tools": [],
  "requested_acceptance_criteria": [],
  "required_permissions": [],
  "stricter_interpretations": []
}
```

Use only concrete strings. When a task has an ordinary ambiguity, add one `stricter_interpretations` object with its `source` (`CLAUDE.md` or `PROGRESS.md`) and chosen `interpretation`; otherwise leave the array empty. The runner blocks before Claude starts when a requested value is forbidden by root guidance, or when the task omits a guidance-required permission. The final report must also contain the manifest-bound `## Applied Constraints` table emitted in the delegated brief.

## Mode: `implement`

Use when the solution is already decided and the remaining work is direct execution.

```md
# Implement Task

## Goal

<Describe the exact change to make.>

## Allowed Scope

- <List the files or directories that may be edited.>

## Forbidden Actions

- Do not change files outside the allowed scope.
- Do not introduce new dependencies.
- Do not perform broad refactors unrelated to the goal.

## Acceptance Criteria

- <List the user-visible or code-visible outcomes that must be true.>

## Verification

- <List the commands, tests, or manual checks to run.>

## Report Requirements

- List every file changed.
- Summarize the implementation.
- Report each verification step and its result.
- Call out blockers or follow-up risks if anything could not be verified.
```

## Mode: `review`

Use when Claude Code should inspect an existing change for defects, regressions, or missing validation rather than implement a fix.

```md
# Review Task

## Goal

<Describe what change, diff, branch, or artifact should be reviewed.>

## Allowed Scope

- Read access across the relevant repository files.
- Edit nothing unless the task explicitly says notes may be written to a separate file.

## Forbidden Actions

- Do not implement fixes.
- Do not rewrite the reviewed change.
- Do not mark the work accepted on behalf of Codex.

## Acceptance Criteria

- Findings are prioritized by severity.
- Each finding points to concrete evidence.
- Missing tests or verification gaps are called out when relevant.

## Verification

- <List the files, diffs, test outputs, or artifacts to inspect.>

## Report Requirements

- Report findings first.
- Include file references for each concrete issue.
- State explicitly if no findings were discovered.
- Note any residual risk caused by missing context or unrun checks.
```

## Mode: `rescue`

Use when a delegated run is blocked, partially failed, or needs a narrowly scoped recovery step.

```md
# Rescue Task

## Goal

<Describe the blocker or failed state and the smallest acceptable recovery outcome.>

## Allowed Scope

- <List the files, logs, or artifacts that may be touched while recovering.>

## Forbidden Actions

- Do not expand the task into unrelated cleanup.
- Do not discard user changes to force progress.
- Do not hide unresolved blockers.

## Acceptance Criteria

- The blocker is removed or reduced to a clearly explained remaining issue.
- The repository is left in a stable, inspectable state.
- Any unfinished follow-up is stated explicitly.

## Verification

- <List the checks that prove the recovery worked or narrowed the failure.>

## Report Requirements

- Explain the original failure or blocker.
- Describe the recovery action taken.
- Report the verification result.
- If still blocked, state the next required human decision.
```

## Capability: `local_knowledge_query`

Use when Claude Code should query local wiki pages, second-source notes, or a local knowledge base before Codex makes a final decision. This capability uses `Level 2: Capability Owner` autonomy: Claude Code owns the query and synthesis inside the stated scope, while Codex keeps final acceptance authority.

```md
# Local Knowledge Query Task

## Goal

Answer <question> by querying local knowledge sources before Codex makes a final decision.

## Query Keywords

- <List the exact target keywords or phrases that define the intended topic.>

## Out-of-Scope Topics

- <List adjacent or similarly risky topics that must not be used as substitutes. If none, write `None.`>

## Allowed Scope

- Read local wiki pages, second-source notes, or explicitly provided knowledge-base paths.
- Self-check which local query capability is available.
- Prefer `/wiki query` when available; otherwise use an equivalent read-only local knowledge query path.

## Forbidden Actions

- Do not modify wiki pages, notes, source files, scripts, or route logs.
- Do not implement code changes.
- Do not call external web search unless the task explicitly allows it.
- Do not use `Out-of-Scope Topics` as substitute evidence for the target topic.
- Do not treat the result as final Codex acceptance.

## Acceptance Criteria

- The report includes `Status`, `Summary`, `Referenced Pages`, `Findings`, and `Gaps`.
- `Referenced Pages` lists concrete wiki page names or local file paths.
- Each finding is supported by at least one referenced page or file path.
- If the task is high-risk or drift-prone, the findings stay within `Query Keywords` and do not substitute `Out-of-Scope Topics`.
- If local knowledge covers only adjacent or out-of-scope topics, the report uses `Status: failed` with `Failure Code: NO_RELEVANT_KNOWLEDGE`.
- If the query fails, the report includes `Failure Code`.
- `Failure Code`, when present, is exactly one of `CAPABILITY_UNAVAILABLE`, `NO_RELEVANT_KNOWLEDGE`, or `QUERY_FAILED`.

## Verification

- Confirm the query entrypoint used, such as `/wiki query` or an equivalent local read-only query method.
- Confirm each finding is supported by at least one referenced page or file path.
- Confirm `Out-of-Scope Topics` are not used as the evidence basis for the final findings.
- Confirm no local knowledge files were modified.

## Report Requirements

- Start with `Status`: `success` or `failed`.
- Include `Summary`: 1-3 sentences.
- Include `Referenced Pages`: bullet list of page names or local file paths.
- Include `Findings`: bullet list of evidence-backed findings.
- Include `Gaps`: bullet list of missing, ambiguous, or unavailable knowledge.
- For high-risk local-only topics, include a gap note that authoritative external confirmation is still required.
- Include `Failure Code` only when `Status` is `failed`.
```
