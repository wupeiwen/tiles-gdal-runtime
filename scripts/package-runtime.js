const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(process.argv[2]);
const manifest = {
  runtime: path.basename(root),
  gdal: process.env.GDAL_VERSION,
  proj: process.env.PROJ_VERSION,
  ...(process.env.MACOSX_DEPLOYMENT_TARGET
    ? { minimumMacOS: process.env.MACOSX_DEPLOYMENT_TARGET }
    : {}),
  builtAt: new Date().toISOString(),
  files: []
};
function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(file);
    else manifest.files.push(path.relative(root, file).replaceAll(path.sep, '/'));
  }
}
walk(root);
manifest.files.sort();
fs.writeFileSync(path.join(root, 'runtime-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
