#!/usr/bin/env node

/**
 * 卫生检查脚本 — 模块 2
 *
 * 对 skill 目录中的文件按 Hard Rule 分类为 include / exclude / pending，
 * 然后套用 Confirmed Rules 自动裁决 pending 文件。
 *
 * 用法：node scripts/hygiene-check.mjs --skill <name> [--rules <path>]
 */

import { readdir, stat, readFile } from 'node:fs/promises';
import { join, relative, posix } from 'node:path';

// ─── CLI 参数解析 ────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--skill' && argv[i + 1]) {
      args.skill = argv[++i];
    } else if (argv[i] === '--rules' && argv[i + 1]) {
      args.rules = argv[++i];
    }
  }
  if (!args.skill) {
    console.error('用法: node hygiene-check.mjs --skill <name> [--rules <path>]');
    process.exit(2);
  }
  return args;
}

// ─── Hard Rule 定义 ──────────────────────────────────────────────

const HARD_RULES = [
  // 序 1-5: 直排
  { id: 1, regex: /\.(bak|tmp|swp)$/, action: 'exclude' },
  { id: 2, regex: /^temp_/, action: 'exclude' },
  { id: 3, regex: /.*-workspace\/$|.*_workspace\/$/, action: 'exclude' },
  { id: 4, regex: /^新建/, action: 'exclude' },
  { id: 5, regex: /^(__pycache__|\.pytest_cache|node_modules)\/$|^(\.DS_Store|Thumbs\.db)$/, action: 'exclude' },
  // 序 6: SKILL.md 直留
  { id: 6, regex: /^SKILL\.md$/, action: 'include' },
  // 序 7: MISTAKES.md pending
  { id: 7, regex: /^MISTAKES\.md$/, action: 'pending' },
  // 序 8-9: README.md / test-prompts.json 直留
  { id: 8, regex: /^README\.md$/, action: 'include' },
  { id: 9, regex: /^test-prompts\.json$/, action: 'include' },
  // 序 10: 特定目录 → 进入引用判断（特殊处理）
  { id: 10, regex: /^(references|resources|docs|examples|demos|assets|templates|scripts)\//, action: 'reference_judge' },
  // 序 11: tests/ 直留
  { id: 11, regex: /^tests\/$/, action: 'include' },
  // 序 12-15: pending 规则
  { id: 12, regex: /.*_state\.json$|.*_history\.json$|.*_cache\.json$|.*_memory\.json$|.*_config\.json$/, action: 'pending' },
  { id: 13, regex: /.*规格.*\.md$|^REFACTOR_PLAN\.md$|^improvement-spec.*\.md$|^SPEC\.md$/, action: 'pending' },
  { id: 14, regex: /^_?[^/]*\.py$/, action: 'pending' },
  { id: 15, regex: /^CLAUDE\.md$|.*\.tsv$|^logs\/$|.*\.log$/, action: 'pending' },
  // 序 16: 兜底
  { id: 16, regex: /.*/, action: 'pending' },
];

// ─── 路径归一化 ──────────────────────────────────────────────────

async function walkDir(dir, base) {
  const entries = [];
  const items = await readdir(dir, { withFileTypes: true });
  for (const item of items) {
    const fullPath = join(dir, item.name);
    const relPath = posix.normalize(relative(base, fullPath).replace(/\\/g, '/'));
    if (item.isDirectory()) {
      entries.push(relPath + '/');
      // 递归进入子目录（但跳过已知排除目录）
      if (!/^(__pycache__|\.pytest_cache|node_modules)\/$/.test(relPath + '/')) {
        entries.push(...await walkDir(fullPath, base));
      }
    } else {
      entries.push(relPath);
    }
  }
  return entries;
}

// ─── Reference-based Judgment ────────────────────────────────────

async function getReferencedDirs(skillDir) {
  const skillMdPath = join(skillDir, 'SKILL.md');
  let content;
  try {
    content = await readFile(skillMdPath, 'utf-8');
  } catch {
    return null; // SKILL.md 读取失败
  }

  const refs = new Set();
  // 匹配 /目录名[/\s)）]/ 或 ./目录名/ 或 bare 目录名
  const dirNames = ['references', 'resources', 'docs', 'examples', 'demos', 'assets', 'templates', 'scripts'];
  for (const name of dirNames) {
    const re = new RegExp(`/${name}[/\\s)）]|\\./${name}[/\\s)）]?|\\b${name}\\b`, 'g');
    if (re.test(content)) {
      refs.add(name);
    }
  }
  return refs;
}

// ─── Confirmed Rules 套用 ────────────────────────────────────────

async function loadConfirmedRules(rulesPath) {
  try {
    const content = await readFile(rulesPath, 'utf-8');
    const data = JSON.parse(content);
    if (Array.isArray(data.confirmed)) {
      return data.confirmed;
    }
    return [];
  } catch {
    return [];
  }
}

function applyConfirmedRules(pendingFiles, confirmedRules) {
  const stillPending = [];
  const resolved = [];

  for (const file of pendingFiles) {
    let matched = false;
    for (const rule of confirmedRules) {
      // 精确路径匹配（禁用 glob / regex）
      if (rule.pattern === file) {
        resolved.push({ file, verdict: rule.verdict, appliedRule: rule.pattern });
        matched = true;
        break;
      }
    }
    if (!matched) {
      stillPending.push(file);
    }
  }

  return { stillPending, resolved };
}

// ─── 主逻辑 ─────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv);
  const repoRoot = process.cwd();
  const skillDir = join(repoRoot, args.skill);

  // 验证 skill 目录存在
  let dirStat;
  try {
    dirStat = await stat(skillDir);
  } catch {
    outputAndExit({ skill: args.skill, include: [], exclude: [], pending: [], pending_count: 0, error: 'skill 目录不存在' }, 2);
    return;
  }
  if (!dirStat.isDirectory()) {
    outputAndExit({ skill: args.skill, include: [], exclude: [], pending: [], pending_count: 0, error: 'skill 路径不是目录' }, 2);
    return;
  }

  // 验证 SKILL.md 存在
  try {
    await stat(join(skillDir, 'SKILL.md'));
  } catch {
    outputAndExit({ skill: args.skill, include: [], exclude: [], pending: [], pending_count: 0, error: 'SKILL.md 不存在' }, 2);
    return;
  }

  // 遍历所有文件
  const allPaths = await walkDir(skillDir, skillDir);

  // 加载 Confirmed Rules
  const rulesPath = args.rules || join(repoRoot, '.confirmed-rules.json');
  const confirmedRules = await loadConfirmedRules(rulesPath);

  // 获取引用目录（用于序 10）
  const referencedDirs = await getReferencedDirs(skillDir);

  // 分类
  const include = [];
  const exclude = [];
  const pending = [];

  for (const path of allPaths) {
    let classified = false;
    for (const rule of HARD_RULES) {
      if (rule.regex.test(path)) {
        if (rule.action === 'reference_judge') {
          // 序 10: 检查 SKILL.md 是否引用了该目录
          const dirName = path.split('/')[0];
          if (referencedDirs === null) {
            // SKILL.md 读取失败，降级为 pending
            pending.push(path);
          } else if (referencedDirs.has(dirName)) {
            include.push(path);
          } else {
            pending.push(path);
          }
        } else if (rule.action === 'include') {
          include.push(path);
        } else if (rule.action === 'exclude') {
          exclude.push(path);
        } else {
          pending.push(path);
        }
        classified = true;
        break;
      }
    }
    if (!classified) {
      pending.push(path);
    }
  }

  // 套用 Confirmed Rules
  const { stillPending, resolved } = applyConfirmedRules(pending, confirmedRules);
  for (const r of resolved) {
    if (r.verdict === 'include') {
      include.push(r.file);
    } else {
      exclude.push(r.file);
    }
  }

  const result = {
    skill: args.skill,
    include: include.sort(),
    exclude: exclude.sort(),
    pending: stillPending.sort(),
    pending_count: stillPending.length,
    error: null,
  };

  const exitCode = stillPending.length > 0 ? 1 : 0;
  outputAndExit(result, exitCode);
}

function outputAndExit(obj, code) {
  console.log(JSON.stringify(obj, null, 2));
  process.exit(code);
}

main().catch(err => {
  outputAndExit({ skill: '', include: [], exclude: [], pending: [], pending_count: 0, error: err.message }, 2);
});
