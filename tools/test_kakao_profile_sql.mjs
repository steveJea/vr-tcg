import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
const files=await Promise.all(['staging','production'].map(env=>readFile(new URL(`../supabase/kakao_profile_${env}.sql`,import.meta.url),'utf8')));
const bodies=files.map(s=>s.split('-- PROFILE_PATCH_BEGIN\n')[1].split('-- PROFILE_PATCH_END')[0]);assert.equal(bodies[0],bodies[1]);
for(const [i,sql]of files.entries()){
 assert.match(sql,/pg_catalog\.pg_control_system\(\).*is distinct from/);assert.match(sql,new RegExp(i?'7692130048193495360':'7703759698107299042'));
 assert.doesNotMatch(sql,/\b(?:drop|truncate|delete|grant|revoke)\b/i);
 const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);create table public.profiles(id uuid primary key references auth.users(id),nickname text not null check(char_length(nickname) between 1 and 20),avatar_url text,nick_set boolean not null default false);`);
 await db.exec(bodies[i]);await db.exec(`create trigger profiles_nick_guard before insert or update on profiles for each row execute function public._profiles_nick_guard();create function public.handle_new_user() returns trigger language plpgsql as $$begin insert into profiles(id,nickname)values(new.id,left(coalesce(new.raw_user_meta_data->>'name',new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1),'플레이어'),20));return new;end$$;create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();`);
 // PGlite has no real control file; replace only its catalog lookup with a deterministic fixture.
 const guarded=sql.replace('pg_catalog.pg_control_system()','public.test_control()');
 await db.exec(`create function public.test_control() returns table(system_identifier text) language sql as $$select 'WRONG'::text$$;`);
 await assert.rejects(db.exec(guarded),/STOP: .* only/);await db.exec('rollback');
 await db.exec(`create or replace function public.test_control() returns table(system_identifier text) language sql as $$select '${i?'7692130048193495360':'7703759698107299042'}'::text$$;`);
 await db.exec(guarded);await db.exec(guarded);
 for(const[email,meta]of [[null,{}],['',{}],['',{name:''}],['',{name:'카카오형'}],['g@example.com',{}]]){
  const id=crypto.randomUUID();await db.query('insert into auth.users values($1,$2,$3)',[id,email,JSON.stringify(meta)]);
  const row=(await db.query('select nickname,nick_set from profiles where id=$1',[id])).rows[0];assert.equal(row.nickname,meta.name||email?.split('@')[0]||'플레이어');assert.equal(row.nick_set,false);
  // Same blank fallback for the legacy admin-reset path; never set nick_set for it.
  await db.query("update profiles set nickname='',nick_set=true where id=$1",[id]);const reset=(await db.query('select nickname,nick_set from profiles where id=$1',[id])).rows[0];assert.deepEqual(reset,{nickname:'플레이어',nick_set:false});
 }
 const before=(await db.query('select * from profiles order by id')).rows;await db.exec(guarded);assert.deepEqual((await db.query('select * from profiles order by id')).rows,before,'rerun cannot rename/migrate existing accounts');
 await db.exec("begin;set local app.nick_rpc='1';");await assert.rejects(db.query("insert into profiles(id,nickname,nick_set)values(gen_random_uuid(),'',true)"),/violates check constraint/);await db.exec('rollback');
 await db.close();
}
console.log('Kakao profile SQL: staging/prod guards, signup null/empty email, legacy reset, nick_set rules, idempotence/no data changes OK');
