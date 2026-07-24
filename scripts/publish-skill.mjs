#!/usr/bin/env node

/**
 * 多渠道发布脚本 — 模块 6
 *
 * 创建 Git Tag + GitHub Release + 上传 zip 附件。
 * 幂等保护：tag 已存在则跳过。
 *
 * 用法：node scripts/publish-skill.mjs --skill <name> --version <vX.Y.Z> --dir <dir>
 */

import { execSync } from 'node:child_process';
import { readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';

// ─── CLI 参数解析 ────────────────────────────────────────────────

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--skill' && argv[i + 1]) {
      args.skill = argv[++i];
    } else if (argv[i] === '--version' && argv[i + 1]) {
      args.version = argv[++i];
    } else if (argv[i] === '--dir' && argv[i + 1]) {
      args.dir = argv[++i];
    }
  }
  if (!args.skill || !args.version || !args.dir) {
    console.error('用法: node publish-skill.mjs --skill <name> --version <vX.Y.Z> --dir <dir>');
    process.exit(2);
  }
  return args;
}

function run(cmd) {
  return execSync(cmd, { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
}

// ─── 主逻辑 ─────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv);
  const tag = `${args.skill}@${args.version}`;

  // 幂等保护：检查 tag 是否已存在
  try {
    run(`git rev-parse ${tag}`);
    console.log(JSON.stringify({
      skill: args.skill,
      version: args.version,
      tag,
      status: 'skipped',
      reason: 'tag already exists',
    }, null, 2));
    process.exit(0);
    return;
  } catch {
    // tag 不存在，继续
  }

  // 提取 release notes（从 CHANGELOG.md）
  let releaseNotes = `${args.skill} ${args.version}`;
  try {
    const changelog = await readFile(join(args.dir, 'CHANGELOG.md'), 'utf-8');
    const versionSection = extractVersionSection(changelog, args.version);
    if (versionSection) {
      releaseNotes = versionSection;
    }
  } catch {}

  // Step 1: 创建 Git Tag
  try {
    run(`git tag ${tag}`);
  } catch (err) {
    console.error(`创建 tag 失败: ${err.message}`);
    process.exit(1);
  }

  // Step 2: 创建 GitHub Release
  try {
    // 写临时 notes 文件避免 shell 转义问题
    const notesFile = join(args.dir, '.release-notes.md');
    const { writeFileSync } = await import('node:fs');
    writeFileSync(notesFile, releaseNotes, 'utf-8');
    run(`gh release create ${tag} --title "${args.skill} ${args.version}" --notes-file "${notesFile}" --target main`);
  } catch (err) {
    console.error(`创建 Release 失败: ${err.message}`);
    process.exit(1);
  }

  // Step 3: 打包并上传 zip
  try {
    const zipName = `${args.skill}-${args.version}.zip`;
    run(`cd "${args.dir}" && zip -r "${zipName}" . -x ".release-notes.md"`);
    run(`gh release upload ${tag} "${join(args.dir, zipName)}" --clobber`);
  } catch (err) {
    console.error(`上传附件失败: ${err.message}`);
    // Release 已创建，不算致命错误
  }

  console.log(JSON.stringify({
    skill: args.skill,
    version: args.version,
    tag,
    status: 'published',
  }, null, 2));
}

function extractVersionSection(changelog, version) {
  const lines = changelog.split('\n');
  const section = [];
  let inSection = false;
  for (const line of lines) {
    if (line.startsWith(`## ${version}`)) {
      inSection = true;
      continue;
    }
    if (inSection && /^## /.test(line)) break;
    if (inSection) section.push(line);
  }
  return section.join('\n').trim() || null;
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
