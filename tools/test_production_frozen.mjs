// Release 20261108 is shipped and frozen. Its behavioural test runs against the exact tree it was
// built from (config.sourceCommit), because later staging edits legitimately change the sources.
import {execFileSync} from 'node:child_process';
import {mkdtemp,rm,symlink,readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import os from 'node:os';
import path from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const {sourceCommit}=JSON.parse(await readFile(path.join(root,'tools/production/config.json'),'utf8'));
if(!/^[0-9a-f]{40}$/.test(sourceCommit||''))throw Error('config.sourceCommit must pin the shipped release commit');
const dir=await mkdtemp(path.join(os.tmpdir(),'vr-prod-1108-'));
execFileSync('git',['worktree','add','-q','--detach',dir,sourceCommit],{cwd:root});
try{
 await symlink(path.join(root,'node_modules'),path.join(dir,'node_modules'));
 for(const f of ['supabase/production/01_install.sql','supabase/production/functions/pvp-verify-v3/dashboard_single_file.ts','supabase/production/functions/guildbattle-verify-v4/dashboard_single_file.ts','supabase/production/functions/arcade-verify-v5/dashboard_single_file.ts'])
  if(await readFile(path.join(dir,f),'utf8')!==await readFile(path.join(root,f),'utf8'))throw Error('shipped 20261108 artifact changed after release: '+f);
 execFileSync(process.execPath,['tools/build_production_rollout.mjs','--check'],{cwd:dir,stdio:'inherit'});
 execFileSync(process.execPath,['tools/test_production_rollout.mjs'],{cwd:dir,stdio:'inherit'});
}finally{execFileSync('git',['worktree','remove','--force',dir],{cwd:root});await rm(dir,{recursive:true,force:true});}
