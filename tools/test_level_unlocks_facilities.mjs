// Called by the full-stack unlock test. Simulates the actual pre-facility staging upgrade.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
export async function testFacilities({db,q,val,as}) {
 const uid='33333333-3333-4333-8333-333333333333';
 const rpc=(s,p=[])=>as(()=>val(s,p),uid);
 const reject=(s,p=[],pattern=/Lv20/)=>as(()=>assert.rejects(q(s,p),e=>pattern.test(e.message)),uid);
 const policy=JSON.parse(await rd('tools/unlocks/policy.json'));
 const camp=await rd('supabase/camp2.sql');
 for(const name of ['_camp_json','camp_forge_start','camp_dojo_unlock','camp_dojo_start']) {
  const ddl=camp.match(new RegExp('create or replace function public\\.'+name+'\\([\\s\\S]*?\\$\\$;'))?.[0];assert(ddl,name);await db.exec(ddl);
 }
 const oldLevels={...policy.features};delete oldLevels.forge;delete oldLevels.dojo;
 const oldIntros=policy.entries.filter(e=>e.key!=='facilities');
 const lit=x=>JSON.stringify(x).replaceAll("'","''");
 await db.exec(`create or replace function _unlock_levels() returns jsonb language sql immutable as $$select '${lit(oldLevels)}'::jsonb$$;
 create or replace function _unlock_intros() returns jsonb language sql immutable as $$select '${lit(oldIntros)}'::jsonb$$;`);
 await q("insert into auth.users(id,email) values($1,'facilities@example.invalid')",[uid]);
 await q('insert into player_state(user_id,level,xp) values($1,19,73)',[uid]);
 await q("insert into player_wallet(user_id,gold,soul,gem_free) values($1,100000,10000,10000)",[uid]);
 const skill=(await q('select m.card_id id,m.idx,m.unlock,p.grade from story_skill_meta m join story_card_pool p on p.id=m.card_id order by m.unlock,m.card_id,m.idx limit 1'))[0];assert(skill);
 const card=await val('select _story_new_card($1) v',[skill.id]);card.level=skill.unlock;card.skillLv={[skill.idx]:1};
 await q('insert into story_progress(user_id,data) values($1,$2)',[uid,JSON.stringify({owned:[card],starter:card.id})]);
 await rpc("select unlock_intro_claim('pvp_hr') v");await rpc('select camp_status() v');
 const snapshot=async()=>{
  const data={};for(const table of ['player_state','player_wallet','story_progress','camp_state','camp_slots','camp_jobs','unlock_intro_receipts','player_gear_meta']) data[table]=await q(`select to_jsonb(t) data from ${table} t where user_id=$1 order by to_jsonb(t)::text`,[uid]);return data;
 };
 const helperDefs=()=>q("select proname,pg_get_functiondef(oid) def from pg_proc where pronamespace='public'::regnamespace and proname=any($1::text[]) order by proname",[['_camp_lv_need','_camp_lv_mult','_camp_lv_cost','_camp_settle','_camp_pending2','_camp_rate','_camp_forge_hours','_camp_dojo_cost','_camp_dojo_max','_camp_half']]);
 const before=await snapshot(),helpers=await helperDefs();
 const acls=await q("select oid,proacl::text from pg_proc where pronamespace='public'::regnamespace order by oid");
 const migration=await rd('supabase/level_unlocks_facilities_staging.sql');
 await assert.rejects(db.exec(migration),/STOP: facilities only staging/);await db.exec('rollback');
 assert.deepEqual(await snapshot(),before);
 const system=await val('select system_identifier::text v from pg_control_system()');
 const sql=migration.replaceAll("'7703759698107299042'",`'${system}'`);
 await db.exec(sql);await db.exec(sql);
 assert.deepEqual(await snapshot(),before,'upgrade never resets resources, jobs, training, XP or old intro receipts');
 assert.deepEqual(await helperDefs(),helpers,'all training/balance helpers unchanged');
 assert.deepEqual(await q("select oid,proacl::text from pg_proc where oid=any($1::oid[]) order by oid",[acls.map(x=>x.oid)]),acls,'upgrade retains all prior function ACLs/OIDs');
 assert.deepEqual(await val('select _unlock_levels() v'),policy.features);
 assert.equal((await val('select _unlock_intros() v')).filter(e=>e.key==='facilities').length,1);
 assert.equal(await val('select _camp_lv_need(3) v'),25);
 assert.equal(await val('select _camp_lv_mult(1) v'),'1.00');
 // Building Lv10 and paid dojo slots never bypass account Lv20.
 await q('update camp_state set camp_lv=10,dojo_slots=2 where user_id=$1',[uid]);
 await reject('select camp_forge_start(null)');await reject('select camp_dojo_unlock()');await reject('select camp_dojo_start(1,$1,$2)',[card.uid,skill.idx]);
 await reject("select unlock_intro_claim('facilities')",[],/intro locked/);
 await q('update camp_state set camp_lv=1,dojo_slots=0 where user_id=$1',[uid]);
 await q('update player_state set level=20 where user_id=$1',[uid]);
 let status=await rpc('select camp_status() v');
 assert.equal(status.camp_lv,1);assert.equal(Number(status.mult),1);assert.equal(status.forge_open,true);assert.equal(status.dojo_open,true);
 assert.equal(status.forge_account_level,20);assert.equal(status.dojo_account_level,20);
 // Building Lv3 still needs account Lv25. Facilities do not accelerate building upgrades.
 await q('update camp_state set camp_lv=2 where user_id=$1',[uid]);await reject('select camp_levelup()',[],/need level 25/);await q('update camp_state set camp_lv=1 where user_id=$1',[uid]);
 // Actual forge job at camp Lv1: original half materials, duration and ownership checks.
 const gear=await val("select _gear_give_tier($1,1,'weapon','fixture',false) v",[uid]);assert(gear?.gear_id);
 await q('update player_wallet set gold=0 where user_id=$1',[uid]);
 await reject('select camp_forge_start($1)',[gear.gear_id],/not enough gold/);
 assert.equal(await val('select count(*)::int v from camp_jobs where user_id=$1',[uid]),0);
 await q('update player_wallet set gold=100000 where user_id=$1',[uid]);await val('select _gear_dust_add($1,10000) v',[uid]);
 const cost=(await q('select gold,dust from gear_enhance_cost where plus=1'))[0];
 const gold=await val('select gold v from player_wallet where user_id=$1',[uid]),dust=await val('select dust v from player_gear_meta where user_id=$1',[uid]);
 status=await rpc('select camp_forge_start($1) v',[gear.gear_id]);assert.equal(status.camp_lv,1);assert.equal(Number(status.mult),1);
 assert.equal(await val('select gold v from player_wallet where user_id=$1',[uid]),gold-Math.ceil(cost.gold/2));
 assert.equal(await val('select dust v from player_gear_meta where user_id=$1',[uid]),dust-Math.ceil(cost.dust/2));
 assert.equal(Number(await val("select extract(epoch from ends_at-started_at) v from camp_jobs where user_id=$1 and kind='forge'",[uid])),7200);
 await reject('select camp_forge_start($1)',[gear.gear_id],/forge busy/);
 // Dojo opening is still a real 1500/1000-gem purchase, not a free slot grant.
 await q('update player_wallet set gem_free=0,gem_paid=0 where user_id=$1',[uid]);
 await reject('select camp_dojo_unlock()',[],/not enough gem/);assert.equal((await rpc('select camp_status() v')).dojo_slots,0);
 await q('update player_wallet set gem_free=10000 where user_id=$1',[uid]);
 status=await rpc('select camp_dojo_unlock() v');assert.equal(status.dojo_slots,1);
 assert.equal(await val('select gem_free v from player_wallet where user_id=$1',[uid]),8500);
 status=await rpc('select camp_dojo_unlock() v');assert.equal(status.dojo_slots,2);
 assert.equal(await val('select gem_free v from player_wallet where user_id=$1',[uid]),7500);
 await reject('select camp_dojo_unlock()',[],/already open/);
 await reject('select camp_dojo_start(1,\'foreign-card\',$1)',[skill.idx],/not owned/);
 card.skillLv[skill.idx]=7;await q("update story_progress set data=jsonb_set(data,'{owned}',$1::jsonb) where user_id=$2",[JSON.stringify([card]),uid]);
 await reject('select camp_dojo_start(1,$1,$2)',[card.uid,skill.idx],/dojo max/);
 card.skillLv[skill.idx]=1;await q("update story_progress set data=jsonb_set(data,'{owned}',$1::jsonb) where user_id=$2",[JSON.stringify([card]),uid]);
 const skCost=await val('select _skill_cost($1,1) v',[skill.grade]);
 const wallet=(await q('select gold,soul from player_wallet where user_id=$1',[uid]))[0];
 status=await rpc('select camp_dojo_start(1,$1,$2) v',[card.uid,skill.idx]);assert.equal(status.camp_lv,1);assert.equal(Number(status.mult),1);
 const afterWallet=(await q('select gold,soul from player_wallet where user_id=$1',[uid]))[0];
 assert.equal(afterWallet.gold,wallet.gold-Math.ceil(skCost.gold/2));assert.equal(afterWallet.soul,wallet.soul-Math.ceil(skCost.soul/2));
 assert.equal(Number(await val("select extract(epoch from ends_at-started_at) v from camp_jobs where user_id=$1 and kind='dojo'",[uid])),14400);
 // The sheet's deferred 5000-gold intro is granted exactly once, with no EXP/material dependency.
 const rewardGold=await val('select gold v from player_wallet where user_id=$1',[uid]);
 await rpc("select unlock_intro_claim('facilities') v");await rpc("select unlock_intro_claim('facilities') v");
 assert.equal(await val('select gold v from player_wallet where user_id=$1',[uid]),rewardGold+5000);
 assert.equal(await val('select xp v from player_state where user_id=$1',[uid]),73);
 const completed=await snapshot();await db.exec(sql);assert.deepEqual(await snapshot(),completed,'reapplying small upgrade preserves active jobs and one-time rewards');
 assert.deepEqual(await helperDefs(),helpers);
 console.log('Lv20 facilities: real old-staging upgrade, Lv19 denial/Lv20 camp-Lv1 forge+dojo jobs, original prices/materials/times/caps, unchanged building/EXP gates, no resets, one-time intro, ACL/guard/idempotency: OK');
}
