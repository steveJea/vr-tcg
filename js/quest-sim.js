// ===== 시련의 탑 소탕용 화면 없는 전투 (ES 모듈) =====
// tools/quest_sim.mjs 와 같은 규칙: 양측 5장 필드 시작, 손패·드로우·진영 없음, 양측 AI, 적 전멸 = 승리, maxTurns 초과 = 패배.
// skills.js 는 ?sim 으로 따로 불러와 게임 화면의 이펙트·로그(setEmitter)와 섞이지 않게 함.
import { runSweep } from './sweep-core.js';
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
/** me/ai: 카드 객체 배열 (battleCards / quest-gen enemies). leader: api.leaderFor(me). seed: 서버 세션 시드. 반환 { win, turns, timeout } */
export async function simBattle(me, ai, maxTurns = 40, leader = null, seed = null) {
  await init();
  const n = Number(seed);
  const used = Number.isSafeInteger(n) && n >= 1 && n <= 2147483646 ? n : 1 + Math.floor(Math.random() * 2147483646);
  return runSweep(SK, R, { me, ai, maxTurns, leader, seed: used });
}
window.VRQuestSim = { simBattle };
