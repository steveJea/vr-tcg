-- Staging only: 16-11을 진영 HP 보스전으로 바꿈 (최국선 10406 = 불사 보스).
-- mustKill 을 제거하고 type 을 boss 로. 윤진아 → [각성] 윤진아 revive 는 유지.
-- 엔진 코드 변경이 아니므로 phase7 해시 회전·함수 재배포 없음.
-- 여러 번 실행해도 안전. 운영 금지. system_identifier 7703759698107299042.
do $$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: 16-11 boss conversion is staging only; production forbidden';
  end if;

  update public.story_phase_config
     set type = 'boss'
   where chapter = 16 and phase = 11;

  if to_regclass('public.battle_story_defs_v2') is not null then
    update public.battle_story_defs_v2
       set definition = (coalesce(definition, '{}'::jsonb) || jsonb_build_object('type', 'boss'))
                        #- '{rules,mustKill}'
     where chapter = 16 and phase = 11 and variant = '';
    if not found then
      raise notice 'battle_story_defs_v2 16-11 row not found; skip catalog update';
    end if;
  else
    raise notice 'battle_story_defs_v2 not present; skip catalog update';
  end if;
end $$;
