// Test-only sandbox: actual generated dashboard entry, fake runtime env/network, no credentials.
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const source=readFileSync(new URL('../supabase/functions/pvp-verify-v3/dashboard_single_file.ts',import.meta.url),'utf8');
export function dashboardHandler(env,fetcher) {
 let captured;
 const context=vm.createContext({Response,Request,TextDecoder,Uint8Array,fetch:fetcher,Deno:{env:{toObject:()=>({...env})},serve:handler=>{captured=handler;}}});
 new vm.Script(source,{filename:'dashboard_single_file.ts'}).runInContext(context);
 if(typeof captured!=='function') throw Error('Dashboard did not register Deno.serve');
 return captured;
}
