#!/usr/bin/env node

/**
 * 安全检测脚本 — 模块 3
 *
 * 扫描 skill 目录中的敏感信息。发现即中断，不自动替换。
 *
 * 用法：node scripts/security-scan.mjs --skill <name> [--dir <path>]
 */

import { readdir, stat, readFile } from 'node:fs/promises';
import { join, relative, extname } from 'node:path';

// ─── CLI 参数解析 ────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--skill' && argv[i + 1]) {
      args.skill = argv[++i];
    } else if (argv[i] === '--dir' && argv[i + 1]) {
      args.dir = argv[++i];
    }
  }
  if (!args.skill) {
    console.error('用法: node security-scan.mjs --skill <name> [--dir <path>]');
    process.exit(2);
  }
  return args;
}

// ─── 扫描规则（按优先级排序） ────────────────────────────────────

const SCAN_RULES = [
  // 高优先级
  {
    id: 'windows-skills-path',
    priority: 'high',
    pattern: /C:\\Users\\[^\\]+\\\.claude\\skills\\([^\\]+)/g,
    description: 'Windows 路径（skills）',
  },
  {
    id: 'linux-skills-path',
    priority: 'high',
    pattern: /\/home\/[^/]+\/\.claude\/skills\/([^/]+)/g,
    description: 'Linux/Mac 路径（skills）',
  },
  {
    id: 'openai-key',
    priority: 'high',
    pattern: /sk-[a-zA-Z0-9]{20,}/g,
    description: 'OpenAI API key',
  },
  {
    id: 'github-token',
    priority: 'high',
    pattern: /ghp_[a-zA-Z0-9]{36}/g,
    description: 'GitHub token',
  },
  {
    id: 'aws-key',
    priority: 'high',
    pattern: /AKIA[0-9A-Z]{16}/g,
    description: 'AWS access key',
  },
  // 中优先级
  {
    id: 'windows-general-path',
    priority: 'medium',
    pattern: /C:\\Users\\[^\\]+\\/g,
    description: 'Windows 路径（通用）',
  },
  {
    id: 'linux-general-path',
    priority: 'medium',
    pattern: /\/home\/[^/]+\//g,
    description: 'Linux/Mac 路径（通用）',
  },
];

// 按优先级排序：high 在前
const PRIORITY_ORDER = { high: 0, medium: 1 };
const SORTED_RULES = [...SCAN_RULES].sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority]);

const SCAN_EXTENSIONS = new Set(['.md', '.json', '.mjs', '.js', '.py']);

// ─── 工具函数 ────────────────────────────────────────────────────

async function walkFiles(dir) {
  const files = [];
  const items = await readdir(dir, { withFileTypes: true });
  for (const item of items) {
    const fullPath = join(dir, item.name);
    if (item.isDirectory()) {
      if (!['__pycache__', '.pytest_cache', 'node_modules', '.git'].includes(item.name)) {
        files.push(...await walkFiles(fullPath));
      }
    } else {
      files.push(fullPath);
    }
  }
  return files;
}

async function isBinary(filePath) {
  try {
    const fh = await readFile(filePath);
    const check = Math.min(fh.length, 1024);
    for (let i = 0; i < check; i++) {
      if (fh[i] === 0) return true;
    }
    return false;
  } catch {
    return true; // 读不出当二进制处理
  }
}

function getLineColumn(content, offset) {
  let line = 1;
  let col = 1;
  for (let i = 0; i < offset; i++) {
    if (content[i] === '\n') {
      line++;
      col = 1;
    } else {
      col++;
    }
  }
  return { line, col };
}

// ─── 扫描逻辑 ────────────────────────────────────────────────────

async function scanFile(filePath, baseDir) {
  const relPath = relative(baseDir, filePath).replace(/\\/g, '/');
  const ext = extname(filePath);

  if (!SCAN_EXTENSIONS.has(ext)) {
    return { findings: [], skipped: null };
  }

  if (await isBinary(filePath)) {
    return { findings: [], skipped: { file: relPath, reason: 'binary' } };
  }

  let content;
  try {
    content = await readFile(filePath, 'utf-8');
  } catch {
    return { findings: [], skipped: { file: relPath, reason: 'read_error' } };
  }

  const findings = [];

  for (const rule of SORTED_RULES) {
    rule.pattern.lastIndex = 0;
    let match;
    while ((match = rule.pattern.exec(content)) !== null) {
      const { line, col } = getLineColumn(content, match.index);
      findings.push({
        file: relPath,
        line,
        column: col,
        pattern: rule.description,
        matched: match[0],
      });
    }
  }

  return { findings, skipped: null };
}

// ─── 主逻辑 ─────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv);
  const repoRoot = process.cwd();
  const scanDir = args.dir || join(repoRoot, args.skill);

  // 验证目录存在
  try {
    const s = await stat(scanDir);
    if (!s.isDirectory()) throw new Error('不是目录');
  } catch {
    const result = {
      skill: args.skill,
      scanned_files: 0,
      findings: [],
      finding_count: 0,
      skipped: [],
      error: '目录不存在或不是目录',
    };
    console.log(JSON.stringify(result, null, 2));
    process.exit(2);
    return;
  }

  const allFiles = await walkFiles(scanDir);
  const allFindings = [];
  const skipped = [];
  let scannedFiles = 0;

  for (const filePath of allFiles) {
    const result = await scanFile(filePath, scanDir);
    if (result.skipped) {
      skipped.push(result.skipped);
    } else {
      scannedFiles++;
    }
    allFindings.push(...result.findings);
  }

  const output = {
    skill: args.skill,
    scanned_files: scannedFiles,
    findings: allFindings,
    finding_count: allFindings.length,
    skipped,
  };

  console.log(JSON.stringify(output, null, 2));

  if (allFindings.length === 0) {
    process.exit(0);
  } else {
    process.exit(1);
  }
}

main().catch(err => {
  console.log(JSON.stringify({ skill: '', scanned_files: 0, findings: [], finding_count: 0, skipped: [], error: err.message }, null, 2));
  process.exit(2);
});
