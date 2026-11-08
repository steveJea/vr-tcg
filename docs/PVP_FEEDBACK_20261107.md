# PvP staging feedback (2026-11-07 KST)

> Historical report for commit `aeb9e19`. The subsequently approved level-stat
> fix DOES change the engine and requires an Edge + SQL policy rollout.
> Follow [PVP_LEVEL_STATS_20261107.md](PVP_LEVEL_STATS_20261107.md) for the current deployment instructions.

Base: `sec/phase3-pvp-20261107` (`70fd708`). Worktree: `/workspace/vrp-pvpfix`.

## Changes

1. The lobby AUTO/manual control has its own 24px gap below saved decks and an 8px gap above matchmaking.
2. View-battle batch attack is disabled when no ready card has a legal target, including an empty opposing field during the attacker's first two turns. Boss footer: **첫 2턴에는 보스를 공격할 수 없습니다.**
3. `autoTarget()` uses **null = legal base attack** and **undefined = blocked**. The old batch controller's `t == null` discarded both. Batch now emits the canonical `{k:'atk', i, t:-1}` for a base and rechecks targeting after each action. The attack presentation previously passed a null DOM target to `lunge()` for a base attack, which intentionally did nothing. It now targets the base ring, including actual redirected unit targets where applicable. Base hits are logged as damage, not incorrectly as an evade.
4. Active and passive MR videos now share one queue. The view stepper waits for queued clips before proceeding. Healthy playback has no 15s clip-length or 30s queue cutoff; completion is driven by `ended` or an explicit tap/SKIP. Missing/failed media still falls back; a 15s **no-progress** watchdog recovers stalled playback. Queue cancellation/cleanup prevents stale overlays after a battle.
5. Boss results show **opponent above / player below**, six cards per row. Previously, six fixed 20%-width thumbnails overflowed each half of a horizontal result row. Other result rows also allow proportional thumbnail shrinking.
6. Base-damage actions focus the opposing side before the hit; skill damage gets the same treatment. Boss instructions now correctly say to destroy **base HP**, rather than wipe every card. A verified boss victory labels the opposing result row **진영 파괴**. Legacy story completion checks cannot finish a canonical view session.
7. PvP deck-picker thumbnails have an 88px minimum (formerly 52px), larger level labels, card names and visible per-card cost. Added cost ascending/descending sort, inclusive numeric **cost ≤ N** filtering, and combined name search. Existing selection, leader/member restrictions, and league/cost-cap checks are preserved. Korean IME composition is retained while filtering.

## #6 investigation: actual rule, not a new winner rule

The browser and Edge function already use the same canonical `pvp-core.js` rules:

- Boss base HP starts at **800** on both sides.
- Attacker wins when the opposing **base HP is ≤ 0**, not when the guard portrait or every opposing member is destroyed. Direct hits, legal skill damage and overflow can destroy the base.
- The guard is **undying** while its base exists; seeing a living guard portrait at a base-destruction win is expected.
- Direct base attacks are locked for each attacking side's own first two turns; normal targeting restrictions still apply afterward.
- If neither base falls in **40 total turns**, the attacker loses (defender advantage); it is not a higher-HP judgement or draw.
- Official results/rating/rewards still come only from `pvp-verify-v3`, not the temporary local WIN animation.

No client/server verdict disagreement was reproduced. A real view-stepper fixture reaches WIN with **opponent base HP 0 and a living guard**, and its exact recorded batch transcript is accepted by the unchanged strict Edge verifier. The misleading wipe instruction, missing base lunge, off-screen base damage and permanently living guard portrait explain the apparent premature win. No original owner battle transcript was available to retrospectively identify that particular match.

## Verification / deployment

- `npm run check:staging`, `npm run test:staging`, `npm run build:staging`: PASS.
- `npm run test:security:phase1`, `phase2`, `phase3`: PASS (including 120 canonical browser/server fixtures and the standalone Dashboard handler SQL suite).
- New `tools/test_pvp_feedback.mjs` is part of `test:staging`: real view-stepper/manual-batch/AUTO/SKIP transcripts replay identically on the Edge bundle; targeting, media queue, 40s uninterrupted playback, skip/error/stall recovery, filters/IME wiring and result markup are covered.
- Tests use an offline DOM/media harness, not a fresh interactive PC Chrome staging session.
- Staging SQL bundle/parts/manifest were regenerated; hashes remain unchanged because SQL did not change. No new Tailwind utility classes were added; custom styles are in `css/pvp.css` and `css/story.css`, so `css/tw.css` requires no rebuild.
- **For historical commit `aeb9e19` ONLY, no SQL or Edge function changes/deployment were required.** The current follow-up requires both (see the linked rollout above). `dashboard_single_file.ts` was unchanged and passed its reproducibility check. Its engine version was `16b61abb1c42f29f063b9b84de938ef950363cdd2a23262cddf05c27c0c038a6`.

### Pre-existing issue — resolved by the approved follow-up

At the initial feedback commit, the optional legacy `node tools/test_pvp_core.mjs` failed its **레벨 스탯 반영** assertion both here and on untouched base `70fd708` in `/workspace/vrp-phase3`. In `snapCard()` a trailing `// EX는 별 색으로만` comment swallowed the `slv/ATK/HP/DEF/power` fields. The initial feedback commit intentionally did **not** change that canonical engine behavior or the engine hash: correcting it changes battle balance and requires a coordinated client/Edge/policy-hash update. This was not a regression introduced by these UI fixes and is now fixed in the approved follow-up (see the linked report above); the assertion now passes and is permanently included in the phase3 security suite.
