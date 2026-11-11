import { build } from 'esbuild';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
const root = new URL('../', import.meta.url), check = process.argv.includes('--check');
const r = await build({
  absWorkingDir: root.pathname,
  entryPoints: ['tools/sweep-engine-entry.mjs'],
  bundle: true,
  platform: 'neutral',
  format: 'esm',
  target: 'es2022',
  loader: { '.csv': 'text' },
  write: false,
  metafile: true,
});
const h = createHash('sha256');
for (const f of Object.keys(r.metafile.inputs).sort()) h.update(f).update('\0').update(await readFile(new URL(f, root))).update('\0');
const version = h.digest('hex');
async function put(p, s) {
  const u = new URL(p, root);
  if (check) { if (await readFile(u, 'utf8') !== s) throw new Error('stale ' + p); }
  else { await mkdir(new URL('.', u), { recursive: true }); await writeFile(u, s); }
}
await put('supabase/functions/_shared/sweep-engine-v6.mjs', '// GENERATED: node tools/build_phase6_engine.mjs\nexport const ENGINE_VERSION=' + JSON.stringify(version) + ';\n' + r.outputFiles[0].text);
await put('js/sweep-engine-version.js', '// GENERATED\nexport const SWEEP_ENGINE_VERSION=' + JSON.stringify(version) + ';\n');
const sqlUrl = new URL('supabase/security_phase6_story_tower.sql', root);
const sql = await readFile(sqlUrl, 'utf8');
const nextSql = sql.replace(/values\s*\(\s*true\s*,\s*false\s*,\s*'[a-f0-9]{64}'\s*\)/, "values (true, false, '" + version + "')");
if (check && sql !== nextSql) throw new Error('stale SQL engine hash');
if (!check) await writeFile(sqlUrl, nextSql);
const questUrl = new URL('js/quest.js', root);
const quest = await readFile(questUrl, 'utf8');
const nextQuest = quest.replace(/const SWEEP_V6 = '[a-f0-9]{64}';/, "const SWEEP_V6 = '" + version + "';");
if (check && quest !== nextQuest) throw new Error('stale quest engine hash');
if (!check) await writeFile(questUrl, nextQuest);
console.log('Phase6 sweep engine ' + version);
