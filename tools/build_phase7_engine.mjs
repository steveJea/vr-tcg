import { build } from 'esbuild';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const check = process.argv.includes('--check');
const r = await build({
  absWorkingDir: root.pathname,
  entryPoints: ['tools/direct-engine-entry.mjs'],
  bundle: true,
  platform: 'neutral',
  format: 'esm',
  target: 'es2022',
  loader: { '.csv': 'text', '.json': 'json' },
  write: false,
  metafile: true,
});
const banned = ['js/rules.js', 'supabase/functions/_shared/sweep-engine-v6.mjs', 'supabase/functions/_shared/arcade-engine-v5.mjs', 'supabase/functions/_shared/pvp-engine-v3.mjs', 'supabase/functions/_shared/guildbattle-engine-v4.mjs'];
for (const file of banned) {
  const before = await readFile(new URL(file, root));
  const after = await readFile(new URL(file, root));
  if (!before.equals(after)) throw new Error('phase7 build mutated ' + file);
}
const text = '// GENERATED: node tools/build_phase7_engine.mjs\n' + r.outputFiles[0].text;
const out = new URL('supabase/functions/story-direct-verify-v7/engine.mjs', root);
if (check) {
  if (await readFile(out, 'utf8') !== text) throw new Error('stale direct engine; run node tools/build_phase7_engine.mjs');
} else {
  await mkdir(new URL('.', out), { recursive: true });
  await writeFile(out, text);
}
if (!text.includes('1dbdb45994799cdcf3db14bd6eb44689d35678a733774caffcfd9867df85685c')) throw new Error('direct engine lost the sweep hash');
console.log('Phase7 direct engine bytes ' + Buffer.byteLength(text));
