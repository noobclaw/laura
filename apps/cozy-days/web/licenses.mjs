import {
  readFile,
  writeFile,
  readdir,
  access
} from 'node:fs/promises';
import {
  dirname,
  join,
  relative
} from 'node:path';
const fallback = JSON.parse(await readFile('third-party/license-sources.json', 'utf8'));
const meta = JSON.parse(await readFile('build/metafile.json', 'utf8')),
  packages = new Map();
const bundled = new Set(Object.values(meta.outputs).flatMap(output => Object.entries(output.inputs ?? {}).filter(([, v]) => v.bytesInOutput > 0).map(([path]) => path)));
for (const input of bundled) {
  if (!input.startsWith('node_modules/')) continue;
  let root = dirname(input);
  while (root !== '.') {
    try {
      const entry = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
      if (entry.name) break;
    } catch {}
    root = dirname(root);
  }
  if (root === '.' || packages.has(root)) continue;
  const spec = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
  const files = (await readdir(root)).filter(file => /^(license|licence|copying|notice)([.\-_]|$)/i.test(file));
  const notices = [];
  for (const file of files) {
    try {
      notices.push({
        file,
        text: await readFile(join(root, file), 'utf8')
      });
    } catch {}
  }
  if (!notices.length && fallback[spec.name]) {
    const source = fallback[spec.name];
    notices.push({
      file: source.file,
      text: `Source: ${source.url} (checked ${source.checked})\n` + await readFile(`third-party/licenses/${source.file}`, 'utf8')
    });
  }
  packages.set(root, {
    name: spec.name,
    version: spec.version,
    license: spec.license ?? 'See bundled notices',
    notices
  });
}
const values = [...packages.values()].sort((a, b) => a.name.localeCompare(b.name));
const text = 'Third-party runtime and bundled code notices\nGenerated from the local production bundle.\n\n' + values.map(p => `${'='.repeat(72)}\n${p.name} ${p.version}\nLicense: ${typeof p.license==='string'?p.license:JSON.stringify(p.license)}\n\n${p.notices.map(n=>`--- ${n.file} ---\n${n.text}`).join('\n')}\n`).join('\n');
await writeFile('THIRD_PARTY_NOTICES.txt', text);
await writeFile('build/licenses.json', JSON.stringify(values.map(({
  notices,
  ...p
}) => ({
  ...p,
  files: notices.map(n => n.file)
})), null, 2));
console.log(JSON.stringify({
  packages: values.length,
  missingLicenseText: values.filter(p => !p.notices.length).map(p => p.name)
}));
