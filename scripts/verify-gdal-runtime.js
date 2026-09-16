const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { locateRuntime, assertRuntime } = require('../src/raster/runtimeLocator.js');

const runtimeArg = process.argv[2];
const runtime = assertRuntime(locateRuntime(runtimeArg ? { env: { ...process.env, TILES_GDAL_RUNTIME: runtimeArg }, resourcesPath: '' } : {}));
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
