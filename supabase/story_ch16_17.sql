-- =====================================================================
-- 스토리 챕터 16 「젊은 베르테르의 슬픔」(12 페이즈) · 17 「폭풍의 언덕」(15 페이즈)
-- STAGING ONLY. Supabase SQL Editor 에 이 파일 전체를 붙여넣고 Run.
-- 여러 번 실행해도 안전. 삭제 없음. 운영 금지.
-- 필요 조건: story_ch15.sql 적용된 상태
-- 스탯 포인트는 시트대로 전 페이즈 3 (마지막 스토리 페이즈도 3).
-- P16-12 · P17-7 · P17-12 · P17-15 는 전투 없는 스토리 페이즈 (enemy_count=0, story_complete_scene).
-- 보유 마나·별점·출전 조건·각성 난입은 클라이언트(js/story-data-ch16.js · ch17.js)와
-- battle_story_defs_v2 (아래 카탈로그 insert) 에 있음.
-- 입장 레벨: 챕터 16 = 26, 챕터 17 = 27
-- =====================================================================
do $$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: story ch16/17 staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $$;

insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (16,1,'normal',3,null,5), (16,2,'normal',3,null,5), (16,3,'normal',3,null,5), (16,4,'normal',3,null,5),
  (16,5,'normal',3,null,5), (16,6,'normal',3,null,1), (16,7,'normal',3,null,5), (16,8,'normal',3,null,5),
  (16,9,'normal',3,null,5), (16,10,'normal',3,null,5), (16,11,'normal',3,null,6), (16,12,'normal',3,null,0),
  (17,1,'normal',3,null,5), (17,2,'normal',3,null,5), (17,3,'normal',3,null,5), (17,4,'normal',3,null,5),
  (17,5,'normal',3,null,5), (17,6,'normal',3,null,5), (17,7,'normal',3,null,0), (17,8,'normal',3,null,5),
  (17,9,'normal',3,null,5), (17,10,'normal',3,null,5), (17,11,'normal',3,null,5), (17,12,'normal',3,null,0),
  (17,13,'normal',3,null,5), (17,14,'normal',3,null,6), (17,15,'normal',3,null,0)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21
    when 'chapter_12' then 22 when 'chapter_13' then 23 when 'chapter_14' then 24 when 'chapter_15' then 25
    when 'chapter_16' then 26 when 'chapter_17' then 27
    else null end $$;

-- 전투 없는 스토리 페이즈 클리어 (enemy_count=0 만). 세션·리플레이 없이 진행도만 기록.
create or replace function public.story_complete_scene(p_chapter int, p_phase int) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  uid uuid := auth.uid(); d jsonb; cfg public.story_phase_config; cl jsonb; first boolean; prev int;
  need int; lv int; tickets jsonb;
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: story_complete_scene staging only';
  end if;
  if uid is null then raise exception 'not signed in'; end if;
  select * into cfg from public.story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null or coalesce(cfg.enemy_count, 0) <> 0 then raise exception 'invalid scene phase'; end if;
  need := public._player_unlock_level('chapter_' || p_chapter);
  begin
    lv := coalesce((public._player_json(uid)->>'level')::int, 1);
  exception when others then lv := 1; end;
  if need is not null and lv < need then raise exception 'level required: level %', need; end if;
  d := public._story_lock(uid);
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  if p_phase > 1 then
    prev := p_phase - 1;
    if not cl @> to_jsonb(prev) then raise exception 'previous phase not cleared'; end if;
  end if;
  first := not cl @> to_jsonb(p_phase);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
  end if;
  d := public._story_save(uid, d);
  begin tickets := public._story_ticket_sync(uid); exception when others then tickets := null; end;
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'chapter_reward', tickets, 'exp', '[]'::jsonb);
end $$;
revoke all on function public.story_complete_scene(int, int) from public, anon;
grant execute on function public.story_complete_scene(int, int) to authenticated;

-- 확인:
-- select chapter, phase, type, points, enemy_count from public.story_phase_config where chapter in (16,17) order by 1,2;
-- select public._player_unlock_level('chapter_16'), public._player_unlock_level('chapter_17');

-- battle_story_defs_v2 for chapters 16–17 (from tools/build_phase2_catalog.mjs)
do $cat$
begin
  if to_regclass('public.battle_story_defs_v2') is null then
    raise notice 'battle_story_defs_v2 not present; skip ch16/17 catalog';
    return;
  end if;
  execute $s0$insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
(16,1,'','{"no":1,"type":"normal","enemies":{"ids":["10514","10143","10144","10145","10146"],"boost":{"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10146":{"HP":101,"ATK":20,"DEF":16,"storyLv":45,"power":1393},"10514":{"HP":113,"ATK":19,"DEF":19,"storyLv":45,"power":3412}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10514","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,2,'','{"no":2,"type":"normal","enemies":{"ids":["10147","10143","10144","10145","10146"],"boost":{"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10146":{"HP":101,"ATK":20,"DEF":16,"storyLv":45,"power":1393},"10147":{"HP":115,"ATK":22,"DEF":17,"storyLv":45,"power":1553}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10147","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,3,'','{"no":3,"type":"normal","enemies":{"ids":["10155","10154","10155","10143","10144"],"boost":{"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10154":{"HP":101,"ATK":16,"DEF":12,"storyLv":45,"power":1257},"10155":{"HP":115,"ATK":17,"DEF":13,"storyLv":45,"power":1399}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10155","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,4,'','{"no":4,"type":"normal","enemies":{"ids":["10157","10145","10146","10156","10152"],"boost":{"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10146":{"HP":101,"ATK":20,"DEF":16,"storyLv":45,"power":1393},"10152":{"HP":534,"ATK":104,"DEF":104,"storyLv":45,"power":34342},"10156":{"HP":130,"ATK":19,"DEF":14,"storyLv":45,"power":1664},"10157":{"HP":144,"ATK":20,"DEF":16,"storyLv":45,"power":1831}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10157","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,5,'','{"no":5,"type":"normal","enemies":{"ids":["10158","10159","10160","10147","10148"],"boost":{"10147":{"HP":115,"ATK":22,"DEF":17,"storyLv":45,"power":1553},"10148":{"HP":169,"ATK":28,"DEF":19,"storyLv":45,"power":5275},"10158":{"HP":144,"ATK":22,"DEF":22,"storyLv":45,"power":1969},"10159":{"HP":188,"ATK":38,"DEF":30,"storyLv":45,"power":6526},"10160":{"HP":226,"ATK":47,"DEF":39,"storyLv":45,"power":8019}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10158","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,6,'','{"no":6,"type":"normal","enemies":{"ids":["10383"],"boost":{"10383":{"HP":966,"ATK":124,"DEF":138,"storyLv":45,"power":116253}}},"party":{"forced":["10123","10025","10183"],"mustLive":["10123","10025","10183"],"levels":{"10025":50,"10123":50,"10183":50},"battleLevels":{"10025":1,"10123":1,"10183":1},"solo":true},"bossId":"10383","mana":200,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,7,'','{"no":7,"type":"normal","enemies":{"ids":["10150","10149","10145","10144","10143"],"boost":{"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10145":{"HP":86,"ATK":19,"DEF":14,"storyLv":45,"power":1170},"10149":{"HP":207,"ATK":38,"DEF":28,"storyLv":45,"power":7240},"10150":{"HP":282,"ATK":56,"DEF":47,"storyLv":45,"power":10434}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10150","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,8,'','{"no":8,"type":"normal","enemies":{"ids":["10151","10161","10162","10163","10164"],"boost":{"10151":{"HP":464,"ATK":70,"DEF":70,"storyLv":45,"power":25251},"10161":{"HP":244,"ATK":51,"DEF":43,"storyLv":45,"power":9248},"10162":{"HP":282,"ATK":56,"DEF":49,"storyLv":45,"power":10515},"10163":{"HP":418,"ATK":70,"DEF":60,"storyLv":45,"power":23092},"10164":{"HP":441,"ATK":70,"DEF":60,"storyLv":45,"power":23844}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10151","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,9,'','{"no":9,"type":"normal","enemies":{"ids":["10152","10146","10165","10166","10167"],"boost":{"10146":{"HP":101,"ATK":20,"DEF":16,"storyLv":45,"power":1393},"10152":{"HP":534,"ATK":104,"DEF":104,"storyLv":45,"power":34342},"10165":{"HP":464,"ATK":70,"DEF":70,"storyLv":45,"power":25251},"10166":{"HP":487,"ATK":81,"DEF":81,"storyLv":45,"power":27586},"10167":{"HP":534,"ATK":93,"DEF":93,"storyLv":45,"power":30851}}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10152","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,10,'','{"no":10,"type":"normal","enemies":{"ids":["10025","10143","10144","10153","10154"],"boost":{"10025":{"HP":966,"ATK":152,"DEF":179,"storyLv":45,"power":85539},"10143":{"HP":72,"ATK":16,"DEF":12,"storyLv":45,"power":985},"10144":{"HP":72,"ATK":17,"DEF":13,"storyLv":45,"power":1018},"10153":{"HP":86,"ATK":14,"DEF":10,"storyLv":45,"power":1074},"10154":{"HP":101,"ATK":16,"DEF":12,"storyLv":45,"power":1257}},"levels":{"10025":2,"10143":2,"10144":2,"10153":2,"10154":2}},"party":{"forced":["10406"],"mustLive":["10406"],"levels":{"10406":40},"battleLevels":{"10406":1},"noFemale":true,"maxGrade":"SUPER RARE"},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,11,'','{"no":11,"type":"normal","enemies":{"ids":["10406","10290","10383","10097","10393","10306"],"boost":{"10097":{"HP":235,"ATK":30,"DEF":56,"storyLv":45,"power":10455},"10290":{"HP":179,"ATK":19,"DEF":21,"storyLv":45,"power":7682},"10306":{"HP":179,"ATK":30,"DEF":34,"storyLv":45,"power":7943},"10383":{"HP":966,"ATK":124,"DEF":138,"storyLv":45,"power":116253},"10393":{"HP":499,"ATK":70,"DEF":81,"storyLv":45,"power":38466},"10406":{"HP":580,"ATK":81,"DEF":81,"storyLv":45,"power":38309}}},"party":{"forced":["10200"],"mustLive":["10200"],"levels":{"10200":60},"battleLevels":{"10200":1},"noFemale":true},"bossId":"10406","mana":200,"rules":{"maxTurns":20,"revive":[{"id":"10290","become":"10291","delay":0,"storyLevel":100,"battleLevel":10}]},"hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(16,12,'','{"no":12,"type":"normal","hero":"10406","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none","party":{"forced":["10406"]}}'::jsonb),
(17,1,'','{"no":1,"type":"normal","enemies":{"ids":["10147","10146","10145","10144","10143"],"boost":{"10143":{"HP":70,"ATK":15,"DEF":11,"storyLv":40,"power":938},"10144":{"HP":70,"ATK":17,"DEF":13,"storyLv":40,"power":1003},"10145":{"HP":83,"ATK":18,"DEF":14,"storyLv":40,"power":1131},"10146":{"HP":97,"ATK":19,"DEF":15,"storyLv":40,"power":1328},"10147":{"HP":111,"ATK":21,"DEF":17,"storyLv":40,"power":1503}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"noMale":true,"maxGrade":"SUPER RARE"},"bossId":"10147","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,2,'','{"no":2,"type":"normal","enemies":{"ids":["10152","10149","10148","10160","10146"],"boost":{"10146":{"HP":97,"ATK":19,"DEF":15,"storyLv":40,"power":1328},"10148":{"HP":160,"ATK":27,"DEF":18,"storyLv":40,"power":5017},"10149":{"HP":196,"ATK":36,"DEF":27,"storyLv":40,"power":6877},"10152":{"HP":499,"ATK":98,"DEF":98,"storyLv":40,"power":32215},"10160":{"HP":214,"ATK":44,"DEF":37,"storyLv":40,"power":7573}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"noMale":true,"maxGrade":"SUPER RARE"},"bossId":"10152","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,3,'','{"no":3,"type":"normal","enemies":{"ids":["10025","10152","10152","10152","10152"],"boost":{"10025":{"HP":896,"ATK":141,"DEF":166,"storyLv":40,"power":79339},"10152":{"HP":499,"ATK":98,"DEF":98,"storyLv":40,"power":32215}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"noMale":true},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,4,'','{"no":4,"type":"normal","enemies":{"ids":["10158","10157","10156","10155","10154"],"boost":{"10154":{"HP":97,"ATK":15,"DEF":11,"storyLv":40,"power":1192},"10155":{"HP":111,"ATK":17,"DEF":13,"storyLv":40,"power":1368},"10156":{"HP":125,"ATK":18,"DEF":14,"storyLv":40,"power":1604},"10157":{"HP":139,"ATK":19,"DEF":15,"storyLv":40,"power":1754},"10158":{"HP":139,"ATK":21,"DEF":21,"storyLv":40,"power":1892}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10158","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,5,'','{"no":5,"type":"normal","enemies":{"ids":["10158","10149","10147","10146","10153"],"boost":{"10146":{"HP":97,"ATK":19,"DEF":15,"storyLv":40,"power":1328},"10147":{"HP":111,"ATK":21,"DEF":17,"storyLv":40,"power":1503},"10149":{"HP":196,"ATK":36,"DEF":27,"storyLv":40,"power":6877},"10153":{"HP":83,"ATK":14,"DEF":10,"storyLv":40,"power":1051},"10158":{"HP":139,"ATK":21,"DEF":21,"storyLv":40,"power":1892}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10158","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,6,'','{"no":6,"type":"normal","enemies":{"ids":["10161","10149","10149","10149","10149"],"boost":{"10149":{"HP":196,"ATK":36,"DEF":27,"storyLv":40,"power":6877},"10161":{"HP":231,"ATK":48,"DEF":41,"storyLv":40,"power":8753}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10161","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,7,'','{"no":7,"type":"normal","hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none","party":{"forced":["10307"]}}'::jsonb),
(17,8,'','{"no":8,"type":"normal","enemies":{"ids":["10025","10164","10164","10164","10164"],"boost":{"10025":{"HP":896,"ATK":141,"DEF":166,"storyLv":40,"power":79339},"10164":{"HP":412,"ATK":65,"DEF":56,"storyLv":40,"power":22242}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"SUPER RARE"},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,9,'','{"no":9,"type":"normal","enemies":{"ids":["10166","10166","10166","10166","10166"],"boost":{"10166":{"HP":456,"ATK":76,"DEF":76,"storyLv":40,"power":25853}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10166","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,10,'','{"no":10,"type":"normal","enemies":{"ids":["10025","10166","10166","10166","10166"],"boost":{"10025":{"HP":966,"ATK":152,"DEF":179,"storyLv":45,"power":85539},"10166":{"HP":487,"ATK":81,"DEF":81,"storyLv":45,"power":27586}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,11,'','{"no":11,"type":"normal","enemies":{"ids":["10025","10166","10166","10166","10166"],"boost":{"10025":{"HP":966,"ATK":152,"DEF":179,"storyLv":45,"power":85539},"10166":{"HP":487,"ATK":81,"DEF":81,"storyLv":45,"power":27586}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"HIGH RARE"},"bossId":"10025","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,12,'','{"no":12,"type":"normal","hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none","party":{"forced":["10307"]}}'::jsonb),
(17,13,'','{"no":13,"type":"normal","enemies":{"ids":["10200","10025","10151","10151","10151"],"boost":{"10025":{"HP":1036,"ATK":163,"DEF":192,"storyLv":50,"power":91739},"10151":{"HP":494,"ATK":74,"DEF":74,"storyLv":50,"power":26808},"10200":{"HP":1140,"ATK":207,"DEF":104,"storyLv":50,"power":98609}}},"party":{"forced":["10307"],"mustLive":["10307"],"levels":{"10307":45},"battleLevels":{"10307":1},"maxGrade":"SUPER RARE"},"bossId":"10200","mana":100,"rules":{"maxTurns":20},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,14,'','{"no":14,"type":"normal","enemies":{"ids":["10200","10025","10151","10151","10151","10151"],"boost":{"10025":{"HP":1036,"ATK":163,"DEF":192,"storyLv":50,"power":91739},"10151":{"HP":494,"ATK":74,"DEF":74,"storyLv":50,"power":26808},"10200":{"HP":1140,"ATK":207,"DEF":104,"storyLv":50,"power":98609}}},"party":{"forced":["10307"],"mustLive":["10311"],"levels":{"10307":45},"battleLevels":{"10307":1},"solo":true},"bossId":"10200","enemyFirst":true,"mana":200,"rules":{"maxTurns":20},"awaken":{"on":"10307","id":"10311","storyLevel":50,"battleLevel":1},"hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none"}'::jsonb),
(17,15,'','{"no":15,"type":"normal","hero":"10307","tutorial":false,"single":true,"loan":[],"loanLevel":{},"variantKind":"none","party":{"forced":["10307"]}}'::jsonb)
on conflict (chapter,phase,variant) do update set definition=excluded.definition;$s0$;
end $cat$;
-- 확인: select chapter, count(*) from public.battle_story_defs_v2 where chapter in (16,17) group by 1;

-- Phase7 engine_hash (direct-battle-core: 6적 필드 + 윤진아→[각성] 변환)
do $$
declare
  old_7 text := '3f9d8fd104b5ea50305841c1516780d03b1be6bdf1996d37a2d203ff6a5fbf9c';
  new_7 text := '0178e4a7e0fcdedce4815b75c2a9449782f93b3d7df1277d0943a532ff3659d2';
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: story ch16/17 staging only; production forbidden';
  end if;
  if to_regclass('public.battle_replay_policy_v7') is null then
    raise notice 'battle_replay_policy_v7 not present; skip hash update';
    return;
  end if;
  update public.battle_replay_policy_v7 set engine_hash=new_7 where singleton and engine_hash=old_7;
end $$;
