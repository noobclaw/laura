// Copies the playable web build (../web) into ./app so the packaged client is self-contained.
const fs = require('fs');
const path = require('path');
const src = path.join(__dirname, '..', 'web');
const dst = path.join(__dirname, 'app');
const skip = new Set(['tools', 'tests', 'node_modules', 'package.json', 'package-lock.json']);
fs.rmSync(dst, { recursive: true, force: true });
fs.mkdirSync(dst, { recursive: true });
for (const name of fs.readdirSync(src)) {
  if (skip.has(name)) continue;
  fs.cpSync(path.join(src, name), path.join(dst, name), { recursive: true });
}
if (!fs.existsSync(path.join(dst, 'index.html'))) { console.error('index.html missing'); process.exit(1); }
console.log('copied web build to', dst);
