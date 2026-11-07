# PvP progression stats: impact, fix and staging rollout

## Confirmed impact / introduction

- Introduced by **28f7d6c2df5cdedf238d4e54b4872e0f2237c3da**, PR **#382**, **2026-11-01 16:51:28 KST** (`보유 인재: EX 별 규칙 + 이름표 [EX] 제거`). The parent revision contains working stat assignments; this commit replaced the EX name prefix with an inline `//` comment that accidentally consumed the remaining fields on that line. This is the introduction/merge time, not a proven deployment time.
- Public production `https://tcg.mbbs.kr/js/pvp-core.js` was read on **2026-11-07 19:20 KST**: HTTP 200, SHA-256 `67f326d357318870a78ec019b511f57fed883a8d3347f7683d8a936fa6a9e05f`, and it still contains the faulty comment. Production has no `pvp-engine-version.js` (404), consistent with phase3 being staging-only. Public staging script reads returned HTTP 403; its deployed source could not be directly inspected. The local phase3 source and its actual bundled verifier were reproduced offline; no authenticated game account or live DB was accessed.
- This affects **real combat**, not only the displayed level: both attacker and defender snapshots pass through `snapCard()` in AUTO and manual PvP, in open/HR and 1v1/3v3/boss modes. The phase3 Edge bundle inherited the same bug, so browser/server agreed on the **same wrong stats**.
- `level`, merge bonus `exb`, allocated `boost` points, progression-scaled `power`, `slv` and EX display metadata were omitted. `slv` is also used by transformations/summons. `skillLv` objects, gear and sigils were still passed through; their existing effects were not all disabled. Gear was incorrectly applied to unscaled base stats. EX stage itself is display/level-cap metadata; its percentage benefit is `exb`, not an extra EX-stage multiplier.
- Proof using card **10137 (복광준)** with canonical data: Lv1 was ATK/HP/DEF **48/245/25**. Even Lv40, EX3, EX bonus 20%, points ATK9/HP8/DEF7 incorrectly remained **48/245/25**. The corrected result is **132/670/71**. Before the fix, changing only those progression fields for either side produced identical old-Edge outcomes in all **12** combinations of role × AUTO/manual × mode. After the fix, all 12 chosen cases change combat results and still replay identically between browser and Edge.
- Other users of this shared function (friend battles, raid and war) also receive the corrected progression; story/tower use their separate `boosted()` implementation and were not broken by this particular comment.
- No player progression was erased from storage. Counts of affected players/matches and any retrospective compensation cannot be established without a separate historical DB audit. Past official receipts, ratings and rewards are deliberately not recomputed.

## Implementation

`js/pvp-core.js` now puts every returned field on its own line, preserving the original grade-rate/rounding/EX-bonus/diminishing-point formulas and gear application order. The no-EX-name-prefix change is preserved. Generated browser engine version, `_shared/pvp-engine-v3.mjs` and `pvp-verify-v3/dashboard_single_file.ts` are rebuilt together.

Old engine: `16b61abb1c42f29f063b9b84de938ef950363cdd2a23262cddf05c27c0c038a6`

New engine: `ff3c2c77c26429a0fbf85f1d1ab73edb882af342a152727c1aed64c49160dd2a`

The Edge handler never replays an old transcript with the new engine. For an old session it delegates only to SQL with no computed result: SQL rejects an active hash mismatch, or idempotently closes an expired session as the already-reserved forfeit. Settled receipts remain readable/retryable unchanged. The browser clears a saved old-version start request after refresh, but retains same-version request IDs for retries.

## SQL: policy change required; snapshot backfill NOT required

- `_pvp_snap` in `gear_snap.sql` already preserves `level/ex/exb/boost/skillLv` plus server-read gear/sigil metadata.
- Phase3 `_pvp_decks_v3` refreshes **both sides** from `story_progress` and saved deck UIDs at match start. It does not trust the possibly stale `pvp_decks.snap` defense cache. Attempt snapshots then remain frozen for replay.
- PGlite regressions change both players' progression **after saving decks** and prove attacker/defender snapshots are fresh for all modes and manual play, while cached defense rows remain unchanged. No deck re-save or stored-defense data migration is necessary.
- Existing staging installations **do need** the small new `supabase/security_phase3_pvp_level_stats.sql` to change the trusted engine hash. It checks the staging DB system identifier, refuses unknown engine versions and unexpired old sessions, serializes against in-flight policy readers with an exclusive relation lock, is idempotent, and preserves the kill switch. It does not reset/change wallets, ratings, attempts, stored snapshots or receipts.
- Fresh installers already contain the new hash in `security_phase3_pvp.sql`; the regenerated staging bundle/parts/manifest contain that new policy. The existing-install-only upgrade patch is deliberately excluded from fresh installers (listed in `staging_sql_sources.json`). **Existing installations must not run the full installer/parts again.**

## Exact owner rollout — STAGING ONLY

1. Finish any running PvP matches using the **currently deployed old client/Edge**, then stop starting new matches during the short rollout. Do not turn the global kill switch off to drain matches: that also blocks normal settlement.
2. In staging Supabase SQL Editor, run the **entire** `supabase/security_phase3_pvp_level_stats.sql`. If it stops with active old sessions, finish those matches on the old version or wait until their normal expiry (at most one hour), then rerun. Never delete the guard or rewrite session hashes. The exclusive lock prevents an old start from slipping past the check. During the version mismatch between steps, starts fail closed without creating attempts.
3. Update the **existing** Edge Function **`pvp-verify-v3`**: replace its Dashboard `index.ts` with the entire regenerated **`supabase/functions/pvp-verify-v3/dashboard_single_file.ts`**, then Deploy. **JWT verification ON.** No custom secrets or access token are needed; existing built-in `SUPABASE_*` credentials, including the auto-injected service-role/secret key, remain runtime-only. Do not paste a key into code. CLI users may deploy the normal function entry and regenerated `_shared` bundle instead; the Dashboard single file already includes both.
4. Deploy the updated web/staging build from this commit, including **`js/pvp-core.js`, `js/pvp-engine-version.js`, `js/pvp.js`** and the prior feedback assets. Browser hard-refresh (PC Chrome: Ctrl+Shift+R). No Tailwind rebuild is needed because this follow-up adds no CSS/classes.
5. Confirm the SQL policy hash matches the new engine above. Test an upgraded attacker and an already-saved upgraded defense deck in AUTO/manual; no deck re-save is required. Pending expired old receipts recover through SQL without new-rule replay; historical settled receipts stay unchanged.

Do **not** apply this SQL/Edge to production: both remain explicitly staging-guarded. Production also has the bug, but a production phase3/security rollout needs its own reviewed, approved production configuration/migration. Simply copying these staging-only backend artifacts to the production project is not a supported production release.

## Validation

- `test_pvp_core.mjs`: fully passing; now permanently included in `test:security:phase3` so a browser/server-consistent regression cannot hide this failure again.
- New `test_pvp_level_stats.mjs`: exact formulas across all six current catalog grades plus legacy LR compatibility, EX metadata, skill-level power, diminishing points, immutable inputs, gear order/mode/sigil caps, actual field stats for both roles and all 12 AUTO/manual/mode browser/Edge combinations.
- Phase3 PGlite + real normal/Dashboard handlers: fresh post-save defense snapshots; wrong DB/unknown hash/active session upgrade rejection; idempotent hash change with no economy/snapshot changes; expired old-receipt recovery; kill-switch preservation.
- Required staging check/test/build and security phases1–3 pass, including the existing 120 canonical parity fixtures, previous UI feedback regressions and zero-import Dashboard reproducibility checks.
- Additional shared-function regressions: gear battle, war core, raid core, gear snapshot SQL and browser skill-level effects all pass.
- One optional, unrelated legacy test remains failing: `test_skill_level_sql.mjs` hardcodes a stale skill-catalog count of 142 (line 36). It fails identically on untouched phase3 base `70fd708`; every other assertion in that script passes. Its test and all SQL inputs are unchanged by this fix. This is not part of the required staging/security suites, all of which pass.
- Offline tests use actual engines/functions with fake DOM/Auth and in-memory SQL; no live DB writes, secrets, deployments or pushes were made.
