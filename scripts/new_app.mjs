// Clone the shell project into apps/<name> and rebrand it.
// Usage: node scripts/new_app.mjs <kebab-name> <applicationId> "<Display Name>"
// Example: node scripts/new_app.mjs echo-jot com.noobclaw.echojot "回声笔记"

import { cp, readFile, writeFile, rename, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [name, appId, displayName] = process.argv.slice(2);

if (!name || !appId || !displayName) {
  console.error('Usage: node scripts/new_app.mjs <kebab-name> <applicationId> "<Display Name>"');
  process.exit(1);
}
if (!/^[a-z][a-z0-9-]*$/.test(name)) {
  console.error(`Bad name "${name}": must be kebab-case`);
  process.exit(1);
}
if (!/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$/.test(appId)) {
  console.error(`Bad applicationId "${appId}": expected e.g. com.example.myapp`);
  process.exit(1);
}

const snake = name.replaceAll('-', '_'); // dart package name
const shellDir = path.join(ROOT, 'shell');
const destDir = path.join(ROOT, 'apps', name);

try {
  await stat(destDir);
  console.error(`apps/${name} already exists — refusing to overwrite`);
  process.exit(1);
} catch {}

// Copy the shell, skipping build junk.
const SKIP = new Set(['build', '.dart_tool', '.idea', '.gradle', 'node_modules']);
await cp(shellDir, destDir, {
  recursive: true,
  filter: (src) => !SKIP.has(path.basename(src)),
});

// Files that carry the shell's identity.
const SHELL_PKG = 'tool_shell';
const SHELL_APP_ID = 'com.noobclaw.tool_shell'; // must be replaced before SHELL_PKG (it contains it)
const SHELL_DISPLAY = 'Tool Shell';

const textFileRe = /\.(dart|yaml|yml|xml|gradle|kts|properties|json|md|html|plist|pbxproj|xcconfig|xcscheme|entitlements)$/i;

async function* walk(dir) {
  const { readdir } = await import('node:fs/promises');
  for (const ent of await readdir(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (!SKIP.has(ent.name)) yield* walk(p);
    } else {
      yield p;
    }
  }
}

let replaced = 0;
for await (const file of walk(destDir)) {
  if (!textFileRe.test(file) && path.basename(file) !== 'gradle.properties') continue;
  const before = await readFile(file, 'utf8');
  const after = before
    .replaceAll(SHELL_APP_ID, appId)
    .replaceAll(SHELL_PKG, snake)
    .replaceAll(SHELL_DISPLAY, displayName);
  if (after !== before) {
    await writeFile(file, after, 'utf8');
    replaced++;
  }
}

// Move the Android package directory to match the new applicationId.
const oldPkgPath = path.join(destDir, 'android', 'app', 'src', 'main', 'kotlin', ...SHELL_APP_ID.split('.'));
const newPkgPath = path.join(destDir, 'android', 'app', 'src', 'main', 'kotlin', ...appId.split('.'));
try {
  await stat(oldPkgPath);
  const { mkdir } = await import('node:fs/promises');
  await mkdir(path.dirname(newPkgPath), { recursive: true });
  await rename(oldPkgPath, newPkgPath);
  // Clean now-empty old package dirs.
  let dir = path.dirname(oldPkgPath);
  const kotlinRoot = path.join(destDir, 'android', 'app', 'src', 'main', 'kotlin');
  while (dir.startsWith(kotlinRoot) && dir !== kotlinRoot) {
    try { await rm(dir, { recursive: false }); } catch { break; }
    dir = path.dirname(dir);
  }
} catch {}

console.log(`Created apps/${name}`);
console.log(`  package:       ${snake}`);
console.log(`  applicationId: ${appId}`);
console.log(`  display name:  ${displayName}`);
console.log(`  files updated: ${replaced}`);
console.log(`\nNext: implement lib/tool/ in apps/${name}, then: flutter pub get && flutter build apk --release`);
