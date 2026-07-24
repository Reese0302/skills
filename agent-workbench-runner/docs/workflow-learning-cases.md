# Workflow Learning Cases

本文件记录 `agent-workbench` 的工作流失败案例。它不是全局知识库，而是给 Codex 委派前使用的经验账本：遇到相似任务时，先查这里，再选择 route、权限档、任务模板、timeout 或验证方式。

## 使用规则

- 案例类型只限：`permission`、`routing`、`task-template`、`verification`、`timeout`、`artifact`。
- 新案例必须包含：问题类型、触发场景、失败证据、根因、最小修复、下次规则、适用边界、证据路径。
- 委派前如果命中案例，Codex 应采用对应规则，并在任务说明或报告中写明使用了哪个案例。
- 未命中案例时，保持最小默认策略；失败后再补案例。
- 案例只有在 2-3 次真实任务中稳定有效后，才考虑升级为脚本参数、模板默认项、hook、skill 或 plugin。
- 个案不得直接升级成全局默认。

## 案例模板

```md
### `<type>/<case-id>`

- 问题类型：`permission | routing | task-template | verification | timeout | artifact`
- 触发场景：<什么时候会遇到这个问题>
- 失败证据：<可复核的错误、输出或现象>
- 根因：<为什么失败>
- 最小修复：<已验证的最小修复>
- 下次规则：<Codex 下次遇到同类任务应该怎么做>
- 适用边界：<这个规则能用到哪里，不能用到哪里>
- 证据路径：<报告、stdout、command、run artifact 等路径>
- 稳定度：`seed | reused-1 | reused-2 | promoted`
```

## Seed Cases

### `permission/skill-mechanic-readonly`

- 问题类型：`permission`
- 触发场景：Claude Code 运行 `skill-mechanic` 时，需要执行只读 Node 机械层脚本，例如 `skill-md-lint`、`j-mechanical`、`leitwort-gate`。
- 失败证据：默认 interactive 运行和 `--permission-mode acceptEdits` 都会阻挡 `Bash`；先前运行中 `Glob` / `Bash` 出现在 `permission_denials`。
- 根因：Claude Code 理解了任务，但没有获得运行 `Glob` / `Bash` 的工具权限。
- 最小修复：使用 `--permission-mode acceptEdits --allowedTools Bash,Glob`，并按任务需要传入 `--add-dir {workspace_root}` 与 `--add-dir {user_agents_dir}`。
- 下次规则：遇到只读 `skill-mechanic` 机械检查任务时，优先使用 `skill-mechanic-readonly` 权限档；如果需要 Claude Code 直接读取明确 skill 路径，可额外加入 `Read`；不要直接升级到 `bypassPermissions`。
- 适用边界：仅适用于只读机械检查。若任务需要编辑 skill、写日志、联网或调用其他工具，必须另开案例或重新验证。
- 证据路径：`tmp\claude-permission-matrix-20260706\report.md`、`tmp\skill-mechanic-explain-skill-stdout.json`、`tmp\skill-mechanic-explain-skill-result.md`、`tmp\workflow-learning-v11-task1-wiki-skill-mechanic-report.md`、`tmp\workflow-learning-v11-task1-wiki-skill-mechanic-rerun-stdout.json`
- 稳定度：`reused-1`

### `verification/claude-token-plan-limit`

- 问题类型：`verification`
- 触发场景：需要 Claude Code 执行委派、skill 检查或 LLM 判断层，但 CLI 返回 `429 token plan limit exhausted`。
- 失败证据：`stdout.json` 中 `api_error_status=429`，`result` 为 `API Error: Request rejected (429) · token plan limit exhausted`，且 `permission_denials=[]`。
- 根因：Claude Code 运行被账户/计划额度限制阻塞，不是工具权限、路径权限或目标 skill 本身失败。
- 最小修复：保存 transcript 三件套；把本次运行标记为 `partial`；如果任务存在确定性子步骤，可先运行只读本地脚本补充证据；确认是否可切换 Claude Code 模型或执行通道；不要立刻用更大权限重试。
- 下次规则：遇到 429 时，Codex 应先区分“模型/额度阻塞”和“权限拒绝”；如果用户已切换到可用模型，可用同一权限档重跑；只有在额度恢复、换可用执行通道或用户明确要求时，才重跑 Claude Code。
- 适用边界：适用于 Claude Code CLI 返回明确 429 的场景。不适用于脚本 exit 非 0、timeout、permission denial 或目标文件错误。
- 证据路径：`tmp\workflow-learning-v11-task1-wiki-skill-mechanic-stdout.json`、`tmp\workflow-learning-v11-task1-wiki-skill-mechanic-result.md`、`tmp\workflow-learning-v11-task1-wiki-skill-mechanic-rerun-stdout.json`、`tmp\workflow-learning-v11-task1-wiki-skill-mechanic-report.md`
- 稳定度：`seed`

### `routing/research-plan-vs-review`

- 问题类型：`routing`
- 触发场景：用户要求做调研、比较、归纳框架或设计方案，但 prompt 中出现“review / 审查 / 比较”等词。
- 失败证据：既有调研记录显示，含“比较/审查”措辞的 prompt 可能被 `codex-route.ps1` 判到 `review`，而实际目标更接近 `plan`。
- 根因：route 启发式会受措辞影响；`review` 词面信号可能盖过“产出方案”的意图。
- 最小修复：调研归纳类任务显式使用 `-Mode plan`，或在任务文本中明确“目标是形成方案，不是 review 已有 diff”。
- 下次规则：遇到调研、比较、归纳、架构设计类请求时，Codex 先判断是否应显式指定 `plan`，不要完全依赖 auto route。
- 适用边界：适用于还没有目标 diff 或待审查实现的任务。若用户明确要求 review 现有改动，仍使用 `review`。
- 证据路径：`docs\auto-hook-plugin-starter-best-practices-research-20260705.md`、`.delegate-runs\route-decisions.jsonl`、`docs\goal-autonomous-codex-workflow-research-20260706.md`
- 稳定度：`reused-1`

### `verification/goal-stage-exit-evidence`

- 问题类型：`verification`
- 触发场景：使用 Codex goal 跑多阶段任务时，阶段推进容易只留下过程叙述，而没有明确的退出证据。
- 失败证据：Task 2 在生成 Markdown 后，用户纠正 HTML 阶段应交给 Claude Code 执行，而不是由 Codex 直接用转换 skill 完成。
- 根因：goal 能推动下一步，但如果阶段目标没有写清“由谁执行”和“退出证据是什么”，Codex 可能选择较近的本地能力，偏离验证意图。
- 最小修复：每个 goal 阶段记录执行主体、输入、输出、命中的 workflow case、允许写入范围和退出证据。
- 下次规则：多阶段 goal 任务进入下一阶段前，Codex 应确认该阶段是在验证 Codex 自身能力、Claude Code 执行能力、还是某个脚本/skill；产物必须包含可检查路径或命令输出。
- 适用边界：适用于 goal 驱动的多阶段工作流验证。不适用于一次性直接回答或单文件小改动。
- 证据路径：`docs\goal-autonomous-codex-workflow-research-20260706.md`、`docs\goal-autonomous-codex-workflow-research-20260706.html`、`tmp\workflow-learning-v11-task2-claude-html-result.md`
- 稳定度：`seed`

### `artifact/interactive-transcript`

- 问题类型：`artifact`
- 触发场景：任务使用侧边栏 Claude Code CLI 或其他 interactive harness，而不是 `scripts\claude-delegate.ps1`。
- 失败证据：interactive 运行如果只靠终端现场信息，后续 Codex 难以验收权限拒绝、失败状态和 Claude Code 的最终报告。
- 根因：interactive harness 没有 `.delegate-runs` 自动三件套，需要人工固定 transcript 命名。
- 最小修复：把同一次 interactive 运行的证据保存在 `tmp\`，使用同一 slug 的 `result.md`、`stdout.json`、`stderr.txt`。
- 下次规则：interactive 委派必须留下 `tmp\<task-slug>-result.md`、`tmp\<task-slug>-stdout.json`、`tmp\<task-slug>-stderr.txt`；缺失任一项时，报告说明原因。
- 适用边界：适用于 interactive harness。普通 batch 委派继续使用 `.delegate-runs\<run>\` 下的标准产物。
- 证据路径：`docs\claude-delegate-workflow.md`、`docs\delegation-authority-v1-validation-checklist.md`、`tmp\workflow-learning-v11-task2-claude-html-result.md`、`tmp\workflow-learning-v11-task3-claude-reflect-permission-scout-result.md`
- 稳定度：`reused-1`

### `routing/similar-skill-name-mismatch`

- 问题类型：`routing`
- 触发场景：用户指定一个 skill，但当前环境里存在名字相近、职责相邻的另一个 skill，例如 `reflect` 与 `reflect-lint`。
- 失败证据：Task 3 初始探索误把用户说的 `reflect` 路由到 `reflect-lint`；用户随后明确真实目标是 `{claude_skills_dir}\reflect`。
- 根因：仅凭名称前缀和描述相似度判断 skill，会把“经验写入”任务与“健康检查”任务混淆。
- 最小修复：当用户给出绝对路径时，以绝对路径为准；当存在相似 skill 名时，先读取目标 `SKILL.md` frontmatter 和路径身份，再执行。
- 下次规则：遇到 `reflect` / `reflect-lint`、`skill-manager` 多版本、bridge / source-of-truth 等相似 skill 时，Codex 必须确认文件身份，不得用相近 skill 替代用户指定目标。
- 适用边界：适用于 skill 路由、bridge 真源识别、同名前缀工具选择。不适用于普通源码符号重名。
- 证据路径：`tmp\workflow-learning-v11-task3-claude-reflect-permission-scout-result.md`、`{claude_skills_dir}\reflect\SKILL.md`、`{skills_repo}\reflect-lint\SKILL.md`
- 稳定度：`seed`

### `permission/reflect-readonly-scout`

- 问题类型：`permission`
- 触发场景：需要评估 Claude Code 专属 `reflect` skill 的真实权限压力，但还不希望写入 `~\.claude\experiences` 或消费 captures。
- 失败证据：`reflect` 明确需要大量 `Read` / `Write` / `Bash` / `AskUserQuestion` / `Agent` 调用；真实扫描 `~\.claude\projects` 会写 `_scan_state.json`，`--consume-confirmed` 会移动 captures。
- 根因：`reflect` 是经验写入型 skill，真实运行天然有宽读取和多写入副作用；不能用普通只读检查权限档替代。
- 最小修复：先用只读 scout 权限档运行：`acceptEdits + --allowedTools Read,Bash,Glob`，只允许读取 reflect skill 目录和运行缺失 archive path 的空结果 smoke command。
- 下次规则：真实运行 `/reflect` 前，先跑 `reflect-readonly-scout` 或等价侦察，列出将读写的路径和工具；只有用户接受写入 `~\.claude\experiences` 后，再升级到真实运行权限档。
- 适用边界：适用于 reflect 权限侦察。不等于真实 `/reflect` 已执行，也不验证原则写入质量。
- 证据路径：`tmp\workflow-learning-v11-task3-claude-reflect-permission-scout-result.md`、`tmp\workflow-learning-v11-task3-claude-reflect-permission-scout-stdout.json`
- 稳定度：`seed`

### `timeout/check-before-rerun`

- 问题类型：`timeout`
- 触发场景：外层 wrapper 或终端命令超时，调用方不知道 Claude Code 是否已经完成、部分完成或写入文件。
- 失败证据：workflow 文档已记录：超时后不能假设“没有工作发生”，必须检查 run 目录和目标 diff。
- 根因：外层进程超时只说明调用方等待结束，不等于被委派进程没有产出。
- 最小修复：重跑前先检查 `.delegate-runs\<run>\` 是否包含 `brief.md`、`command.json`、`claude-output.json`、`result.md`、`metadata.json`，并检查目标 diff。
- 下次规则：遇到 timeout，Codex 先验收现有 artifacts 和工作区状态；只有确认没有可用结果或需要 rescue 时，才发起重跑。
- 适用边界：适用于 batch harness 和有 run artifact 的外层调用。没有 run 目录的 interactive 任务应先按 `artifact/interactive-transcript` 补齐证据。
- 证据路径：`docs\claude-delegate-workflow.md`
- 稳定度：`seed`

### `timeout/detached-execution-decision-point`

- 问题类型：`timeout`
- 触发场景：准备发起长时间、并行、无人值守，或用户可能中途关闭 Codex 的委派任务，需要先判断当前工作台是否具备“脱离 Codex 进程后仍可靠继续执行”的能力。
- 失败证据：`scripts\claude-delegate.ps1` 当前是同步调用链：Codex/PowerShell 启动 `claude.exe` 后阻塞等待返回，再回写 `claude-output.json`、`result.md`、`metadata.json`；`docs\delegate-evolution-phases.md` 明确写着 `no automatic multi-run chaining` 和 `no background workflow supervisor`。
- 根因：当前工作台强调 `task file + .delegate-runs` 的证据化验收，不是后台守护式编排；因此自动压缩主要影响 Codex 上下文，而关闭 Codex/终端则不能被当成“委派会稳态继续”的能力承诺。
- 最小修复：在发起任务前先做一个显式决策：这轮任务是否“必须在 Codex 关闭后继续跑”。如果不是硬需求，沿用当前 harness，并依赖 task file 与 `.delegate-runs` 做中断后复查；如果是硬需求，不要假设当前工作台足够，需单独设计 detached executor / background supervisor。
- 下次规则：凡是用户对“关闭 Codex 是否还能继续跑”有要求，或任务天然属于长时/无人值守/并行编排，Codex 必须先暴露这个决策点，再决定是继续用当前委派链路，还是升级到外部执行层；不要把当前 batch delegate 描述成具备抗关闭能力。
- 适用边界：适用于 `agent-workbench` 当前这套 Codex 指挥 Claude Code 的实验性委派架构。它是架构决策点，不等于已经实现 detached execution。
- 证据路径：`scripts\claude-delegate.ps1`、`docs\claude-delegate-workflow.md`、`docs\delegate-evolution-phases.md`
- 稳定度：`seed`
