// Arcade entry cut-in rule (형님 2026-11-11): a card shows it if it has a dedicated scene
// (events.json entry.fx → data/fx/<id>_0.webp) or an entry voice (<id>_0), whatever its grade;
// otherwise only SR and above (SUPER/ULTRA/MYTHIC/LEGENDARY RARE) show the profile portrait.
// Every card that shows must resolve to a real image: local img/npc/<id>.webp for ids swapped by
// js/img-fallback.js, else vr-ideal-worldcup bt_img (proved by its locally generated img/thumb/<id>.webp).
import assert from 'node:assert/strict';
import {readFile,access} from 'node:fs/promises';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const exists=p=>access(new URL('../'+p,import.meta.url)).then(()=>true,()=>false);
const rows=(await rd('data/cards.csv')).trim().split('\n');const H=rows[0].split(',');const gi=H.indexOf('grade');
const cards=rows.slice(1).map(l=>{const c=l.split(',');return{id:c[0],grade:c[gi]};});
const fx=new Set((JSON.parse(await rd('data/events.json')).entry?.fx||[]).map(String));
const voice=new Set(JSON.parse(await rd('data/voice/index.json')));
const SR_UP=new Set(['SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE']);
const fb=await rd('js/img-fallback.js');
const override=new Set(fb.match(/const OVERRIDE = new Set\(\[([^\]]*)\]\)/)[1].match(/\d+/g));
const shows=c=>fx.has(c.id)||voice.has(c.id+'_0')||SR_UP.has(c.grade);
const show=cards.filter(shows),bad=[];
for(const {id} of show){
 const src=fx.has(id)?`data/fx/${id}_0.webp`:override.has(id)?`img/npc/${id}.webp`:null;
 if(src){if(!await exists(src))bad.push(id+' → '+src);continue;}
 if(!await exists(`img/thumb/${id}.webp`))bad.push(id+' → bt_img (no local thumb: original likely missing; add img/npc + OVERRIDE)');
}
assert.deepEqual(bad,[],'cards without a working entry image:\n'+bad.join('\n'));
const byId=Object.fromEntries(cards.map(c=>[c.id,c]));
for(const id of ['10511','10512','10513',...Array.from({length:13},(_,i)=>String(10520+i))]){
 assert(override.has(id)&&await exists(`img/npc/${id}.webp`),id+' new card portrait');
 assert.equal(shows(byId[id]),SR_UP.has(byId[id].grade)||voice.has(id+'_0')||fx.has(id),id+' new card follows the SR+ rule (entry voice/scene shows at any grade)');
}
assert(cards.some(c=>!shows(c)),'low-grade cards without scene/voice are skipped');
assert(cards.some(c=>!SR_UP.has(c.grade)&&voice.has(c.id+'_0')),'voiced low-grade cards still show (pre-#556 behaviour)');
const g=await rd('js/game.js');
assert.match(g,/const ENTRY_PORTRAIT_GRADES = new Set\(\['SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE'\]\);/);
assert.match(g,/return entryHas\(id\) \|\| !!voiceSet\?\.has\(`\$\{id\}_0`\) \|\| ENTRY_PORTRAIT_GRADES\.has\(card\.grade\);/);
assert.match(g,/if \(hasEntryCutIn\(u\.base \|\| u\.card\) && !S\.fxSeen\.has\(`entry:\$\{u\.uid\}`\)\)/,'onEnter gated by the rule');
assert.match(g,/if \(id == null \|\| !hasEntryCutIn\(c\)\) continue;/,'preload only cards that will show');
assert.match(g,/function entryImg\(id\) \{ return entryHas\(id\) \? `data\/fx\/\$\{id\}_0\.webp` : portraitFull\(id\); \}/);
assert.match(g,/const img = entryImg\(id\);\n  await entryReady\(img\);/,'decode before the animation starts');
assert.match(g,/primeBattleMedia\(story \? 0 : 10\)/,'arcade deck entry images preloaded');
const n=g=>cards.filter(c=>c.grade===g&&shows(c)).length;
console.log(`Entry images: ${show.length}/${cards.length} cards show a cut-in (SR ${n('SUPER RARE')}, UR ${n('ULTRA RARE')}, MR ${n('MYTHIC RARE')}, plus ${show.filter(c=>!SR_UP.has(c.grade)).length} below SR with scene/voice), all resolve; SR+ rule + preload/decode wired OK`);
