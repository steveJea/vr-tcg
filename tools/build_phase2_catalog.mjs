// Trusted repository data -> server stage rules. No network, keys or live DB.
import {readFile,writeFile} from 'node:fs/promises';
import vm from 'node:vm';
import {parseCSV} from '../js/rules.js';
const root=new URL('../',import.meta.url), rd=p=>readFile(new URL(p,root),'utf8');
const html=await rd('index.html'), ctx=vm.createContext({window:{}});
for(const [,p] of html.matchAll(/src="(js\/story-data[^"?]*\.js)"/g)) vm.runInContext(await rd(p),ctx,{filename:p});
const D=ctx.window.STORY_DATA, rows=[];
const fields=['no','type','enemies','party','baseHp','bossId','enemyFirst','bossCdMinus','pool','mana','manaBonus','starTurns','starMana','loseClears','reserve','fullMp','mustSummon','rules','awaken','joinAlly','spare'];
for(const b of D.chapters) {
  const variants=[['',b],...Object.entries(b.byStarter||b.byRoute||{}).map(([k,o])=>[k,{...b,...o,hero:o.hero,phases:b.phases.map(p=>({...p,...o.phases?.[p.no]}))}])];
  for(const [variant,ch] of variants) for(const ph of ch.phases) {
    const def=Object.fromEntries(fields.filter(k=>ph[k]!==undefined).map(k=>[k,ph[k]]));
    Object.assign(def,{hero:ch.hero||null,tutorial:!!ch.tutorial,single:!!ch.single,loan:ch.loan||[],loanLevel:ch.loanLevel||{},variantKind:b.byStarter?'starter':b.byRoute?'route':'none'});
    if(!def.party) def.party=ch.hero?{forced:[ch.hero]}:{};
    rows.push(`(${ch.id},${ph.no},'${variant}','${JSON.stringify(def).replaceAll("'","''")}'::jsonb)`);
  }
}
const meta=[...parseCSV(await rd('data/cards.csv')),...parseCSV(await rd('data/npc_cards.csv'))];
const metaSql=meta.map(c=>`insert into public.battle_card_meta_v2(id,definition) values ('${c.id}','${JSON.stringify(Object.fromEntries(['class','gender','MOR','cost','grade'].map(k=>[k,c[k]]))).replaceAll("'","''")}') on conflict(id) do update set definition=excluded.definition;`).join('\n');
const batches=[]; for(let i=0;i<rows.length;i+=30) batches.push('insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values\n'+rows.slice(i,i+30).join(',\n')+'\non conflict (chapter,phase,variant) do update set definition=excluded.definition;');
const block='-- BEGIN GENERATED PHASE2 STORY\n'+batches.join('\n')+'\n'+metaSql+'\n-- END GENERATED PHASE2 STORY';
const path=new URL('supabase/security_phase2_clears.sql',root), old=await readFile(path,'utf8');
const out=old.replace(/-- BEGIN GENERATED PHASE2 STORY[\s\S]*?-- END GENERATED PHASE2 STORY/,block);
if(process.argv.includes('--check')) {if(old!==out) throw new Error('Phase 2 stage catalog stale: node tools/build_phase2_catalog.mjs');}
else await writeFile(path,out);
console.log(`Phase 2 story catalog: ${rows.length} stage variants`);
