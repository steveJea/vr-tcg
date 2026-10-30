# supabase SQL 안내

SQL Editor 에서 형님이 직접 실행하는 파일들. **같은 함수를 여러 파일이 다시 정의**하므로, 오래된 파일을 다시 돌리면 나중에 붙인 검사가 사라질 수 있어요.

- `schema.sql`: 예전 통합본. **다시 돌리지 마세요 (최신 아님)**.
- 실제 DB 상태 확인: `audit_live.sql` (읽기 전용) 결과의 함수 본문 md5 로 확인.
- 아래 순서·표는 git 에 파일이 추가된 순서로 **추정**한 것 (같은 날 여러 파일이면 이름순).

## 실행 순서 (추가된 순서)

1. `story.sql` (2026-10-17)
2. `gacha.sql` (2026-10-17) — ⚠ 일부 함수 최신 아님
3. `story_server.sql` (2026-10-17) — ⚠ 일부 함수 최신 아님
4. `story_levels.sql` (2026-10-17) — ⚠ 일부 함수 최신 아님
5. `story_min_battle.sql` (2026-10-17)
6. `story_level_stats.sql` (2026-10-17) — ⚠ 일부 함수 최신 아님
7. `story_merge.sql` (2026-10-17) — ⚠ 일부 함수 최신 아님
8. `story_ch2.sql` (2026-10-17)
9. `story_statpt.sql` (2026-10-17)
10. `story_gacha.sql` (2026-10-17)
11. `story_leader_lock.sql` (2026-10-18) — ⚠ 일부 함수 최신 아님
12. `story_cards_1022.sql` (2026-10-22)
13. `admin.sql` (2026-10-22)
14. `quest.sql` (2026-10-22) — ⚠ 일부 함수 최신 아님
15. `phaseE_1.sql` (2026-10-22) — ⚠ 일부 함수 최신 아님
16. `phaseE_2.sql` (2026-10-22) — ⚠ 일부 함수 최신 아님
17. `phaseE_3.sql` (2026-10-22) — ⚠ 일부 함수 최신 아님
18. `phaseE_4.sql` (2026-10-22)
19. `phaseE_5.sql` (2026-10-22) — ⚠ 일부 함수 최신 아님
20. `quest_sweep.sql` (2026-10-22) — ⚠ 일부 함수 최신 아님
21. `gallery_owned.sql` (2026-10-22)
22. `gallery_register_new.sql` (2026-10-22)
23. `story_ch3.sql` (2026-10-22)
24. `phaseE_6.sql` (2026-10-22)
25. `story_ch4.sql` (2026-10-22)
26. `story_ch5.sql` (2026-10-22)
27. `player_xp_x3.sql` (2026-10-23)
28. `story_ch6.sql` (2026-10-23)
29. `tower_v2.sql` (2026-10-25)
30. `story_ch1_reward.sql` (2026-10-25) — ⚠ `_story_complete_phase_e0` 최신 아님 (story_block_exp.sql)
31. `cards_1025.sql` (2026-10-25)
32. `story_decks.sql` (2026-10-26) — ⚠ 일부 함수 최신 아님
33. `pvp.sql` (2026-10-26) — ⚠ 일부 함수 최신 아님
34. `story_ch7.sql` (2026-10-26)
35. `cards_1026.sql` (2026-10-26)
36. `grade_lr.sql` (2026-10-27)
37. `pvp_tier.sql` (2026-10-27) — ⚠ 일부 함수 최신 아님
38. `gem.sql` (2026-10-27)
39. `guild.sql` (2026-10-27) — ⚠ 일부 함수 최신 아님
40. `guild2.sql` (2026-10-27) — ⚠ 일부 함수 최신 아님
41. `guild3.sql` (2026-10-27) — ⚠ 일부 함수 최신 아님
42. `guild4.sql` (2026-10-27) — ⚠ 일부 함수 최신 아님
43. `manual_battle.sql` (2026-10-27)
44. `war_manual.sql` (2026-10-27)
45. `guild4_ui.sql` (2026-10-28)
46. `pvp_info_notices.sql` (2026-10-28)
47. `story_ch0.sql` (2026-10-28)
48. `story_ch0_pull.sql` (2026-10-28)
49. `gear_v1.sql` (2026-10-28) — ⚠ 일부 함수 최신 아님
50. `gear_snap.sql` (2026-10-28)
51. `gear_drops.sql` (2026-10-28) — ⚠ 일부 함수 최신 아님
52. `gear_craft.sql` (2026-10-28)
53. `gear_sigil.sql` (2026-10-28) — ⚠ 일부 함수 최신 아님
54. `gear_sigil_story_off.sql` (2026-10-28)
55. `gear_shop.sql` (2026-10-28)
56. `trade_origin.sql` (2026-10-28) — ⚠ 일부 함수 최신 아님
57. `trade_origin_v2.sql` (2026-10-28)
58. `trade_drink.sql` (2026-10-28)
59. `trade_board.sql` (2026-10-28)
60. `trade_admin.sql` (2026-10-28)
61. `card_10435.sql` (2026-10-28)
62. `card_id_remap.sql` (2026-10-28)
63. `admin_reset.sql` (2026-10-29)
64. `story_ch8.sql` (2026-10-29)
65. `story_ch9_11.sql` (2026-10-29)
66. `story_ch0_p4.sql` (2026-10-29)
67. `guild_lend.sql` (2026-10-29)
68. `story_decks10.sql` (2026-10-29)
69. `guild_lend_notice.sql` (2026-10-29)
70. `story_stars.sql` (2026-10-29)
71. `blood_rebalance.sql` (2026-10-29)
72. `blood_rebalance_preview.sql` (2026-10-29) — 읽기 전용 미리보기
73. `blood_rebalance_refund.sql` (2026-10-29) — ⚠ 1회용 환급 (다시 돌려도 중복 지급 안 됨)
74. `story_level_gate.sql` (2026-10-29) — 챕터 입장 레벨 제한. ⚠ 이후 `phaseE_2.sql` 다시 돌리지 마세요
75. `lr_grade_align.sql` (2026-10-29)
76. `story_ch0_jieun.sql` (2026-10-29) — 챕0 강제 10회 영입 하지은 확정
77. `pvp_boss_league.sql` (2026-10-30) — PvP 보스리그 (mode boss). `_pvp_ok` 최신 = 이 파일
78. `story_ch0_p5.sql` (2026-10-30) — 챕0 P5 보스전 튜토리얼 (보상 주예린)
79. `story_ch8_boss_one.sql` (2026-10-30) — 챕8 P15 보스 1명 (enemy_count 1)
80. `story_block_exp.sql` (2026-10-30) — 막기 전투 EXP (`_story_complete_phase_e0` 최신; `story_ch1_reward.sql` 버전은 옛 것)

## 여러 파일에 정의된 함수 → 최신 정의 파일

| 함수 | 최신 파일 | 예전 정의 (다시 돌리면 덮어씀) |
|---|---|---|
| `_gear_grant` | `gear_drops.sql` | `gear_v1.sql` |
| `_gear_raid_claim_trg` | `gear_sigil.sql` | `gear_drops.sql` |
| `_guild_feed` | `guild2.sql` | `guild.sql` |
| `_lv_cost`, `_lv_cost_b`, `_lv_cost_g`, `card_cost_table` | `blood_rebalance.sql` | `phaseE_4.sql` |
| `_dismantle_yield`, `_merge_shard_base`, `_skill_soul_base` | `lr_grade_align.sql` | `phaseE_3.sql`, `phaseE_4.sql`, `phaseE_6.sql` |
| `_player_add_xp` | `guild.sql` | `phaseE_2.sql` |
| `_player_xp_need` | `player_xp_x3.sql` | `phaseE_2.sql` |
| `_pvp_extra` | `gem.sql` | `pvp.sql` |
| `_pvp_ok` | `pvp_boss_league.sql` | `pvp.sql` |
| `_pvp_grant` | `gem.sql` | `pvp_tier.sql` |
| `_pvp_snap` | `gear_snap.sql` | `pvp.sql` |
| `_raid_numbers` | `manual_battle.sql` | `guild3.sql` |
| `_sigil_story_roll` | `gear_sigil_story_off.sql` | `gear_sigil.sql` |
| `_story_cap` | `lr_grade_align.sql` | `schema.sql`, `story_levels.sql`, `story_merge.sql` |
| `_story_earned` | `story_server.sql` | `schema.sql` |
| `_story_feed_exp` | `lr_grade_align.sql` | `schema.sql`, `story_levels.sql` |
| `_story_find` | `story_merge.sql` | `schema.sql` |
| `_story_gain` | `story_level_stats.sql` | `schema.sql`, `story_levels.sql` |
| `_story_lock` | `story_statpt.sql` | `schema.sql`, `story_server.sql`, `story_merge.sql` |
| `_story_max_ex` | `lr_grade_align.sql` | `schema.sql`, `story_merge.sql` |
| `_story_migrate` | `story_merge.sql` | `schema.sql` |
| `_story_min_battle_secs` | `story_min_battle.sql` | `schema.sql`, `story_server.sql` |
| `_story_new_card` | `trade_origin_v2.sql` | `schema.sql`, `story_merge.sql`, `trade_origin.sql` |
| `_story_new_uid` | `story_merge.sql` | `schema.sql` |
| `_story_norm` | `story_merge.sql` | `schema.sql`, `story_levels.sql` |
| `_story_owned` | `story_merge.sql` | `schema.sql` |
| `_story_refund_stats` | `story_statpt.sql` | `schema.sql` |
| `_story_save` | `story_server.sql` | `schema.sql` |
| `_story_ticket_sync` | `story_gacha.sql` | `schema.sql` |
| `_story_used` | `story_levels.sql` | `schema.sql`, `story_server.sql` |
| `_war_lock` | `guild4_ui.sql` | `guild4.sql` |
| `_war_npc_deck` | `card_id_remap.sql` | `guild4.sql` |
| `_war_numbers` | `war_manual.sql` | `guild4.sql` |
| `admin_user_quest` | `tower_v2.sql` | `quest.sql` |
| `gallery_register` | `gallery_register_new.sql` | `schema.sql` |
| `guild_shop_buy` | `gear_shop.sql` | `guild.sql` |
| `mail_claim` | `trade_board.sql` | `gear_v1.sql`, `gear_drops.sql` |
| `pvp_rankings` | `pvp_tier.sql` | `pvp.sql` |
| `pvp_report` | `guild.sql` | `pvp.sql`, `pvp_tier.sql` |
| `pvp_start` | `gem.sql` | `pvp.sql` |
| `pvp_status` | `gem.sql` | `pvp.sql`, `pvp_tier.sql` |
| `quest_complete` | `tower_v2.sql` | `quest.sql`, `phaseE_3.sql` |
| `quest_start` | `tower_v2.sql` | `quest.sql` |
| `quest_status` | `tower_v2.sql` | `quest.sql` |
| `quest_sweep_complete` | `tower_v2.sql` | `quest_sweep.sql` |
| `quest_sweep_info` | `tower_v2.sql` | `quest_sweep.sql` |
| `quest_sweep_start` | `tower_v2.sql` | `quest_sweep.sql` |
| `story_allocate` | `story_statpt.sql` | `schema.sql`, `story_server.sql`, `story_levels.sql`, `story_merge.sql` |
| `story_choose_route` | `story_ch2.sql` | `schema.sql` |
| `story_choose_starter` | `story_merge.sql` | `schema.sql`, `story_server.sql` |
| `story_complete_phase` | `guild2.sql` | `schema.sql`, `story_server.sql`, `story_levels.sql`, `story_merge.sql`, `phaseE_2.sql`, `phaseE_3.sql` |
| `story_daily_draw` | `story_merge.sql` | `schema.sql`, `gacha.sql` |
| `story_discard` | `phaseE_3.sql` | `schema.sql`, `story_levels.sql`, `story_merge.sql` |
| `story_discard_many` | `phaseE_3.sql` | `schema.sql`, `story_level_stats.sql`, `story_merge.sql`, `story_leader_lock.sql` |
| `story_dismantle` | `phaseE_6.sql` | `phaseE_3.sql` |
| `story_mark_seen` | `story_ch0_pull.sql` | `schema.sql`, `story_server.sql` |
| `story_merge` | `phaseE_4.sql` | `schema.sql`, `story_merge.sql`, `story_leader_lock.sql` |
| `story_set_decks` | `story_decks10.sql` | `story_decks.sql` |
| `story_set_leader` | `story_leader_lock.sql` | `schema.sql` |
| `story_set_lock` | `story_decks.sql` | `schema.sql`, `story_leader_lock.sql` |
| `story_start_phase` | `story_level_gate.sql` | `schema.sql`, `story_server.sql`, `phaseE_2.sql` |
| `story_sweep` | `gear_sigil.sql` | `phaseE_5.sql`, `guild2.sql`, `gear_drops.sql` |
| `story_ticket_draw` | `story_ch0_jieun.sql` | `schema.sql`, `story_gacha.sql` |
| `story_tickets` | `story_gacha.sql` | `schema.sql` |
| `wallet_status` | `gem.sql` | `phaseE_1.sql` |

한 파일에만 정의된 함수 306개는 표에서 생략.


추가: `_player_unlock_level`, `_player_json` 도 이제 `story_level_gate.sql` 이 최신 (`phaseE_2.sql` 은 옛 버전).
