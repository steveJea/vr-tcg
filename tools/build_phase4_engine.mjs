import { build } from 'esbuild';
import { createHash } from 'node:crypto';
import { readFile,writeFile,mkdir } from 'node:fs/promises';
const root=new URL('../',import.meta.url), check=process.argv.includes('--check');
const r=await build({absWorkingDir:root.pathname,entryPoints:['tools/guildbattle-engine-entry.mjs'],bundle:true,platform:'neutral',format:'esm',target:'es2022',loader:{'.csv':'text'},write:false,metafile:true});
const h=createHash('sha256');for(const f of Object.keys(r.metafile.inputs).sort())h.update(f).update('\0').update(await readFile(new URL(f,root))).update('\0');
const version=h.digest('hex');
async function put(p,s){const u=new URL(p,root);if(check){if(await readFile(u,'utf8')!==s)throw Error('stale '+p);}else {await mkdir(new URL('.',u),{recursive:true});await writeFile(u,s);}}
await put('supabase/functions/_shared/guildbattle-engine-v4.mjs','// GENERATED: node tools/build_phase4_engine.mjs\nexport const ENGINE_VERSION='+JSON.stringify(version)+';\n'+r.outputFiles[0].text);
await put('js/guildbattle-engine-version.js','// GENERATED\nexport const GUILDBATTLE_ENGINE_VERSION='+JSON.stringify(version)+';\n');
const u=new URL('tools/phase4/head.sql',root),s=await readFile(u,'utf8'),t=s.replace(/values\(true,'[a-f0-9]{64}'\)/,"values(true,'"+version+"')");if(check&&s!==t)throw Error('stale SQL template engine hash');if(!check)await writeFile(u,t);
console.log('Phase4 engine '+version);
