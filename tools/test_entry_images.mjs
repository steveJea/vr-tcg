// Arcade entry cut-in: every card in data/cards.csv must resolve to a real image.
// Dedicated scene (events.json entry.fx → data/fx/<id>_0.webp), else the profile portrait:
// local img/npc/<id>.webp for ids swapped by js/img-fallback.js, otherwise vr-ideal-worldcup bt_img
// (its local img/thumb/<id>.webp is generated from that original, so it proves the original exists).
import assert from 'node:assert/strict';
import {readFile,access} from 'node:fs/promises';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const exists=p=>access(new URL('../'+p,import.meta.url)).then(()=>true,()=>false);
const ids=(await rd('data/cards.csv')).trim().split('\n').slice(1).map(l=>l.split(',')[0]);
const fx=new Set((JSON.parse(await rd('data/events.json')).entry?.fx||[]).map(String));
const fb=await rd('js/img-fallback.js');
const override=new Set(fb.match(/const OVERRIDE = new Set\(\[([^\]]*)\]\)/)[1].match(/\d+/g));
const bad=[];
for(const id of ids){
 const src=fx.has(id)?`data/fx/${id}_0.webp`:override.has(id)?`img/npc/${id}.webp`:null;
 if(src){if(!await exists(src))bad.push(id+' → '+src);continue;}
 if(!await exists(`img/thumb/${id}.webp`))bad.push(id+' → bt_img (no local thumb: original likely missing; add img/npc + OVERRIDE)');
}
assert.deepEqual(bad,[],'cards without a working entry image:\n'+bad.join('\n'));
for(const id of ['10511','10512','10513',...Array.from({length:13},(_,i)=>String(10520+i))])assert(override.has(id)&&await exists(`img/npc/${id}.webp`),id+' new card portrait');
const g=await rd('js/game.js');
assert(!/voiceSet\?\.has\(`\$\{id\}_0`\) \|\| \(EVENTS\.entry\.fx/.test(g),'entry cut-in no longer requires an entry voice');
assert.match(g,/function entryImg\(id\) \{ return entryHas\(id\) \? `data\/fx\/\$\{id\}_0\.webp` : portraitFull\(id\); \}/);
assert.match(g,/const img = entryImg\(id\);\n  await entryReady\(img\);/,'decode before the animation starts');
assert.match(g,/primeBattleMedia\(story \? 0 : 10\)/,'arcade deck entry images preloaded');
assert.match(g,/if \(entryAhead && !S\.story\) warmEntries\(/);
console.log(`Entry images: ${ids.length} cards resolve (${fx.size} dedicated, ${ids.filter(i=>!fx.has(i)&&override.has(i)).length} local portraits, rest bt_img), preload + decode wired OK`);
