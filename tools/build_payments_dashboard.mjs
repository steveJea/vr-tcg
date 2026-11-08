import {readFile,writeFile} from 'node:fs/promises';
const dir=new URL('../supabase/functions/payments-confirm-v1/',import.meta.url);
const out='// Generated from handler.mjs; staging only; JWT verification ON.\n'+await readFile(new URL('handler.mjs',dir),'utf8')+'\nDeno.serve(createHandler(Deno.env.toObject()));\n';
if(process.argv.includes('--check')){if(out!==await readFile(new URL('dashboard_single_file.ts',dir),'utf8'))throw Error('payments dashboard drift');}else await writeFile(new URL('dashboard_single_file.ts',dir),out);
console.log('Payments dashboard single-file parity OK');
