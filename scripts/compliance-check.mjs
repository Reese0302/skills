#!/usr/bin/env node

/**
 * 合规检查脚本 — 模块 4
 *
 * 检查 skill 的 SKILL.md frontmatter 是否符合发布规范。
 *
 * 用法：node scripts/compliance-check.mjs --skill <name>
 */

import { readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';

// ─── CLI 参数解析 ────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--skill' && argv[i + 1]) {
      args.skill = argv[++i];
    }
  }
  if (!args.skill) {
    console.error('用法: node compliance-check.mjs --skill <name>');
    process.exit(3);
  }
  return args;
}

// ─── YAML frontmatter 简易解析 ───────────────────────────────────

function parseFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return null;

  const lines = match[1].split(/\r?\n/);
  const result = {};
  let currentKey = null;
  let currentValue = [];

  for (const line of lines) {
    const kvMatch = line.match(/^([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)/);
    if (kvMatch) {
      if (currentKey !== null) {
        result[currentKey] = currentValue.join('\n').trim();
      }
      currentKey = kvMatch[1];
      currentValue = [kvMatch[2]];
    } else if (currentKey !== null) {
      // 多行 YAML 值续行
      currentValue.push(line.trimStart());
    }
  }
  if (currentKey !== null) {
    result[currentKey] = currentValue.join('\n').trim();
  }

  return result;
}

// ─── 检查项定义 ──────────────────────────────────────────────────

const CHECKS = [
  { id: 1, name: 'SKILL.md 存在', level: 'error' },
  { id: 2, name: 'frontmatter 可解析', level: 'error' },
  { id: 3, name: 'frontmatter 有 name', level: 'error' },
  { id: 4, name: 'frontmatter 有 description', level: 'error' },
  { id: 5, name: 'name ≤64 字符', level: 'error' },
  { id: 6, name: 'name 格式合规', level: 'error' },
  { id: 7, name: 'name 与目录名一致', level: 'error' },
  { id: 8, name: 'description ≤1024 字符', level: 'error' },
  { id: 9, name: 'LICENSE 存在', level: 'warning' },
  { id: 10, name: 'README.md 存在', level: 'warning' },
];

// ─── 主逻辑 ─────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv);
  const repoRoot = process.cwd();
  const skillDir = join(repoRoot, args.skill);
  const skillMdPath = join(skillDir, 'SKILL.md');

  const results = [];
  let skillMdExists = false;
  let frontmatter = null;
  let frontmatterParsed = false;

  // 序 1: SKILL.md 存在
  try {
    await stat(skillMdPath);
    skillMdExists = true;
    results.push({ id: 1, name: 'SKILL.md 存在', status: 'pass', level: 'error' });
  } catch {
    results.push({ id: 1, name: 'SKILL.md 存在', status: 'fail', level: 'error', detail: '文件不存在' });
  }

  if (!skillMdExists) {
    // 序 2-8 全部 skip
    for (let i = 2; i <= 8; i++) {
      const check = CHECKS[i - 1];
      results.push({ id: check.id, name: check.name, status: 'skip', level: check.level });
    }
  } else {
    // 读取 SKILL.md
    let content;
    try {
      content = await readFile(skillMdPath, 'utf-8');
    } catch {
      // 读取失败，序 2-8 全部 skip
      for (let i = 2; i <= 8; i++) {
        const check = CHECKS[i - 1];
        results.push({ id: check.id, name: check.name, status: 'skip', level: check.level });
      }
      // 序 9-10 继续检查
      await checkFileExists(skillDir, 'LICENSE', 9, results);
      await checkFileExists(skillDir, 'README.md', 10, results);
      outputResults(args.skill, results);
      return;
    }

    // 序 2: frontmatter 可解析
    frontmatter = parseFrontmatter(content);
    if (frontmatter === null) {
      results.push({ id: 2, name: 'frontmatter 可解析', status: 'fail', level: 'error', detail: '无法解析 YAML frontmatter' });
      // 序 3-8 skip
      for (let i = 3; i <= 8; i++) {
        const check = CHECKS[i - 1];
        results.push({ id: check.id, name: check.name, status: 'skip', level: check.level });
      }
    } else {
      frontmatterParsed = true;
      results.push({ id: 2, name: 'frontmatter 可解析', status: 'pass', level: 'error' });

      // 序 3: frontmatter 有 name
      if (frontmatter.name && String(frontmatter.name).trim()) {
        results.push({ id: 3, name: 'frontmatter 有 name', status: 'pass', level: 'error' });
      } else {
        results.push({ id: 3, name: 'frontmatter 有 name', status: 'fail', level: 'error', detail: 'name 字段为空或不存在' });
      }

      // 序 4: frontmatter 有 description
      if (frontmatter.description && String(frontmatter.description).trim()) {
        results.push({ id: 4, name: 'frontmatter 有 description', status: 'pass', level: 'error' });
      } else {
        results.push({ id: 4, name: 'frontmatter 有 description', status: 'fail', level: 'error', detail: 'description 字段为空或不存在' });
      }

      const name = frontmatter.name ? String(frontmatter.name).trim() : '';

      // 序 5: name ≤64 字符
      if (name.length <= 64) {
        results.push({ id: 5, name: 'name ≤64 字符', status: 'pass', level: 'error' });
      } else {
        results.push({ id: 5, name: 'name ≤64 字符', status: 'fail', level: 'error', detail: `name 长度 ${name.length} 超过 64` });
      }

      // 序 6: name 仅小写字母、数字、连字符
      if (/^[a-z0-9-]+$/.test(name)) {
        results.push({ id: 6, name: 'name 格式合规', status: 'pass', level: 'error' });
      } else {
        results.push({ id: 6, name: 'name 格式合规', status: 'fail', level: 'error', detail: 'name 包含不允许的字符（仅允许小写字母、数字、连字符）' });
      }

      // 序 7: name 与目录名一致
      if (name === args.skill) {
        results.push({ id: 7, name: 'name 与目录名一致', status: 'pass', level: 'error' });
      } else {
        results.push({ id: 7, name: 'name 与目录名一致', status: 'fail', level: 'error', detail: `name="${name}" ≠ 目录名="${args.skill}"` });
      }

      // 序 8: description ≤1024 字符（Unicode 码点计算）
      const desc = frontmatter.description ? String(frontmatter.description).trim() : '';
      const descLength = [...desc].length; // Unicode 码点
      if (descLength <= 1024) {
        results.push({ id: 8, name: 'description ≤1024 字符', status: 'pass', level: 'error' });
      } else {
        results.push({ id: 8, name: 'description ≤1024 字符', status: 'fail', level: 'error', detail: `description 长度 ${descLength} 超过 1024` });
      }
    }
  }

  // 序 9: LICENSE 存在
  await checkFileExists(skillDir, 'LICENSE', 9, results);

  // 序 10: README.md 存在
  await checkFileExists(skillDir, 'README.md', 10, results);

  outputResults(args.skill, results);
}

async function checkFileExists(dir, filename, checkId, results) {
  const check = CHECKS[checkId - 1];
  try {
    await stat(join(dir, filename));
    results.push({ id: check.id, name: check.name, status: 'pass', level: check.level });
  } catch {
    results.push({ id: check.id, name: check.name, status: 'fail', level: check.level, detail: `${filename} 不存在` });
  }
}

function outputResults(skill, results) {
  const errorCount = results.filter(r => r.status === 'fail' && r.level === 'error').length;
  const warningCount = results.filter(r => r.status === 'fail' && r.level === 'warning').length;
  const pass = errorCount === 0;

  const output = {
    skill,
    checks: results,
    error_count: errorCount,
    warning_count: warningCount,
    pass,
  };

  console.log(JSON.stringify(output, null, 2));

  if (errorCount > 0) {
    process.exit(2);
  } else if (warningCount > 0) {
    process.exit(1);
  } else {
    process.exit(0);
  }
}

main().catch(err => {
  console.log(JSON.stringify({ skill: '', checks: [], error_count: 0, warning_count: 0, pass: false, error: err.message }, null, 2));
  process.exit(3);
});
