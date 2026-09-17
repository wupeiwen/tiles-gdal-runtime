const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const runtimeArg = process.argv[2];
if (!runtimeArg) throw new Error('用法: node verify-gdal-runtime.js <runtime-directory>');
const root = path.resolve(runtimeArg);
const executable = process.platform === 'win32' ? '.exe' : '';
const runtime = {
  root,
  binDir: path.join(root, 'bin'),
  libDir: path.join(root, 'lib'),
  gdalData: path.join(root, 'share', 'gdal'),
  projLib: path.join(root, 'share', 'proj'),
  binaries: { gdal: path.join(root, 'bin', `gdal${executable}`) }
};
for (const directory of [runtime.root, runtime.binDir, runtime.libDir, runtime.gdalData, runtime.projLib]) {
  if (!fs.existsSync(directory)) throw new Error(`GDAL runtime 缺少目录: ${directory}`);
}
if (!fs.existsSync(runtime.binaries.gdal)) throw new Error(`GDAL runtime 缺少可执行文件: ${runtime.binaries.gdal}`);
const env = { ...process.env, GDAL_DATA: runtime.gdalData, PROJ_LIB: runtime.projLib, PATH: `${runtime.binDir}${path.delimiter}${runtime.libDir}${path.delimiter}${process.env.PATH || ''}` };
if (process.platform === 'linux') env.LD_LIBRARY_PATH = `${runtime.libDir}${path.delimiter}${process.env.LD_LIBRARY_PATH || ''}`;
if (process.platform === 'darwin') env.DYLD_LIBRARY_PATH = `${runtime.libDir}${path.delimiter}${process.env.DYLD_LIBRARY_PATH || ''}`;

function run(command, args) {
  const result = spawnSync(command, args, { env, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`${command} ${args.join(' ')}\n${result.stderr || result.stdout}`);
  return result.stdout;
}

const version = run(runtime.binaries.gdal, ['--version']).trim();
const drivers = JSON.parse(run(runtime.binaries.gdal, ['raster', '--drivers']));
const serializedDrivers = JSON.stringify(drivers);
for (const driver of ['GTiff', 'VRT', 'PNG']) {
  if (!serializedDrivers.includes(driver)) throw new Error(`GDAL runtime 缺少 ${driver} driver`);
}
const tileHelp = run(runtime.binaries.gdal, ['raster', 'tile', '--help']);
for (const option of ['WebMercatorQuad', '--convention', '--skip-blank', '--output-nodata']) {
  if (!tileHelp.includes(option)) throw new Error(`gdal raster tile 缺少能力: ${option}`);
}
if (!fs.existsSync(path.join(runtime.projLib, 'proj.db'))) throw new Error('PROJ runtime 缺少 proj.db');
const probeRoot = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'tiles-gdal-runtime-'));
try {
  const input = path.join(probeRoot, 'probe.tif');
  const output = path.join(probeRoot, 'tiles');
  run(runtime.binaries.gdal, ['raster', 'create', '-o', input, '--output-format', 'GTiff', '--size', '32,32', '--band-count', '4', '--burn', '64', '--burn', '128', '--burn', '192', '--burn', '255', '--crs', 'EPSG:3857', '--bbox=-1000,-1000,1000,1000']);
  const zstdInput = path.join(probeRoot, 'probe-zstd.tif');
  run(runtime.binaries.gdal, ['raster', 'create', '-o', zstdInput, '--output-format', 'GTiff', '--creation-option', 'COMPRESS=ZSTD', '--size', '8,8', '--band-count', '1', '--burn', '1', '--crs', 'EPSG:3857', '--bbox=-1000,-1000,1000,1000']);
  const zstdInfo = JSON.parse(run(runtime.binaries.gdal, ['info', '--json', zstdInput]));
  const compression = zstdInfo.metadata?.IMAGE_STRUCTURE?.COMPRESSION
    || zstdInfo.bands?.find((band) => band.metadata?.IMAGE_STRUCTURE?.COMPRESSION)?.metadata?.IMAGE_STRUCTURE?.COMPRESSION;
  if (compression !== 'ZSTD') throw new Error(`GDAL runtime 未启用 ZSTD 压缩（实际: ${compression || '未知'}）`);
  run(runtime.binaries.gdal, ['raster', 'tile', '-i', input, '-o', output, '--tiling-scheme', 'WebMercatorQuad', '--min-zoom', '0', '--max-zoom', '0', '--convention', 'xyz', '--add-alpha', '--webviewer', 'none']);
  const pngs = [];
  function collect(directory) { for (const entry of fs.readdirSync(directory, { withFileTypes: true })) { const file = path.join(directory, entry.name); if (entry.isDirectory()) collect(file); else if (file.endsWith('.png')) pngs.push(file); } }
  collect(output);
  if (!pngs.length) throw new Error('GDAL runtime 冒烟测试未生成 PNG 瓦片');
} finally {
  fs.rmSync(probeRoot, { recursive: true, force: true });
}
console.log(`GDAL runtime 验证通过: ${version}`);
console.log(runtime.root);
