import { build } from 'esbuild';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
const out = 'supabase/functions/_shared/pvp-engine-v3.mjs';
const result = await build({ absWorkingDir: root, entryPoints: ['tools/pvp-engine-entry.mjs'], bundle: true, platform: 'neutral', format: 'esm', target: 'es2022', loader: { '.csv': 'text' }, write: false, metafile: true });
const inputs = Object.keys(result.metafile.inputs).sort();
const hash = createHash('sha256');
for (const f of inputs) hash.update(f).update('\0').update(await readFile(path.join(root, f))).update('\0');
const version = hash.digest('hex');
const content = '// GENERATED: node tools/build_phase3_engine.mjs (do not edit).\nexport const ENGINE_VERSION = '+JSON.stringify(version)+';\n'+result.outputFiles[0].text;
const browserPath = path.join(root,'js/pvp-engine-version.js');
const browser = '// GENERATED: node tools/build_phase3_engine.mjs\nexport const PVP_ENGINE_VERSION = '+JSON.stringify(version)+';\n';
const policyPath = path.join(root, 'supabase/security_phase3_pvp.sql');
const policy = await readFile(policyPath, 'utf8');
if ((policy.match(/values\(true,'[a-f0-9]{64}'\)/g) || []).length !== 1) throw new Error('phase3 policy engine-hash marker missing/ambiguous');
const next = policy.replace(/engine_hash = '[a-f0-9]{64}'/g, "engine_hash = '"+version+"'").replace(/values\(true,'[a-f0-9]{64}'\)/g, "values(true,'"+version+"')");
const upgradePath = path.join(root, 'supabase/security_phase3_pvp_level_stats.sql');
const upgrade = await readFile(upgradePath, 'utf8');
const upgradeMarker = /new_hash constant text := '[a-f0-9]{64}';/g;
if ((upgrade.match(upgradeMarker) || []).length !== 1) throw new Error('level-stat upgrade hash marker missing/ambiguous');
const nextUpgrade = upgrade.replace(upgradeMarker, "new_hash constant text := '"+version+"';");
if (process.argv.includes('--check')) {
  if (await readFile(path.join(root,out),'utf8') !== content || policy !== next || upgrade !== nextUpgrade || await readFile(browserPath,'utf8') !== browser) throw new Error('stale phase3 engine / SQL hash; regenerate');
} else {
  await mkdir(path.dirname(path.join(root,out)),{recursive:true});
  await writeFile(path.join(root,out),content); await writeFile(policyPath,next); await writeFile(browserPath,browser); await writeFile(upgradePath,nextUpgrade);
}
console.log('Phase3 engine '+version+' ('+inputs.length+' canonical inputs)');
