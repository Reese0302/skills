#!/usr/bin/env node

/**
 * 发布件生成脚本 — 模块 5
 *
 * 在临时目录生成发布件：复制 include 文件 + 安全替换 + 生成 README/LICENSE/CHANGELOG。
 *
 * 用法：node scripts/generate-artifacts.mjs --skill <name> --out <dir>
 */

import { readdir, stat, readFile, writeFile, cp, mkdir, rm } from 'node:fs/promises';
import { join, posix, relative } from 'node:path';
import { execSync } from 'node:child_process';

// ─── CLI 参数解析 ────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--skill' && argv[i + 1]) {
      args.skill = argv[++i];
    } else if (argv[i] === '--out' && argv[i + 1]) {
      args.out = argv[++i];
    }
  }
  if (!args.skill || !args.out) {
    console.error('用法: node generate-artifacts.mjs --skill <name> --out <dir>');
    process.exit(1);
  }
  return args;
}

// ─── YAML frontmatter 简易解析 ───────────────────────────────────

function parseFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return {};
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
      currentValue.push(line.trimStart());
    }
  }
  if (currentKey !== null) {
    result[currentKey] = currentValue.join('\n').trim();
  }
  return result;
}

// ─── 版本号生成 ──────────────────────────────────────────────────

async function getVersion(repoRoot, skillName) {
  try {
    const published = JSON.parse(await readFile(join(repoRoot, '.published.json'), 'utf-8'));
    const last = published[skillName]?.last_version;
    if (last) {
      const m = last.match(/^v(\d+)\.(\d+)\.(\d+)$/);
      if (m) {
        return `v${m[1]}.${m[2]}.${parseInt(m[3]) + 1}`;
      }
    }
  } catch {}
  return 'v1.0.0';
}

// ─── README 生成 ─────────────────────────────────────────────────

function generateReadme(fm, skillName, version) {
  const name = fm.name || skillName;
  // 取 description 第一行有效内容（去掉 YAML | 标记和多行内容）
  const rawDesc = (fm.description || '').replace(/^\|\s*\n?/, '').trim();
  const desc = rawDesc.split('\n')[0].trim();

  // 从 SKILL.md 提取功能章节的 H3 标题
  const featureSection = extractSection(fm._raw || '', /功能|能力|工具/);
  const features = featureSection
    ? featureSection.match(/^### .+$/gm)?.map(h => `- ${h.replace(/^### /, '')}`).join('\n') || '- <!-- TODO: 补充功能列表 -->'
    : '- <!-- TODO: 补充功能列表 -->';

  const howTo = extractSection(fm._raw || '', /执行步骤|工作流|使用场景/) || '<!-- TODO: 补充使用说明 -->';

  const installCmd = '```bash\n# 通过 Claude Code 安装\nclaude install-skill ' + name + '\n```';

  return `# ${name}

> ${desc || '<!-- TODO: 补充一句话介绍 -->'}

## 快速开始

${installCmd}

**触发方式**：${extractTrigger(fm._raw || '') || '<!-- TODO: 补充触发方式 -->'}

## 它解决什么问题

${desc || '<!-- TODO: 补充问题描述 -->'}

## 怎么用

${howTo}

## 功能列表

${features}

## 更新日志

v${version.replace(/^v/, '')} (${new Date().toISOString().slice(0, 10)}) — 更新说明见 CHANGELOG.md

## 许可证

MIT
`;
}

function extractSection(raw, titleRegex) {
  const lines = raw.split('\n');
  let inSection = false;
  const section = [];
  for (const line of lines) {
    if (/^## /.test(line)) {
      if (inSection) break;
      if (titleRegex.test(line)) {
        inSection = true;
        continue;
      }
    }
    if (inSection) section.push(line);
  }
  return section.join('\n').trim() || null;
}

function extractTrigger(raw) {
  const lines = raw.split('\n');
  for (const line of lines) {
    if (/触发|trigger|激活/i.test(line) && line.length < 200) {
      return line.replace(/^[-*]\s*/, '').trim();
    }
  }
  return null;
}

// ─── LICENSE 生成 ────────────────────────────────────────────────

function generateLicense(skillName) {
  const year = new Date().getFullYear();
  return `MIT License

Copyright (c) ${year} ${skillName}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
`;
}

// ─── CHANGELOG 生成 ──────────────────────────────────────────────

function generateChangelog(fm, version, skillName) {
  const date = new Date().toISOString().slice(0, 10);
  const raw = fm._raw || '';

  // 功能列表
  const featureSection = extractSection(raw, /功能|能力|工具/);
  const features = featureSection
    ? featureSection.match(/^### .+$/gm)?.map(h => `- ${h.replace(/^### /, '')}`).join('\n') || '- <!-- 从 SKILL.md 功能列表自动填充 -->'
    : '- <!-- 从 SKILL.md 功能列表自动填充 -->';

  return `# Changelog

## ${version} (${date})

### 功能
${features}

### 资源脚本
- <!-- 从 resources/*.mjs 自动填充 -->

### 依赖
- <!-- 从 SKILL.md 依赖引用自动填充 -->
`;
}

// ─── .gitignore 生成 ─────────────────────────────────────────────

const GITIGNORE = `publish-checklist.md
MISTAKES.md
logs/
*.log
`;

// ─── 安全替换（复用 security-scan 逻辑） ────────────────────────

const SCAN_RULES = [
  { pattern: /C:\\Users\\[^\\]+\\\.claude\\skills\\([^\\]+)/g, replacement: (m, s) => `~/.claude/skills/${s}` },
  { pattern: /\/home\/[^/]+\/\.claude\/skills\/([^/]+)/g, replacement: (m, s) => `~/.claude/skills/${s}` },
  { pattern: /sk-[a-zA-Z0-9]{20,}/g, replacement: () => '[REDACTED]' },
  { pattern: /ghp_[a-zA-Z0-9]{36}/g, replacement: () => '[REDACTED]' },
  { pattern: /AKIA[0-9A-Z]{16}/g, replacement: () => '[REDACTED]' },
  { pattern: /C:\\Users\\[^\\]+\\/g, replacement: () => '{用户目录}' },
  { pattern: /\/home\/[^/]+\//g, replacement: () => '{用户目录}' },
];

async function securityReplace(dir) {
  const SCAN_EXT = new Set(['.md', '.json', '.mjs', '.js', '.py']);
  const files = await walkFiles(dir);
  for (const filePath of files) {
    const ext = filePath.slice(filePath.lastIndexOf('.'));
    if (!SCAN_EXT.has(ext)) continue;
    let content;
    try {
      content = await readFile(filePath, 'utf-8');
    } catch { continue; }
    let modified = content;
    for (const rule of SCAN_RULES) {
      rule.pattern.lastIndex = 0;
      modified = modified.replace(rule.pattern, rule.replacement);
    }
    if (modified !== content) {
      await writeFile(filePath, modified, 'utf-8');
    }
  }
}

async function walkFiles(dir) {
  const files = [];
  const items = await readdir(dir, { withFileTypes: true });
  for (const item of items) {
    const fullPath = join(dir, item.name);
    if (item.isDirectory()) {
      files.push(...await walkFiles(fullPath));
    } else {
      files.push(fullPath);
    }
  }
  return files;
}

// ─── 主逻辑 ─────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv);
  const repoRoot = process.cwd();
  const skillDir = join(repoRoot, args.skill);
  const outDir = args.out;

  // 验证 skill 目录
  try {
    const s = await stat(skillDir);
    if (!s.isDirectory()) throw new Error('不是目录');
  } catch {
    console.error(`skill 目录不存在: ${skillDir}`);
    process.exit(1);
  }

  // Step 0: 清空/创建输出目录
  await rm(outDir, { recursive: true, force: true });
  await mkdir(outDir, { recursive: true });

  // Step 1: 复制所有文件（卫生检查的 include 清单在此简化为全量复制）
  // 完整实现应接收 include 清单，此处先全量复制
  const allFiles = await walkFiles(skillDir);
  for (const filePath of allFiles) {
    const rel = relative(skillDir, filePath).replace(/\\/g, '/');
    const dest = join(outDir, rel);
    await mkdir(join(dest, '..'), { recursive: true });
    await cp(filePath, dest);
  }

  // Step 2: 安全替换（在输出目录上执行）
  await securityReplace(outDir);

  // 读取 SKILL.md frontmatter
  let fm = {};
  let raw = '';
  try {
    raw = await readFile(join(skillDir, 'SKILL.md'), 'utf-8');
    fm = parseFrontmatter(raw);
    fm._raw = raw;
  } catch {}

  const version = await getVersion(repoRoot, args.skill);
  const today = new Date().toISOString().slice(0, 10);

  // Step 3: 生成 README.md
  await writeFile(join(outDir, 'README.md'), generateReadme(fm, args.skill, version), 'utf-8');

  // Step 4: 生成 LICENSE
  await writeFile(join(outDir, 'LICENSE'), generateLicense(fm.name || args.skill), 'utf-8');

  // Step 5: 生成 CHANGELOG.md
  await writeFile(join(outDir, 'CHANGELOG.md'), generateChangelog(fm, version, args.skill), 'utf-8');

  // Step 6: 生成 .gitignore
  await writeFile(join(outDir, '.gitignore'), GITIGNORE, 'utf-8');

  console.log(JSON.stringify({
    skill: args.skill,
    version,
    out_dir: outDir,
    files: (await walkFiles(outDir)).map(f => relative(outDir, f).replace(/\\/g, '/')).sort(),
    date: today,
  }, null, 2));
}

main().catch(err => {
  console.error(err);
  process.exit(2);
});
