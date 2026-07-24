<div align="center">

# agent-workbench-runner

**agent-workbench 的可移植前门：先初始化工作区，再分类——默认直连，高风险才进托管 runner。**

> 自带脚本副本 · 双层 workspace · 宝玉式首次 setup · Codex 规划 / 验收 · Claude Code 执行

[English](README-en.md) · [快速开始](#快速开始) · [初始化](#初始化) · [什么时候用托管](#什么时候用托管-runner) · [工作原理](#工作原理) · [命令](#命令) · [限制](#限制)

</div>

---

<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="agent-workbench-runner — 先分类：直连协作或托管 runner">
</p>

**调用 `$agent-workbench-runner` 只启动分类，不会强制跑一次 delegate。**  
**首次使用若未找到工作区配置，会阻塞并进入初始化（不会读写作者机器上的 `F:\` 路径）。**

| 通道 | 何时 | 发生什么 |
| --- | --- | --- |
| **直连**（默认） | 普通有界任务 | Codex 与 Claude Code 直接协作；不需要六段任务文件 |
| **托管 runner** | 高风险 / 审计 / 沙箱 | 跑 **本 skill 包内** `scripts/claude-delegate.ps1` + 六段契约 + 可检查产物 |

Codex（或当前拥有验收权的规划方）负责规划与**最终验收**。Claude Code 没有最终验收权。

---

<p align="center">
  <img src="./assets/readme/decision-matrix.svg" width="100%" alt="核心规则：默认直连，仅在需要控制时升级托管">
</p>

## 它是什么

可发布的 Skill 包，形状类似宝玉 skill：`{baseDir}/scripts` 执行 + 首次 setup 写本地配置。

| 层级 | 位置 | 内容 |
| --- | --- | --- |
| **Skill 包**（只读逻辑） | 安装目录 `{baseDir}` | `SKILL.md`、`scripts/*.ps1`、契约 `docs/`、模板、README |
| **Runtime workspace**（可脏） | 项目 `.agent-workbench/` 或 `~/.agent-workbench/` | `config.json`、任务文件、sandbox、`.delegate-runs/` |

脚本**永远**从 skill 包执行，不在 workspace 里分叉一份可执行副本（避免和上游更新分叉）。

---

## 快速开始

### 安装 / 下载

```bash
# 方式一：skills.sh（发布到 Reese0302/skills 之后）
npx skills@latest add Reese0302/skills --skill agent-workbench-runner
```

```bash
# 方式二：从 monorepo 检出后只拷本 skill（复制，不要移动）
git clone https://github.com/Reese0302/skills.git /tmp/skills
mkdir -p ~/.claude/skills
cp -r /tmp/skills/agent-workbench-runner ~/.claude/skills/agent-workbench-runner
# Codex:
mkdir -p ~/.codex/skills
cp -r /tmp/skills/agent-workbench-runner ~/.codex/skills/agent-workbench-runner
```

```powershell
# 方式三：本机已有目录时复制进 skills（作者开发机）
Copy-Item -Recurse -Force F:\agent-workbench-runner "$env:USERPROFILE\.claude\skills\agent-workbench-runner"
Copy-Item -Recurse -Force F:\agent-workbench-runner "$env:USERPROFILE\.codex\skills\agent-workbench-runner"
```

**依赖：** Windows 上托管路径需要 **PowerShell**（5.1 / 7）与可发现的 **Claude Code CLI**。脚本会尝试自动发现 CLI；也可在 `config.json` 里设 `claude_path`。

### 触发

```text
$agent-workbench-runner
用 agent workbench 跑这个任务
先初始化 workbench
重新初始化 workbench
```

### 最简心智模型

```text
调用 skill
  → 查找 workspace config（项目 → 用户）
      无 → first-time-setup（阻塞）→ 写 config + 建目录
  → 分类
      ├─ 普通有界 → 直连 Codex ↔ Claude Code → 验收
      └─ Core Rule → sandbox + 六段任务 + DryRun → 真实运行 → 规划方验收
```

---

## 初始化

与宝玉 skill 的 Step 0 类似：**没有配置就禁止往下跑。**

查找顺序：

1. `$PWD/.agent-workbench/config.json`
2. `~/.agent-workbench/config.json`（Windows：`%USERPROFILE%\.agent-workbench\`）

首次会问：

1. 工作区级别：用户主目录（推荐） / 当前项目  
2. Sandbox：默认 `{workspace}/sandbox/` / 自定义可丢弃绝对路径  
3. 语言：`zh` / `en`（可选）

然后**从 skill 包模板复制**（不移动任何已有仓库文件）生成：

```text
{workspace}/
├── config.json
├── AGENTS.md
├── docs/task.md
├── sandbox/           # 默认
└── .delegate-runs/
```

详情见 [references/setup/first-time-setup.md](references/setup/first-time-setup.md)。

示例 `config.json`：

```json
{
  "schema_version": 1,
  "workspace_root": "C:\\Users\\you\\.agent-workbench",
  "sandbox_path": "./sandbox",
  "permission_profile_default": "default",
  "claude_path": null,
  "language": "zh"
}
```

---

<p align="center">
  <img src="./assets/readme/section-when.svg" width="100%" alt="章节：何时使用">
</p>

## 什么时候用托管 runner

**仅当**至少满足一条：

1. 用户明确要求 managed sandbox 或 delegate run  
2. 需要 root guidance 校验、冲突拦截或 confirmed-experience 投影  
3. 完成声明依赖 native-web 遥测或可检查 run 产物  
4. 必须在可丢弃 sandbox 里执行以保护主 worktree  

不要只为了「输出更好看」就上 runner。

---

<p align="center">
  <img src="./assets/readme/section-how.svg" width="100%" alt="章节：工作原理">
</p>

## 工作原理

<p align="center">
  <img src="./assets/readme/workflow.svg" width="100%" alt="托管路径：分类 → 沙箱 → 规则 → 路由 → 六段契约 → DryRun → 验收">
</p>

### 托管路径

1. 确保 workspace 已 init  
2. 分类；仅 Core Rule 触发才继续  
3. 使用 `sandbox_abs`（由 config 解析）  
4. 读契约文档（`{baseDir}/docs/…`）与 workspace `AGENTS.md`  
5. 可选 `codex-route.ps1`  
6. 填齐六段任务（常用 `{workspace}/docs/task.md`）  
7. 变更后先 `-DryRun`  
8. 规划方检查产物并验收  

### Claim 审查字段

`claim` · `evidence tier` · `trust boundary` · `missing evidence` · `conclusion consistency`  

完整产物 ≠ 最终 claim 验收。

---

<p align="center">
  <img src="./assets/readme/section-commands.svg" width="100%" alt="章节：命令">
</p>

## 命令

将 `{baseDir}`、`{workspace_root}`、`{sandbox_abs}` 换成**解析后的绝对路径**。

```powershell
& "{baseDir}\scripts\codex-route.ps1" -TaskText "<task>"

& "{baseDir}\scripts\claude-delegate.ps1" `
  -TaskFile "{workspace_root}\docs\task.md" `
  -AddDir "{sandbox_abs}" `
  -Name <name> `
  -DryRun

& "{baseDir}\scripts\claude-delegate.ps1" `
  -TaskFile "{workspace_root}\docs\task.md" `
  -AddDir "{sandbox_abs}" `
  -Name <name>

& "{baseDir}\scripts\list-delegate-runs.ps1" -Latest 10
```

---

<p align="center">
  <img src="./assets/readme/section-safety.svg" width="100%" alt="章节：安全与收口">
</p>

## 安全与收口

- 产物落在 workspace/sandbox 的 `.delegate-runs/`  
- `PermissionProfile` 是否强制以 `docs/execution-boundary-matrix.md` 为准  
- `WorkflowLearningCase` 不单独改 Claude 参数  
- 会改主项目 worktree → 停下先问  
- **禁止**把作者机器路径当成陌生人环境的默认值  

收口清单：workspace / sandbox 路径 · 命令 · 产物路径 · 验证结果 · 主仓是否未动  

---

## 包内布局

```text
agent-workbench-runner/
├── SKILL.md
├── README.md / README-en.md
├── assets/readme/
├── scripts/                 # 从上游 workbench 复制进来的执行器
│   ├── claude-delegate.ps1
│   ├── claude-cli-discovery.ps1
│   ├── codex-route.ps1
│   └── list-delegate-runs.ps1
├── docs/                    # 只读契约
├── templates/workspace/     # init 素材
└── references/setup/
    └── first-time-setup.md
```

---

## 限制

| 维度 | 能 | 不能 |
| --- | --- | --- |
| 安装 | 跨机器复制/发布 skill 包 | 自动拥有作者的 `F:\agent-workbench` 历史 |
| 执行 | 包内脚本 + 用户 workspace | 无 PowerShell / 无 Claude CLI 时托管跑通 |
| 范围 v1 | 分类 + 委派三件套 + init | 打包全部 evidence/rescue 编排器 |
| 验收 | 强调规划方终验 | 把完整产物自动当成 claim 通过 |

> 装 skill → init workspace → 该直连直连、该托管托管。最终信不信结果，仍是规划方 / 你的事。
