// ===== 퀘스트(시련의 탑) 적 구성 생성기 — 순수 함수 (브라우저: window.VRQuestGen, node: globalThis.VRQuestGen) =====
// 층 번호로 시드 → 같은 층은 항상 같은 적 5장. 적 리더는 시트 등급에서 "목표 전투력 이하로 가장 가깝게" 레벨을 붙임.
// 나머지 4장: same = 리더 전투력의 90~100%, weak = 60~80% (리더와 같은 등급 이하에서 레벨로 맞춤). bond = combos.json 조합을 넣어 구성.
// 레벨 규칙(스토리와 같음): 스탯 배율 = 1 + 등급 비율 × (레벨 − 1), 비율 N1% R2% HR3% SR4% UR5% MR6%, 최대 레벨 N20 R30 HR40 SR50 UR60 MR70
// 전투력은 스탯 배율만큼 비례해서 오른다고 봄 (power × 배율)
// 2026-10 개편: quest.json level { base 5, step 5, every 10 } → 적 5명 모두 Lv = 5 + 5 × ⌊층/10⌋ (+ opts.levelOffset), 상한 없음. 카드 선택은 예전 시드 방식 그대로
(() => {
  const ORDER = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE'];
  const LV_RATE = { 'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06 };
  const LV_CAP = { 'NORMAL': 20, 'RARE': 30, 'HIGH RARE': 40, 'SUPER RARE': 50, 'ULTRA RARE': 60, 'MYTHIC RARE': 70 };
  const MAX_EX = { 'NORMAL': 1, 'RARE': 2, 'HIGH RARE': 3, 'SUPER RARE': 4, 'ULTRA RARE': 5, 'MYTHIC RARE': 6 };
  /** 적 최대 레벨 = 최대 레벨 + EX 최대 단계 × 5 (플레이어가 EX 합성으로 올릴 수 있는 끝까지) */
  const capOf = g => (LV_CAP[g] || 20) + 5 * (MAX_EX[g] || 1);
  const lvPct = (g, L) => Math.round((LV_RATE[g] || 0.01) * (Math.max(1, L) - 1) * 100);
  const powerAt = (c, L) => Math.round((+c.power || 0) * (1 + lvPct(c.grade, L) / 100));
  function rngOf(seed) { let a = (seed * 2654435761 + 0x9e3779b9) >>> 0; return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
  const pick = (r, list) => list[Math.floor(r() * list.length)];
  /** 레벨 L 적 카드 (전투용 카드 객체): 스탯·전투력 반영 */
  function leveled(c, L) {
    const m = 1 + lvPct(c.grade, L) / 100;
    return { ...c, HP: Math.round(+c.HP * m), ATK: Math.round(+c.ATK * m), DEF: Math.round(+c.DEF * m), power: powerAt(c, L), qLevel: L };
  }
  /** 목표 이하로 가장 큰 레벨 */
  function bestLevel(c, T) { let L = 0; for (let l = 1; l <= capOf(c.grade); l++) if (powerAt(c, l) <= T) L = l; return L; }
  /** [lo, hi] 안에 드는 레벨 목록 */
  function levelsIn(c, lo, hi) { const out = []; for (let l = 1; l <= capOf(c.grade); l++) { const p = powerAt(c, l); if (p >= lo && p <= hi) out.push(l); } return out; }

  function pickLeader(r, pool, f, prefer) {
    const T = f.power, cands = [];
    for (const c of pool) {
      if (c.grade !== f.grade) continue;
      const L = bestLevel(c, T); if (!L) continue;
      cands.push({ c, L, ratio: powerAt(c, L) / T });
    }
    if (prefer) { const pc = cands.filter(x => prefer.has(String(x.c.id)) && x.ratio >= 0.9); if (pc.length) { const x = pick(r, pc); return { c: x.c, L: x.L }; } }
    if (!cands.length) {   // 목표가 그 등급 최저보다 낮음 → 가장 약한 카드 Lv.1
      const g = pool.filter(c => c.grade === f.grade).sort((a, b) => a.power - b.power)[0];
      return g ? { c: g, L: 1 } : null;
    }
    cands.sort((a, b) => b.ratio - a.ratio);
    const top = cands[0].ratio, good = cands.filter(x => x.ratio >= Math.min(0.95, top - 0.02));   // 목표에 가장 가까운 후보들
    const x = pick(r, good);
    return { c: x.c, L: x.L };
  }
  /** 고정 레벨 (cfg.level = { base, step, every }): 5명 모두 base + step × ⌊층 / every⌋ + offset. 최대 레벨 상한 무시. 없으면 null (예전 전투력 목표 방식) */
  function levelOf(cfg, floor, offset = 0) {
    const lv = cfg?.level; if (!lv) return null;
    return Math.max(1, (lv.base ?? 5) + (lv.step ?? 5) * Math.floor(floor / (lv.every || 10)) + (offset | 0));
  }
  /** cfg: quest.json, f: 층, pool: 카드 목록(cards.csv), combos: combos.json, opts: { levelOffset }(속성 탑 +10 등)
   *  → { floor, enemies:[카드(레벨 반영)], leader, combo, range, level }
   *  카드 고르기는 층 번호 시드 그대로 (전투력 목표로 후보를 고름). cfg.level 이 있으면 고른 뒤 5명 모두 고정 레벨로 다시 맞춤 */
  function generate(cfg, f, pool, combos = [], opts = {}) {
    const g = generate0(cfg, f, pool, combos), L = levelOf(cfg, f.floor, opts.levelOffset);
    if (L == null || !g.enemies.length) return g;
    const byId = new Map(pool.map(c => [String(c.id), c])), man = g.manual ? f.enemies : null;
    const enemies = g.enemies.map((c, i) => leveled(byId.get(String(c.id)) || c, man?.[i]?.level || L));
    return { ...g, enemies, leader: enemies[0], range: undefined, level: L };
  }
  function generate0(cfg, f, pool, combos = []) {
    const r = rngOf(f.floor), n = cfg.enemyCount || 5;
    const byId = new Map(pool.map(c => [String(c.id), c]));
    if (Array.isArray(f.enemies) && f.enemies.length) {   // 수동 지정(덮어쓰기)
      const list = f.enemies.map(e => byId.get(String(e.id)) && leveled(byId.get(String(e.id)), e.level || 1)).filter(Boolean);
      return { floor: f.floor, enemies: list, leader: list[0], combo: null, boss: f.boss || null, manual: true };
    }
    const gi = ORDER.indexOf(f.grade), allowed = c => ORDER.indexOf(c.grade) <= gi && ORDER.indexOf(c.grade) >= 0;
    const [rlo, rhi] = (cfg.ranges || {})[f.others] || (f.others === 'weak' ? [0.6, 0.8] : [0.9, 1.0]);
    // 인연: 조합 후보 (모든 멤버가 리더 등급 이하, 5장 이하)
    let combo = null, prefer = null;
    if (f.bond) {
      // 조합 고르기: 멤버가 리더(목표의 90% 이상) 또는 나머지 범위에 들어갈 수 있는 비율이 높은 조합 우선
      const canLead = c => c.grade === f.grade && bestLevel(c, f.power) && powerAt(c, bestLevel(c, f.power)) >= f.power * 0.9;
      const fit = cb => { const ms = cb.cards.map(id => byId.get(String(id))), L = ms.find(canLead); if (!L) return -1;
        const lp = powerAt(L, bestLevel(L, f.power)); return ms.filter(c => c === L || levelsIn(c, lp * rlo, lp * rhi).length).length / ms.length; };
      const cs = combos.filter(cb => cb.cards.length <= n && cb.cards.every(id => byId.has(String(id)) && allowed(byId.get(String(id))))).map(cb => ({ cb, s: fit(cb) })).filter(x => x.s > 0);
      const best = cs.length ? Math.max(...cs.map(x => x.s)) : 0;
      const top = cs.filter(x => x.s >= best - 1e-9).map(x => x.cb);
      combo = top.length ? pick(r, top) : null;
      if (combo) prefer = new Set(combo.cards.map(String));
    }
    const lead = pickLeader(r, pool, f, prefer); if (!lead) return { floor: f.floor, enemies: [], leader: null, combo: null };
    const leader = leveled(lead.c, lead.L), lp = leader.power, lo = Math.round(lp * rlo), hi = Math.round(lp * rhi);
    const used = new Set([String(lead.c.id)]), out = [leader];
    const place = c => { const ls = levelsIn(c, lo, hi); if (!ls.length) return false; out.push(leveled(c, pick(r, ls))); used.add(String(c.id)); return true; };
    let comboOk = false;
    if (combo) {
      // 조합 멤버를 범위에 맞춰 넣음 (범위에 안 맞으면 가장 가까운 레벨로라도 넣어 조합을 살림)
      for (const id of combo.cards) {
        const c = byId.get(String(id)); if (!c || used.has(String(id)) || out.length >= n) continue;
        if (!place(c)) { let L = bestLevel(c, hi) || 1; out.push(leveled(c, L)); used.add(String(id)); }
      }
      comboOk = combo.cards.every(id => used.has(String(id)));
    }
    // 나머지: 범위 안에 드는 카드 (같은 등급 가중치 3배)
    const cands = pool.filter(c => !used.has(String(c.id)) && allowed(c) && levelsIn(c, lo, hi).length);
    const w = cands.map(c => c.grade === f.grade ? 3 : 1);
    while (out.length < n && cands.length) {
      let t = r() * w.reduce((a, b) => a + b, 0), i = 0;
      for (; i < cands.length - 1; i++) { t -= w[i]; if (t <= 0) break; }
      const c = cands.splice(i, 1)[0]; w.splice(i, 1); place(c);
    }
    // 범위에 맞는 카드가 모자라면 범위 밖 가장 가까운 카드로 채움
    if (out.length < n) {
      const rest = pool.filter(c => !used.has(String(c.id)) && allowed(c)).map(c => { const L = bestLevel(c, hi) || 1; return { c, L, d: Math.abs(powerAt(c, L) - (lo + hi) / 2) }; }).sort((a, b) => a.d - b.d);
      for (const x of rest) { if (out.length >= n) break; out.push(leveled(x.c, x.L)); used.add(String(x.c.id)); }
    }
    return { floor: f.floor, enemies: out, leader, combo: comboOk ? combo.name : null, boss: f.boss || null, range: [lo, hi] };
  }

  /** 속성 탑 적: 시드 = 탑+층. 그 속성 카드(+ 그 속성 NPC)만, 같은 카드 중복 가능.
   *  등급: 그 층 시련의 탑 리더 등급(f.grade) 이하 (그 속성에 그 등급이 없으면 가장 가까운 아래 등급, 없으면 가장 낮은 등급)
   *  레벨: 시련의 탑 공식 + levelOffset(기본 10). 첫 장 = 리더(가장 센 카드). opts: { tower, cls, npc:[카드], levelOffset } */
  const strSeed = t => { let h = 2166136261; for (const ch of String(t)) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0; return h; };
  function generateAttr(cfg, f, pool, opts = {}) {
    const r = rngOf((strSeed(opts.tower || opts.cls) ^ Math.imul(f.floor, 2654435761)) >>> 0), n = cfg.enemyCount || 5;
    const L = levelOf(cfg, f.floor, opts.levelOffset ?? 10) ?? Math.max(1, 15 + 5 * Math.floor(f.floor / 10));
    const cands = [...pool, ...(opts.npc || [])].filter(c => c.class === opts.cls && ORDER.indexOf(c.grade) >= 0);
    if (!cands.length) return { floor: f.floor, enemies: [], leader: null, combo: null, level: L, cls: opts.cls };
    let gi = ORDER.indexOf(f.grade); while (gi > 0 && !cands.some(c => ORDER.indexOf(c.grade) === gi)) gi--;
    if (!cands.some(c => ORDER.indexOf(c.grade) === gi)) gi = Math.min(...cands.map(c => ORDER.indexOf(c.grade)));
    // 후보 종류가 3 미만이면 한 등급씩 위로 넓힘 (리더는 원래 등급에서)
    let hi = gi; const kinds = h => new Set(cands.filter(c => ORDER.indexOf(c.grade) <= h).map(c => String(c.id))).size;
    while (kinds(hi) < 3 && hi < ORDER.length - 1) hi++;
    const ok = cands.filter(c => ORDER.indexOf(c.grade) <= hi), top = ok.filter(c => ORDER.indexOf(c.grade) === gi);
    const w = ok.map(c => hi > gi ? 1 : ORDER.indexOf(c.grade) === gi ? 3 : 1), sum = w.reduce((a, b) => a + b, 0);
    const out = [pick(r, top)];
    if (hi > gi) { const rest = ok.filter(c => c !== out[0]); while (out.length < 3 && rest.length) out.push(rest.splice(Math.floor(r() * rest.length), 1)[0]); } // 넓힌 경우 최소 3종
    while (out.length < n) { let t = r() * sum, i = 0; for (; i < ok.length - 1; i++) { t -= w[i]; if (t <= 0) break; } out.push(ok[i]); }
    const enemies = out.map(c => leveled(c, L)).sort((a, b) => b.power - a.power);
    return { floor: f.floor, enemies, leader: enemies[0], combo: null, boss: f.floor % 10 === 0 ? String(enemies[0].id) : null, level: L, cls: opts.cls, grade: ORDER[gi] };
  }
  /** 첫 클리어 보상: 층 rewards 덮어쓰기 → every 규칙(먼저 맞는 것). 반환 { tickets, gold } (없으면 null) */
  function rewardOf(cfg, f) {
    if (f.rewards) return { tickets: f.rewards.tickets | 0, gold: f.rewards.gold | 0 };
    for (const [k, rw] of (cfg.rewards?.every || [])) if (f.floor % k === 0) return { tickets: rw.tickets | 0, gold: rw.gold | 0 };
    return null;
  }
  globalThis.VRQuestGen = { generate, generateAttr, levelOf, rewardOf, powerAt, leveled, lvPct, capOf, LV_CAP, LV_RATE };
})();
