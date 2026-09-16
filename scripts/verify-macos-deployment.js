const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const runtimeRoot = path.resolve(process.argv[2] || '');
const target = process.argv[3];

if (!runtimeRoot || !target) {
  throw new Error('用法: node verify-macos-deployment.js <runtime-dir> <minimum-macos>');
}

function versionParts(version) {
  return version.split('.').map((part) => Number.parseInt(part, 10) || 0);
}

function compareVersions(left, right) {
  const a = versionParts(left);
  const b = versionParts(right);
  for (let index = 0; index < Math.max(a.length, b.length); index += 1) {
    const difference = (a[index] || 0) - (b[index] || 0);
    if (difference !== 0) return difference;
  }
  return 0;
}

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(entryPath) : [entryPath];
  });
}

let inspected = 0;
let highestMinimum = '0';
const incompatible = [];

for (const file of walk(runtimeRoot)) {
  const kind = spawnSync('file', ['-b', file], { encoding: 'utf8' });
  if (kind.status !== 0 || !kind.stdout.includes('Mach-O')) continue;

  inspected += 1;
  const build = spawnSync('vtool', ['-show-build', file], { encoding: 'utf8' });
  if (build.status !== 0) {
    throw new Error(`无法读取 Mach-O deployment target: ${file}\n${build.stderr}`);
  }

  const minimums = [...build.stdout.matchAll(/\bminos\s+(\d+(?:\.\d+)*)/g)].map((match) => match[1]);
  if (!minimums.length) throw new Error(`Mach-O 缺少 minos 信息: ${file}`);

  for (const minimum of minimums) {
    if (compareVersions(minimum, highestMinimum) > 0) highestMinimum = minimum;
    if (compareVersions(minimum, target) > 0) {
      incompatible.push(`${path.relative(runtimeRoot, file)}: ${minimum}`);
    }
  }
}

if (!inspected) throw new Error(`runtime 中未发现 Mach-O 文件: ${runtimeRoot}`);
if (incompatible.length) {
  throw new Error(`以下文件的最低 macOS 版本高于 ${target}:\n${incompatible.join('\n')}`);
}

console.log(`macOS deployment target 验证通过: ${inspected} 个 Mach-O，最高 ${highestMinimum}`);
