import {
  build
} from 'esbuild';
import {
  readFile,
  writeFile,
  mkdir,
  readdir,
  unlink
} from 'node:fs/promises';
import {
  createHash
} from 'node:crypto';
const result = await build({
  entryPoints: ['examples/play.js'],
  outdir: 'build',
  entryNames: 'game-[hash]',
  chunkNames: 'shared-[hash]',
  bundle: true,
  splitting: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  minify: true,
  metafile: true,
  legalComments: 'external',
  define: {
    'process.env.NODE_ENV': '"production"'
  },
  logLevel: 'info'
});
const entry = Object.entries(result.metafile.outputs).find(([, value]) => value.entryPoint === 'examples/play.js')[0];
const css = await readFile('examples/game.css');
const hash = createHash('sha256').update(css).digest('hex').slice(0, 12);
let page = await readFile('index.html', 'utf8');
page = page.replace(/<script type="module" src="[^"]+"><\/script>/, `<script type="module" src="./${entry}"></script>`);
page = page.replace(/href="\.\/examples\/(?:play|game)\.css[^\"]*"/, `href="./examples/game.css?v=${hash}"`);
await writeFile('index.html', page);
await mkdir('build', {
  recursive: true
});
await writeFile('build/metafile.json', JSON.stringify(result.metafile, null, 2));
console.log(`Local browser entry: ${entry}`);

const keep = new Set(Object.keys(result.metafile.outputs).map(path => path.replace(/^build\//, '')));
for (const file of [...keep]) keep.add(`${file}.LEGAL.txt`);
for (const file of await readdir('build'))
  if (/^(game|shared)-/.test(file) && !keep.has(file)) await unlink(`build/${file}`);

await import('./licenses.mjs');
