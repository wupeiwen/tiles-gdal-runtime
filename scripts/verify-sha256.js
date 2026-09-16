const crypto = require('node:crypto');
const fs = require('node:fs');

const [expected, file] = process.argv.slice(2);
if (!expected || !file) {
  throw new Error('用法: node verify-sha256.js <expected-sha256> <file>');
}

const actual = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
if (actual.toLowerCase() !== expected.toLowerCase()) {
  throw new Error(`SHA-256 校验失败: ${file}\n期望: ${expected}\n实际: ${actual}`);
}
console.log(`SHA-256 校验通过: ${file}`);
