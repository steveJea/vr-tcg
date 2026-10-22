// ===== 시련의 탑 소탕용 화면 없는 전투 (ES 모듈) =====
// tools/quest_sim.mjs 와 같은 규칙: 양측 5장 필드 시작, 손패·드로우·진영 없음, 양측 AI, 적 전멸 = 승리, maxTurns 초과 = 패배.
// skills.js 는 ?sim 으로 따로 불러와 게임 화면의 이펙트·로그(setEmitter)와 섞이지 않게 함.
const V = new URL('./skills.js?sim=1', import.meta.url).href;
const SK = await import(V);
const R = await import(new URL('./rules.js', import.meta.url).href);
let ready = null;
async function init() {
  if (!ready) ready = (async () => {
    const j = async p => (await fetch(p)).json();
    const [sk, co] = await Promise.all([j('data/skills.json'), j('data/combos.json')]);
    SK.setSkillData(sk, co); SK.setEmitter(() => {});
  })();
  return ready;
}
/** me/ai: 카드 객체 배열 (battleCards / quest-gen enemies). 반환 { win, turns } */
export async function simBattle(me, ai, maxTurns = 40) {
  await init();
  const mk = name => ({ name, hp: 1, maxHp: 1, deck: [], hand: [], field: [], mana: 0, maxMana: 0, noBase: true });
  const P = [mk('나'), mk('적')];
  SK.initPlayers(P[0], P[1]);
  me.forEach(c => SK.placeUnit(P[0], { ...c }, R.makeUnit)); ai.forEach(c => SK.placeUnit(P[1], { ...c }, R.makeUnit));
  SK.refreshAll(P[0]); SK.refreshAll(P[1]);
  const gone = p => !p.field.some(u => u.hp > 0);
  const firstMe = Math.random() < 0.5;
  const end = () => gone(P[1]) ? 1 : gone(P[0]) ? 0 : -1;
  for (let t = 0; t < maxTurns; t++) {
    const cur = P[(t + (firstMe ? 0 : 1)) % 2], op = cur.foe;
    R.clearBuff(op); R.refillMana(cur);
    cur.field.forEach(u => u.canAttack = true);
    SK.turnStart(cur);
    let e = end(); if (e >= 0) return { win: !!e, turns: t + 1 };
    for (const u of [...cur.field]) {
      if (!cur.field.includes(u) || !u.canAttack) continue;
      const sk = SK.aiPickSkill(u);
      if (sk) SK.useSkill(u, sk); else { const tg = R.aiPickTarget(u, cur, op); if (tg === undefined || tg === null) continue; R.resolveAttack(cur, op, u, tg); }
      e = end(); if (e >= 0) return { win: !!e, turns: t + 1 };
    }
    R.endTurnXp(cur); SK.turnEnd(cur);
    e = end(); if (e >= 0) return { win: !!e, turns: t + 1 };
  }
  return { win: false, turns: maxTurns, timeout: true };
}
window.VRQuestSim = { simBattle };
