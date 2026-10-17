import { RULES, ELEMENTS, elementMultiplier, calcDamage, canSummon, buildDeck, parseCSV, aiSummonOrder, aiPickTarget, recallCost, canRecall, aiShouldRecall, makeUnit, resolveAttack, refillMana, ACTIONS, canAction, doAction, clearBuff, aiWantShuffle, aiWantBuff, aiWantHeal, aiWantFieldHeal, aiPickItem, endTurnXp, ITEMS, canEquip, equip, attackTargets, canTarget, autoTarget, heroLocked, xpToNext, SKILLS, gainXp, setCardPool, canSacrifice, sacrifice, aiPickSacrifice, aiWantAccel, judgeTimeout, JUDGE_LABEL } from './rules.js';
import { setSkillData, setEmitter, initPlayers, placeUnit, turnStart, turnEnd, useSkill, skillState, aiPickSkill, refreshAll, statusIcons, skillsOf, combos, STATUS, SK, maleLure } from './skills.js';

const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const NF = new Intl.NumberFormat('ko-KR');
const fmt = n => NF.format(n);
const $ = id => document.getElementById(id);
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ===== 전적 저장 (나중에 서버 저장으로 교체 가능하도록 분리) =====
// 아케이드 전적: 게스트는 브라우저 기록, 로그인하면 계정별 키(서버 matches 집계로 채움)라 계정끼리 섞이지 않음
const Stats = {
  get KEY() { const u = window.VRCloud?.user?.id; return u ? `vrTcgStats.v1:${u}` : 'vrTcgStats.v1'; },
  load() { try { return { wins: 0, losses: 0, draws: 0, ...JSON.parse(localStorage.getItem(this.KEY)) }; } catch { return { wins: 0, losses: 0, draws: 0 }; } },
  record(win) { const s = this.load(); win === null ? s.draws++ : win ? s.wins++ : s.losses++; localStorage.setItem(this.KEY, JSON.stringify(s)); return s; },
};

let POOL = [];

// ===== 용병 시스템 =====
// 배틀 중 마나로 HR·SR·UR 카드 고용 (한 판 1명). 고용한 카드는 그 판에서만 쓰고, 판이 끝나면 리셋.
const Merc = {
  KEY: 'vrTcgMercs.v1',
  PRICE: { 'HIGH RARE': 1.2, 'SUPER RARE': 1.5, 'ULTRA RARE': 1.8 },   // N·R·MR은 판매 안 함
  OFFER_N: 3,
  MAX_PER_BATTLE: 1,
  // 판 단위 리셋: 저장 안 함. 예전 영구 보유 데이터는 지움
  clearLegacy() { try { localStorage.removeItem(this.KEY); } catch {} },
  price(c) { return Math.ceil(c.cost * this.PRICE[c.grade]); },
  eligible(c) { return c.grade in this.PRICE; },
  // 보유 여부: 이번 판에 내 덱·손패·필드·무덤에 있는 카드만
  isOwned(c, p) {
    const id = String(c.id);
    return [...p.deck, ...p.hand, ...p.field.map(u => u.base || u.card), ...(p.grave || [])].some(x => String(x.id) === id);
  },
  // 이번 판 용병 목록: 판마다 HR·SR·UR 각 1장씩 랜덤 (부족하면 아무 대상 등급에서 채움)
  roll(pool, p) {
    // 이번 판 내 덱·손패에 이미 있는 카드는 목록에서 빼기 (예전엔 목록에 떠서 '보유 중'으로 막혔음)
    if (p) pool = pool.filter(x => !this.isOwned(x, p));
    const pick = arr => arr[Math.floor(Math.random() * arr.length)];
    const out = [];
    for (const g of Object.keys(this.PRICE)) { const c = pick(pool.filter(x => x.grade === g && !out.includes(x))); if (c) out.push(c); }
    const rest = pool.filter(x => this.eligible(x) && !out.includes(x));
    while (out.length < this.OFFER_N && rest.length) out.push(rest.splice(Math.floor(Math.random() * rest.length), 1)[0]);
    return out;
  },
  canBuy(c, p) {
    if (S.mercHired === String(c.id)) return { ok: false, reason: '고용됨', hired: true };
    if (S.mercBought >= this.MAX_PER_BATTLE) return { ok: false, reason: '이번 판 고용 완료' };
    if (this.isOwned(c, p)) return { ok: false, reason: '이번 판 덱에 있음' };
    const cost = this.price(c);
    if (p.mana < cost) return { ok: false, reason: '마나 부족' };
    return { ok: true, cost };
  },
};
Merc.clearLegacy();
let S = null;          // 게임 상태
let selected = null;   // 선택된 공격 유닛 uid
let uidSeq = 1;
// 연출 스킵: 토글(localStorage 저장) 또는 연출 중 클릭으로 현재 연출 빨리 감기
const SKIP_KEY = 'vrTcgSkipFx';
let skipFx = localStorage.getItem(SKIP_KEY) === '1';
let fastForward = false;
const FX_OFF = () => !!(window.TCG_FAST || skipFx || fastForward);
const AI_DELAY = () => (window.TCG_FAST ? 0 : (skipFx || fastForward) ? 120 : 650);

function newPlayer(name, second, deckOverride = null, hp = RULES.HERO_HP, fieldStart = false) {
  const deck = deckOverride ? (fieldStart ? [...deckOverride] : shuffleArr(deckOverride)) : buildDeck(POOL);
  const n = fieldStart ? 0 : RULES.OPENING_HAND + (second ? RULES.SECOND_PLAYER_BONUS_CARDS : 0);
  return { name, hp, maxHp: hp, deck, hand: deck.splice(0, n), field: [], mana: 0, maxMana: 0, second };
}

function log(msg, cls = '') {
  const el = document.createElement('div');
  el.className = 'py-0.5 ' + cls; el.textContent = msg;
  $('log').prepend(el);
}

const shuffleArr = a => { a = [...a]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
/** story: 스토리 모드 전투 설정 { me:[카드], ai:[카드], win:'wipe'|'ko', meHp, aiHp, aiName, first, onEnd(win, reason) }. 없으면 아케이드 */
function startGame(story = null) {
  if (story && typeof story.then === 'function' || story instanceof Event) story = null;
  const first = story?.first || (Math.random() < 0.5 ? 'me' : 'ai');   // 선공 동전 던지기
  const fs = !!story;   // 스토리: 손패 없이 출전 카드 전부 필드에서 시작
  S = { me: newPlayer('나', first !== 'me', story?.me, story?.meHp, fs), ai: newPlayer(story?.aiName || '적군', first !== 'ai', story?.ai, story?.aiHp, fs), first, story, turn: first, turnNo: 0, totalTurns: 0, myTurns: 0, over: false, busy: false, fxSeen: new Set(), mercBought: 0, mercHired: null, mercOffer: [], log: { dmg: new Map(), total: 0, skills: 0, merc: null, played: new Set(), kills: {} } };
  S.mercOffer = story ? [] : Merc.roll(POOL, S.me);
  // 스토리: 내 진영 없음(일반·보스 공통). 상대 진영은 보스전에만 존재
  S.me.noBase = !!story; S.ai.noBase = story?.win === 'wipe';
  for (const w of ['me', 'ai']) { $(`${w}-hp`).classList.toggle('hidden', S[w].noBase); $(`${w}-hpbar`).parentElement.classList.toggle('hidden', S[w].noBase); }
  $('game').classList.toggle('story-field', !!story);
  { const lbl = $('ai-order').parentElement.firstChild; if (lbl?.nodeType === 3) lbl.textContent = story ? `${story.aiName || '적군'} ` : '🤖 컴퓨터 '; }
  preloadFx([...S.me.deck, ...S.me.hand, ...S.ai.deck, ...S.ai.hand]);
  selected = null; $('log').innerHTML = '';
  $('end-screen').classList.add('hidden'); $('start-screen').classList.add('hidden'); $('game').classList.remove('hidden');
  initPlayers(S.me, S.ai);
  if (fs) {   // 스토리: 양측 카드 전부 필드에 배치 (최대 FIELD_MAX)
    for (const who of ['me', 'ai']) {
      const p = S[who];
      for (const c of p.deck.splice(0, RULES.FIELD_MAX)) {
        const u = placeUnit(p, c, makeUnit);
        if (who === 'me') S.log.played.add(String(c.id));
        if (who === 'ai' && story.bossId != null && String(c.id) === String(story.bossId) && !p.field.some(x => x.undying)) { u.undying = true; u.boss = true; }
      }
      p.deck = [];
    }
    log(story.win === 'ko' ? '👑 보스전: 보스는 진영 안에서 쓰러지지 않아요. 상대 진영 HP를 0으로!' : '⚔️ 일반전: 상대 카드를 모두 쓰러뜨리세요!', 'text-amber-300');
  }
  if (fs) log('⚔️ 출전 카드가 모두 필드에서 시작합니다 (손패·드로우 없음).', 'text-emerald-400');
  else log(first === 'me' ? '🪙 동전 던지기: 내가 선공!' : `🪙 동전 던지기: 컴퓨터가 선공! (나는 후공, 시작 손패 +${RULES.SECOND_PLAYER_BONUS_CARDS})`, 'text-emerald-400');
  $('me-order').textContent = first === 'me' ? '선공' : '후공';
  $('ai-order').textContent = first === 'ai' ? '선공' : '후공';
  startTurn(first);
}

function startTurn(who) {
  const p = S[who];
  S.turn = who; if (who === S.first) S.turnNo++; S.totalTurns++;
  if (who === 'me') { S.myTurns++; if (myTurnsLeft() === 1) lastTurnToast(); }
  clearBuff(opp(who));                   // 지난 턴 강화 해제
  const bonus = refillMana(p);
  if (bonus) { log(`${p.name}: 처치 보너스 마나 +${bonus}`, 'text-sky-300'); if (who === 'me') floatText(`💧 +${bonus}`, 'text-sky-300'); }
  if (S.story) { /* 스토리: 드로우 없음 */ } else if (p.deck.length) p.hand.push(p.deck.shift()); else log(`${p.name}: 덱이 비어 드로우를 건너뜁니다.`, 'text-zinc-500');
  p.field.forEach(u => u.canAttack = true);
  turnStart(p);                           // 쿨타임·MP 회복, 턴 시작 패시브, 마비/혼란/교란 처리
  render();
  if (checkEnd()) return;
  if (who === 'ai') aiTurn();
}

function useAction(who, type) {
  const p = S[who], r = doAction(type, p);
  if (!r.ok) return r;
  const a = ACTIONS[type];
  const detail = type === 'accel' ? `다음 턴부터 매 턴 마나 +${r.n * RULES.ACCEL_BONUS} (${r.n}/${RULES.ACCEL_MAX})` : type === 'shuffle' ? `전체 카드에서 새 카드 ${r.n}장` : type === 'heal' ? `진영 HP +${fmt(r.healed)}` : type === 'fieldheal' ? `필드 ${r.n}장 HP 총 +${fmt(r.healed)}` : `필드 ${r.n}장 이번 턴 ATK +${Math.round(RULES.BUFF_RATIO * 100)}%`;
  log(`${p.name}: ${a.icon} ${a.label} (마나 ${a.cost()}) — ${detail}`, 'text-violet-300');
  if (type === 'heal') floatText(`+${fmt(r.healed)}`, 'text-emerald-300', who === 'me' ? 'me' : 'ai');
  if (type === 'fieldheal') floatText(`💚 +${fmt(r.healed)}`, 'text-emerald-300', who);
  if (type === 'buff') floatText(`⚔️ ATK +${Math.round(RULES.BUFF_RATIO * 100)}%`, 'text-violet-300', who);
  render();
  return r;
}

function equipItem(who, unit, type) {
  const p = S[who], r = equip(type, unit, p);
  if (!r.ok) return r;
  const it = ITEMS[type];
  log(`${p.name}: ${unit.card.name}에게 ${it.icon} ${it.label} 장착 (마나 ${it.cost()}) — ${type === 'weapon' ? 'ATK' : 'HP'} +${fmt(r.d)}`, 'text-amber-200');
  render();
  return r;
}

function opp(who) { return who === 'me' ? S.ai : S.me; }

function summon(who, card) {
  const p = S[who], check = canSummon(card, p, opp(who));
  if (!check.ok) return check;
  p.mana -= card.cost;
  p.hand.splice(p.hand.indexOf(card), 1);
  log(`${p.name}: ${card.name} 소환 (코스트 ${card.cost})`);
  if (who === 'me' && S.story) S.log.played.add(String(card.id));   // 스토리: 참전 카드 기록 (EXP 지급용)
  placeUnit(p, card, makeUnit);
  render();
  return { ok: true };
}

function doSacrifice(who, unit) {
  const p = S[who], r = sacrifice(unit, p);
  if (!r.ok) return r;
  if (selected === unit.uid) selected = null;
  log(`${p.name}: ${unit.card.name} 희생 — 마나 +${r.gain}`, 'text-rose-300');
  floatText(`🩸 마나 +${r.gain}`, 'text-sky-300', who);
  render();
  return r;
}

function recall(who, unit) {
  const p = S[who], check = S.story ? { ok: false, cost: 0, reason: '스토리 불가' } : canRecall(unit, p);
  if (!check.ok || !p.field.includes(unit)) return check;
  p.mana -= check.cost;
  p.field = p.field.filter(u => u !== unit);
  p.hand.push(unit.base);               // 원본 카드로 복귀: HP·레벨·XP·아이템 초기화
  if (selected === unit.uid) selected = null;
  refreshAll(p);
  log(`${p.name}: ${unit.card.name} 회수 (마나 ${check.cost}) — 레벨·아이템 초기화`, 'text-sky-300');
  render();
  return { ok: true };
}

async function attackAll() {
  if (S.turn !== 'me' || S.over || S.busy) return;
  const ready = S.me.field.filter(u => u.canAttack);
  if (!ready.length) return;
  S.busy = true; selected = null; render();
  log(`일괄 공격! (${ready.length}장)`, 'text-emerald-400');
  try {
    for (const u of ready) {
      if (S.over) break;
      if (!S.me.field.includes(u) || !u.canAttack) continue;
      const t = autoTarget(u, S.me, S.ai);
      if (t === undefined) continue;          // 공격할 수 있는 대상 없음 (첫 턴 등)
      await attack('me', u, t, true);
      await sleep(fxMs(60));
    }
  } catch (err) { reportError('attackAll', err); }
  resetAnim();
  S.busy = false; fastForward = false; render();
}

function renderSkipBtn() {
  const m = $('main-skip'); if (m) { m.textContent = skipFx ? '⏩ 스킵' : '🎬 연출'; m.classList.toggle('on', skipFx); }
  const b = $('fx-skip');
  b.textContent = skipFx ? '⏩ 스킵 ON' : '🎬 연출';
  b.classList.toggle('border-amber-400', skipFx); b.classList.toggle('text-amber-300', skipFx);
}

// ===== 공격 연출 =====
const REDUCED = () => !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
const fxMs = ms => (FX_OFF() ? 0 : REDUCED() ? Math.round(ms * 0.3) : ms);
const unitEl = (who, u) => document.querySelector(`#${who}-field [data-uid="${u.uid}"], #${who}-boss [data-uid="${u.uid}"]`);
const heroEl = who => $(`${who}-hero`);

function shake(el) {
  if (!el || FX_OFF()) return;
  el.classList.remove('fx-shake', 'fx-hitflash'); void el.offsetWidth;
  el.classList.add('fx-shake', 'fx-hitflash');
  setTimeout(() => el.classList.remove('fx-shake', 'fx-hitflash'), 330);
}

function dmgNumber(el, text, color) {
  if (!el || FX_OFF()) return;
  const r = el.getBoundingClientRect();
  const d = document.createElement('div');
  d.className = 'fx-dmg'; d.textContent = text;
  if (color) d.style.color = color;
  d.style.left = (r.left + r.width / 2 + (Math.random() - 0.5) * 16) + 'px';
  d.style.top = (r.top + r.height * 0.4) + 'px';
  document.body.appendChild(d);
  setTimeout(() => d.remove(), 950);
}

/** 공격자를 대상 쪽으로 돌진(getBoundingClientRect 차이 → transform). back()으로 제자리 복귀 */
async function lunge(el, targetEl) {
  if (!el || !targetEl || FX_OFF()) return { back: async () => {} };
  const a = el.getBoundingClientRect(), b = targetEl.getBoundingClientRect();
  const dx = (b.left + b.width / 2) - (a.left + a.width / 2);
  const dy = (b.top + b.height / 2) - (a.top + a.height / 2);
  const k = 0.78;
  el.classList.add('fx-attacker');
  el.style.transition = `transform ${fxMs(90)}ms ease-out`;
  el.style.transform = `translate(${dx * -0.06}px, ${dy * -0.06}px) scale(1.06)`;
  await sleep(fxMs(90));
  el.style.transition = `transform ${fxMs(150)}ms cubic-bezier(.5,0,1,1)`;
  el.style.transform = `translate(${dx * k}px, ${dy * k}px) scale(1.1)`;
  await sleep(fxMs(150));
  return {
    back: async () => {
      el.style.transition = `transform ${fxMs(160)}ms ease-out`;
      el.style.transform = '';
      await sleep(fxMs(160));
      el.classList.remove('fx-attacker'); el.style.transition = '';
    }
  };
}

/** 연출(돌진→충돌→복귀) 후 상태 반영. 전투 결과는 resolveAttack 그대로라 로직은 동일.
 *  예외가 나도 finally에서 연출·busy를 되돌려 게임이 멈추지 않게 함 */
async function attack(who, unit, target, fromBatch = false) {
  const o = opp(who), p = S[who];
  if (!unit.canAttack || S.over) return;
  if (!fromBatch && who === 'me' && S.busy) return;
  if (!canTarget(p, o, target)) { if (who === 'me') { const r = attackTargets(p, o).reason; log(r, 'text-red-400'); floatText(r, 'text-red-400 text-sm', 'ai'); } return; }
  const prevBusy = S.busy;
  S.busy = true; selected = null;
  const oWho = who === 'me' ? 'ai' : 'me';
  let aEl = null;
  try {
    if (!FX_OFF()) render();
    aEl = unitEl(who, unit);
    // 남성 공격 유도(최윤희·이혜경): 진영을 노려도 유도 카드 쪽으로 돌진하도록 미리 계산
    const lure = maleLure(unit, o);
    const shown = lure && lure !== target ? lure : target;
    const tEl = shown ? (unitEl(oWho, shown) || heroEl(oWho)) : heroEl(oWho);
    const hit = await withTimeout(lunge(aEl, tEl), 1500);

    const cls = who === 'me' ? 'text-emerald-300' : 'text-red-300';
    pendingDying = [];
    for (const e of resolveAttack(p, o, unit, target)) {
      if (e.type === 'hero') { log(`${unit.card.name} → ${o.name} 진영 ${fmt(e.dmg)} 피해`, cls); shake(tEl); dmgNumber(tEl, `-${fmt(e.dmg)}`); }
      else if (e.type === 'hit') {
        const real = e.target || shown;
        const rEl = (real && (unitEl(oWho, real) || unitEl(who, real))) || tEl;
        const orig = shown || null;
        log(`${unit.card.name} → ${real?.card?.name ?? '?'}${orig && real !== orig ? ` (${orig.card.name} 대신)` : (!orig ? ' (진영 공격 유도)' : '')} ${fmt(e.d1)} 피해${e.mult !== 1 ? ` (속성 ×${e.mult})` : ''}, 반격 ${fmt(e.d2)}`, cls);
        shake(rEl); dmgNumber(rEl, `-${fmt(e.d1)}`);
        if (e.d2) { shake(aEl); dmgNumber(aEl, `-${fmt(e.d2)}`, '#fca5a5'); }
      }
      else if (e.type === 'overflow') { log(`초과 피해 ${fmt(e.dmg)} → ${o.name} 진영`, 'text-orange-300'); const h = heroEl(oWho); shake(h); dmgNumber(h, `💥 -${fmt(e.dmg)}`, '#fdba74'); }
    }
    renderHero(oWho); renderHero(who);
    await withTimeout(hit?.back?.() ?? Promise.resolve(), 1500);
    await withTimeout(fadeDying(), 1500);
  } catch (err) {
    reportError('attack', err);
  } finally {
    resetAnim(aEl);
    unit.canAttack = false;
    S.busy = prevBusy;
    if (!prevBusy) fastForward = false;
    render();
    checkEnd();
  }
}

/** 안전장치: 연출 promise 타임아웃, 남은 연출 정리, 오류 기록 */
function withTimeout(pr, ms) { return Promise.race([pr, new Promise(r => setTimeout(r, ms))]); }
function resetAnim(el) {
  for (const x of [el, ...document.querySelectorAll('.fx-attacker')]) if (x) { x.classList.remove('fx-attacker'); x.style.transform = ''; x.style.transition = ''; }
}
function reportError(where, err) {
  console.error(`[TCG] ${where}`, err);
  (window.TCG_ERRORS ||= []).push(`${where}: ${err?.message || err}`);
}

/** 작은 떠오르는 글자 연출 */
function floatText(text, cls, side = 'me') {
  const anchor = $(side === 'me' ? 'me-field' : 'ai-field');
  if (!anchor) return;
  const r = anchor.getBoundingClientRect();
  const el = document.createElement('div');
  el.className = `float-text fixed z-30 pointer-events-none font-black text-lg drop-shadow ${cls}`;
  el.textContent = text;
  el.style.left = (r.left + r.width / 2 + (Math.random() - 0.5) * 80) + 'px';
  el.style.top = (r.top + r.height / 2) + 'px';
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 1200);
}

function finish(win, reason) {
  S.over = true; hideModal('detail');
  if (S.story) {   // 스토리 모드: 아케이드 전적·랭킹·갤러리에 기록하지 않고 스토리 화면으로 결과 전달
    render();
    const cb = S.story.onEnd;
    setTimeout(() => { $('game').classList.add('hidden'); try { cb?.(win, reason, { turns: S.turnNo, damage: S.log.total, played: [...S.log.played], kills: { ...S.log.kills } }); } catch (err) { reportError('storyEnd', err); } }, FX_OFF() ? 0 : 900);
    return true;
  }
  const st = Stats.record(win);
  $('end-title').innerHTML = win === null ? '<span class="text-zinc-200">무승부</span>' : win ? '<span class="text-emerald-400">승리!</span>' : '<span class="text-red-400">패배...</span>';
  const why = reason === 'ko' ? '진영 붕괴 (KO)' : `${RULES.MAX_TURNS}턴 종료 판정 · ${JUDGE_LABEL[reason]}`;
  const detail = reason === 'ko' ? '' : `<div class="text-sm text-zinc-400 mt-1">진영 HP 나 ${fmt(S.me.hp)} : ${fmt(S.ai.hp)} 상대 · 필드 카드 ${S.me.field.length} : ${S.ai.field.length}</div>`;
  $('end-text').innerHTML = `<div id="end-reason" class="font-bold text-amber-300">${why}</div>${detail}<div class="mt-2">${S.turnNo}라운드 · 아케이드 전적 ${st.wins}승 ${st.losses}패${st.draws ? ` ${st.draws}무` : ''}</div>`;
  try { showEnding(win, reason); } catch (err) { reportError('ending', err); }
  try { const mvp = pickMvp(); window.dispatchEvent(new CustomEvent('vr:match', { detail: { result: win === null ? 'draw' : win ? 'win' : 'lose', reason, turns: S.turnNo, damage: S.log.total, skills: S.log.skills, mvpId: mvp?.card.id, mvpName: mvp?.card.name, mercId: S.log.merc?.id, fieldIds: S.me.field.map(u => (u.base || u.card).id) } })); } catch {}
  $('end-screen').classList.remove('hidden');
  render();
  return true;
}

function checkEnd() {
  if (S.over) return true;
  if (S.ai.hp <= 0 || S.me.hp <= 0) return finish(S.ai.hp <= 0, 'ko');
  if (S.story) {   // 스토리: 내 필드 카드 전멸 시 패배 / 일반전은 상대 카드 전멸 시 승리 (보스전은 진영 HP 0)
    const gone = p => !p.field.length && !p.hand.length && !p.deck.length;
    if (S.story.win === 'wipe' && gone(S.ai)) return finish(true, 'wipe');
    if (gone(S.me)) return finish(false, 'wipe');
  }
  return false;
}
/** 턴 종료 후: 전체 턴 제한 도달 시 판정 */
function checkTimeout() {
  if (S.over || S.totalTurns < RULES.MAX_TURNS) return S.over;
  if (S.story) return finish(false, 'timeout');   // 스토리(일반·보스): 턴 제한 도달 = 패배
  const j = judgeTimeout(S.me, S.ai);
  return finish(j.winner === null ? null : j.winner === S.me, j.reason);
}

function endTurn() {
  if (S.turn !== 'me' || S.over || S.busy) return;
  selected = null;
  endTurnXp(S.me); turnEnd(S.me);
  render();
  if (checkEnd() || checkTimeout()) return;
  startTurn('ai');
}

// ===== 엔딩 =====
/** MVP = 이번 판 상대에게 가장 많은 피해를 준 내 카드. 피해 기록이 없으면 필드→손패 중 등급·코스트 높은 카드 */
function pickMvp() {
  const best = [...S.log.dmg.values()].sort((a, b) => b.dmg - a.dmg)[0];
  if (best) return best;
  const pool = [...S.me.field.map(u => u.card), ...S.me.hand];
  pool.sort((a, b) => (GRADE_RANK[b.grade] ?? 0) - (GRADE_RANK[a.grade] ?? 0) || b.cost - a.cost);
  return pool[0] ? { card: pool[0], dmg: 0 } : null;
}
function mvpVoice(card) {
  try {
    if (!voiceOn || !voiceSet || !card) return;
    const n = skillsOf(card.id).length;
    for (let i = 1; i <= Math.max(n, 3); i++) { const k = `${card.id}_${i}`; if (voiceSet.has(k)) {
      if (voiceCur) { try { voiceCur.pause(); } catch {} }
      const a = voiceAudio(k); a.volume = voiceVol; a.currentTime = 0; voiceCur = a;
      const pr = a.play(); if (pr && pr.catch) pr.catch(() => {}); return k; } }
  } catch {}
}
function showEnding(win, reason) {
  const mvp = pickMvp(), L = S.log;
  const kind = win === null ? 'draw' : win ? 'win' : 'lose';
  const title = { win: 'VICTORY', lose: 'DEFEAT', draw: 'DRAW' }[kind];
  const sub = { win: '승리!', lose: '패배...', draw: '무승부' }[kind];
  const box = $('end-screen');
  box.className = `end-${kind} hidden fixed inset-0 flex items-center justify-center z-50 p-3 overflow-y-auto`;
  const mvpHTML = mvp ? `<div class="end-mvp ${kind === 'win' ? 'end-mvp-big' : ''}">
      <img src="${IMG}${mvp.card.id}.webp" alt="${mvp.card.name}" onerror="this.style.visibility='hidden'">
      <div class="end-mvp-tag">MVP · ${mvp.card.name}${mvp.dmg ? ` · 피해 ${fmt(mvp.dmg)}` : ''}</div></div>` : '';
  const row = (k, v) => `<div class="flex justify-between gap-3 py-1 border-b border-white/10"><span class="text-zinc-400">${k}</span><span class="font-bold text-zinc-100">${v}</span></div>`;
  $('end-title').innerHTML = `<div class="end-slash"><div class="end-big">${title}</div></div><div class="text-base font-bold mt-1 ${kind === 'win' ? 'text-emerald-300' : kind === 'lose' ? 'text-red-400' : 'text-zinc-200'}">${sub}</div>`;
  $('end-mvp-wrap').innerHTML = mvpHTML;
  $('end-stats').innerHTML = row('진행 턴', `${S.myTurns || S.turnNo}턴 (${S.turnNo}라운드)`) + row('준 피해 합계', fmt(L.total)) + row('사용한 스킬', `${L.skills}회`)
    + row('고용한 용병', L.merc ? `🗡️ ${L.merc.name}` : '없음') + row('진영 HP', `나 ${fmt(Math.max(0, S.me.hp))} : ${fmt(Math.max(0, S.ai.hp))} 상대`);
  S.endShare = `VR: Abyss Gate에서 ${sub}${mvp ? ` MVP는 ${mvp.card.name}!` : ''} (${S.turnNo}라운드, 피해 ${fmt(L.total)})`;
  if (kind === 'win' && mvp) setTimeout(() => mvpVoice(mvp.card), FX_OFF() ? 0 : 500);
}
async function shareResult() {
  const url = 'https://tcg.mbbs.kr/', text = S?.endShare || 'VR: Abyss Gate';
  const msg = $('end-share-msg');
  try { if (navigator.share) { await navigator.share({ title: 'VR: Abyss Gate', text, url }); return; } } catch (e) { if (e?.name === 'AbortError') return; }
  try { await navigator.clipboard.writeText(`${text} ${url}`); msg.textContent = '링크를 복사했어요!'; }
  catch { msg.textContent = `${text} ${url}`; }
}

// ===== 스킬 =====
const whoOf = p => (p === S.me ? 'me' : 'ai');
let pendingDying = [];
async function fadeDying() {
  const els = pendingDying.filter(Boolean); pendingDying = [];
  if (els.length && !FX_OFF()) { els.forEach(el => el.classList.add('fx-dying')); await sleep(fxMs(300)); }
}
const TYPE_COLOR = { '공격': 'bg-red-600', '도발': 'bg-orange-500', '회복': 'bg-emerald-600', '버프': 'bg-sky-600', '디버프': 'bg-purple-600' };


/** 스킬 보이스: data/voice/<카드id>_<스킬번호>.mp3 (index.json에 있는 것만). 실패해도 게임은 그대로 진행 */
const VOICE_ON_KEY = 'vrTcgVoiceOn', VOICE_VOL_KEY = 'vrTcgVoiceVol';
let voiceOn = localStorage.getItem(VOICE_ON_KEY) !== '0';
let voiceVol = Math.min(1, Math.max(0, parseFloat(localStorage.getItem(VOICE_VOL_KEY) ?? '0.8') || 0));
let voiceSet = null, voiceCur = null;
const voiceCache = new Map();
// 재생 중인 보이스 집합: 하나라도 재생 중이면 BGM 덕킹, 모두 끝나면(ended/error/pause) 복구
const voiceActive = new Set();
function voiceDuckSync() { try { window.VRSound?.duck?.(voiceActive.size > 0); } catch {} }
function trackVoice(a) {
  if (a._duckTracked) return; a._duckTracked = true;
  a.addEventListener('playing', () => { voiceActive.add(a); voiceDuckSync(); });
  const off = () => { voiceActive.delete(a); setTimeout(voiceDuckSync, 60); }; // 60ms 유예: 보이스 교체 시 BGM 출렁임 방지
  ['ended', 'pause', 'error', 'abort', 'emptied'].forEach(ev => a.addEventListener(ev, off));
}
fetch('data/voice/index.json').then(r => r.ok ? r.json() : []).then(a => { voiceSet = new Set(a); }).catch(() => { voiceSet = new Set(); });
function voiceKey(u, name) {
  try { const i = skillsOf(u.card.id).findIndex(x => x.name === name); return i < 0 ? null : `${u.card.id}_${i + 1}`; } catch { return null; }
}
function voiceAudio(k) {
  let a = voiceCache.get(k);
  if (!a) { a = new Audio(); a.preload = 'auto'; a.src = `data/voice/${k}.mp3`; voiceCache.set(k, a); trackVoice(a); }
  return a;
}
function preloadVoice(cards) {
  if (!voiceSet) return;
  for (const c of cards) skillsOf(c.id).forEach((s, i) => { const k = `${c.id}_${i + 1}`; if (voiceSet.has(k)) voiceAudio(k); });
}
function playVoice(u, name) {
  try {
    if (!voiceOn || !voiceSet || !u) return;
    const k = voiceKey(u, name); if (!k || !voiceSet.has(k)) return;
    if (voiceCur) { try { voiceCur.pause(); voiceCur.currentTime = 0; } catch {} }
    const a = voiceAudio(k); a.volume = voiceVol; a.currentTime = 0; voiceCur = a;
    const p = a.play(); if (p && p.catch) p.catch(() => {});
  } catch {}
}
let voiceUnlocked = false;
function unlockVoice() {
  if (voiceUnlocked) return; voiceUnlocked = true;
  try { const a = new Audio('data:audio/mp3;base64,SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA//tQxAADB8AhSmxhIIEVCSiJrDCQBTcu3UrAIwUdkRgQbFAZC1CQEwTJ9mjRvBA4UOLD8nKVOWfh+UlK3z/177OXrfOdKl7pyn3Xf//WreyTRUoAWgBgkOAGbZHBgG1OF6zM82DWbZaUmMBptgQhGjsyYqc9ae9XFz280948NMBWInljyzsNRFLPWdnZGWrddDsjK1unuSrVN9jJsK8KuQtQCtMBjCEtImISdNKJOopIpBFpNSMbIHCSRpRR5iakjTiyzLhchUUBwCgyKiweBv/7UsQbg8isVNoMPMjAAAA0gAAABEVFGmgqK////9bP/6XCykxBTUUzLjEwMKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'); a.volume = 0; const p = a.play(); if (p && p.catch) p.catch(() => {}); } catch {}
}
document.addEventListener('pointerdown', unlockVoice, { capture: true, once: true });
function renderVoiceBtn() {
  const b = document.getElementById('voice-toggle'), r = document.getElementById('voice-vol');
  if (b) { b.textContent = voiceOn ? '🔊' : '🔇'; b.title = voiceOn ? '스킬 보이스 끄기' : '스킬 보이스 켜기'; }
  if (r) { r.value = String(Math.round(voiceVol * 100)); r.disabled = !voiceOn; }
}
/** 스킬 컷인: 스킬 이름 배너 + 연출 이미지(data/fx/<파일>, 16:9, 모바일 세로는 가운데 기준으로 양옆 잘림) */
const fxLoaded = new Set();
function preloadFx(cards) {
  for (const c of cards) for (const s of skillsOf(c.id)) {
    if (!s.fx || fxLoaded.has(s.fx) || /\.(mp4|webm)$/i.test(s.fx)) continue;
    fxLoaded.add(s.fx); const img = new Image(); img.decoding = 'async'; img.src = `data/fx/${s.fx}`;
  }
  try { preloadVoice(cards); } catch {}
}
function cutInHTML(u, name, fx, passive) {
  const media = fx ? (/\.(mp4|webm)$/i.test(fx) ? `<video src="data/fx/${fx}" autoplay muted playsinline class="cutin-media"></video>` : `<img src="data/fx/${fx}" class="cutin-media" alt="" onerror="this.remove()">`) : '';
  return `${media}<div class="cutin-text"><div class="text-[11px] md:text-xs text-zinc-200">${u.owner.name} · ${u.card.name}${passive ? ' · 패시브' : ''}</div><div class="text-xl md:text-3xl font-black tracking-tight">${passive ? '✨ ' : '⚡ '}${name}</div></div>`;
}
/** 슬래시 착지 순간(약 19%) 화면 살짝 흔들기 — 모션 줄이기 설정이면 생략 */
let impactTimer;
function slashImpact(ms) {
  if (FX_OFF() || REDUCED() || !ms) return;
  clearTimeout(impactTimer);
  impactTimer = setTimeout(() => {
    const root = document.querySelector('main') || document.body;
    root.classList.remove('fx-shake'); void root.offsetWidth; root.classList.add('fx-shake');
    setTimeout(() => root.classList.remove('fx-shake'), 330);
  }, Math.round(ms * 0.19));
}
async function cutIn(u, name, fx, passive = false) {
  playVoice(u, name);
  if (FX_OFF()) return;
  const el = $('cutin');
  el.innerHTML = cutInHTML(u, name, fx, passive);
  const ms = fxMs(fx ? 1300 : passive ? 500 : 750);
  el.style.setProperty('--dur', `${ms}ms`);
  el.className = `cutin ${fx ? 'cutin-img' : ''} fixed left-0 right-0 z-40 pointer-events-none text-center ${whoOf(u.owner) === 'me' ? 'cutin-me' : 'cutin-ai'}`;
  slashImpact(ms);
  await sleep(ms);
  el.className = 'hidden';
}
/** 패시브 발동 연출: 카드별·스킬별 게임당 첫 발동만 큰 이미지(비동기, 턴 진행을 막지 않음), 이후는 작은 글자만 */
let passiveTimer = null;
function passiveCutIn(u, name) {
  if (!S) return;
  S.fxSeen ||= new Set(); const key = `${u.uid}:${name}`;
  if (S.fxSeen.has(key)) return;
  const s = u.sk?.find(x => x.name === name);
  if (s?.fx || FX_OFF()) playVoice(u, name);
  if (FX_OFF() || !s?.fx) { if (voiceKey(u, name)) S.fxSeen.add(key); return; }
  S.fxSeen.add(key);
  const el = $('cutin');
  el.innerHTML = cutInHTML(u, name, s.fx, true);
  const ms = fxMs(1100);
  el.style.setProperty('--dur', `${ms}ms`);
  el.className = 'hidden'; void el.offsetWidth; // 애니메이션 재시작
  el.className = `cutin cutin-img fixed left-0 right-0 z-40 pointer-events-none text-center ${whoOf(u.owner) === 'me' ? 'cutin-me' : 'cutin-ai'}`;
  slashImpact(ms);
  clearTimeout(passiveTimer); passiveTimer = setTimeout(() => { el.className = 'hidden'; }, ms);
}

async function castSkill(who, u, s) {
  const p = S[who];
  if (S.over || !p.field.includes(u) || !skillState(u, s).ok) return;
  const prevBusy = S.busy; S.busy = true; selected = null;
  try {
    render();
    await withTimeout(cutIn(u, s.name, s.fx), 3000);
    pendingDying = [];
    useSkill(u, s);
    if (who === 'me') S.log.skills++;
    renderHero('me'); renderHero('ai');
    await sleep(fxMs(450));
    await withTimeout(fadeDying(), 1500);
  } catch (err) {
    reportError('skill', err);
  } finally {
    $('cutin').className = 'hidden'; resetAnim();
    S.busy = prevBusy;
    if (!prevBusy) fastForward = false;
    render();
    checkEnd();
  }
}

/** 엔진 이벤트 → 로그·연출 */
function onEngine(e) {
  if (!S) return;
  const uEl = u => u && unitEl(whoOf(u.owner), u);
  const nm = u => u.card.name;
  if (e.type === 'dealt') { if (e.src.owner === S.me) { const L = S.log, k = e.src.card.id, r = L.dmg.get(k) || { card: e.src.card, dmg: 0 }; r.dmg += e.dmg; L.dmg.set(k, r); L.total += e.dmg; } return; }
  switch (e.type) {
    case 'skill': log(`${e.unit.owner.name}: ${nm(e.unit)} ⚡[${e.skill.name}] (MP ${e.skill.mp})`, 'text-fuchsia-300'); break;
    case 'passive': log(`${e.unit.owner.name}: ${nm(e.unit)} ✨[${e.name}]${e.text ? ' — ' + e.text : ''}`, 'text-fuchsia-200'); if (!FX_OFF()) { dmgNumber(uEl(e.unit), `✨${e.name}`, '#f0abfc'); passiveCutIn(e.unit, e.name); } break;
    case 'dmg': { const el = uEl(e.unit); shake(el); dmgNumber(el, typeof e.dmg === 'number' ? `-${fmt(e.dmg)}` : e.dmg); break; }
    case 'hero': { const el = heroEl(whoOf(e.p)); shake(el); dmgNumber(el, `-${fmt(e.dmg)}`, e.kind === 'self' ? '#fca5a5' : undefined); log(`${e.p.name} 본진 ${fmt(e.dmg)} 피해${e.kind === 'self' ? ' (자기 공격)' : ''}`, 'text-orange-300'); break; }
    case 'heal': dmgNumber(uEl(e.unit), `+${fmt(e.amt)}`, '#6ee7b7'); break;
    case 'heroHeal': dmgNumber(heroEl(whoOf(e.p)), `+${fmt(e.amt)}`, '#6ee7b7'); log(`${e.p.name} 본진 HP +${fmt(e.amt)}`, 'text-emerald-300'); break;
    case 'destroy': log(`${nm(e.unit)} 파괴!`, 'text-zinc-400'); pendingDying.push(uEl(e.unit)); break;
    case 'refund': if (S.story && e.owner === S.me && e.killer?.card) { const k = String(e.killer.card.id); S.log.kills[k] = (S.log.kills[k] || 0) + 1; }
      log(`${nm(e.killer)} 처치 보상: 마나 +${e.refund}`, 'text-sky-300'); if (e.refund > 0 && !FX_OFF()) dmgNumber(heroEl(whoOf(e.owner)), `💧 +${e.refund} 마나`, '#7dd3fc'); renderHero(whoOf(e.owner)); break;
    case 'levelup': log(`${nm(e.unit)} Lv${e.level}`, 'text-amber-300'); dmgNumber(uEl(e.unit), `⬆ Lv${e.level}`, '#fcd34d'); break;
    case 'status': { const st = STATUS[e.kind]; const t = e.kind === 'mod' ? e.text : `${st?.icon || ''} ${st?.label || e.kind}`; dmgNumber(uEl(e.unit), t, '#c4b5fd'); log(`${nm(e.unit)}: ${t}`, 'text-purple-300'); break; }
    case 'immune': dmgNumber(uEl(e.unit), '🔰 면역', '#93c5fd'); break;
    case 'heroImmune': dmgNumber(heroEl(whoOf(e.p)), '🔰 무효', '#93c5fd'); break;
    case 'resist': dmgNumber(uEl(e.unit), '✳️ 면역', '#93c5fd'); break;
    case 'miss': log(`${nm(e.unit)}: ${e.text}`, 'text-zinc-400'); dmgNumber(uEl(e.unit), 'MISS', '#a1a1aa'); break;
    case 'mp': if (typeof e.amt === 'string' || e.amt > 0) dmgNumber(uEl(e.unit), `MP +${e.amt}`, '#60a5fa'); else dmgNumber(uEl(e.unit), `MP ${e.amt}`, '#60a5fa'); break;
    case 'forced': log(e.text, 'text-purple-300'); shake(uEl(e.unit)); break;
    case 'revive': log(`${e.p.name}: ${e.card.name} 부활 → 손패`, 'text-emerald-300'); break;
    case 'log': log(e.text, 'text-zinc-300'); break;
  }
}

// ===== 간단한 AI =====
async function aiTurn() {
  try {
  S.busy = true; render();
  await sleep(AI_DELAY());
  const ai = S.ai, me = S.me;
  // 1) 비싼 카드부터 낼 수 있는 만큼 소환
  // 0) 위험한 고코스트 카드 회수
  for (const u of [...ai.field]) if (aiShouldRecall(u, ai, me)) { recall('ai', u); await sleep(AI_DELAY()); }
  if (aiWantShuffle(ai, me)) { useAction('ai', 'shuffle'); await sleep(AI_DELAY()); }
  if (aiWantAccel(ai, true)) { useAction('ai', 'accel'); await sleep(AI_DELAY()); }
  { const v = aiPickSacrifice(ai, me); if (v) { doSacrifice('ai', v); await sleep(AI_DELAY()); } }
  for (const c of aiSummonOrder(ai.hand)) {
    if (canSummon(c, ai, me).ok) { summon('ai', c); await sleep(AI_DELAY()); }
  }
  for (let it; (it = aiPickItem(ai, me));) { equipItem('ai', it[1], it[0]); await sleep(AI_DELAY()); }
  if (aiWantAccel(ai)) { useAction('ai', 'accel'); await sleep(AI_DELAY()); }
  if (aiWantFieldHeal(ai)) { useAction('ai', 'fieldheal'); await sleep(AI_DELAY()); }
  if (aiWantBuff(ai)) { useAction('ai', 'buff'); await sleep(AI_DELAY()); }
  // 2) 스킬 또는 공격: 쓸 만한 스킬이 있으면 스킬(공격 대신), 아니면 유리한 교환 우선 공격
  for (const u of [...ai.field]) {
    if (S.over) break;
    if (!ai.field.includes(u) || !u.canAttack) continue;
    const sk = aiPickSkill(u);
    if (sk) { await castSkill('ai', u, sk); await sleep(AI_DELAY()); continue; }
    const best = aiPickTarget(u, ai, me);
    if (best === undefined) continue;
    await attack('ai', u, best);
    await sleep(AI_DELAY());
  }
  if (!S.over && aiWantHeal(ai)) { useAction('ai', 'heal'); await sleep(AI_DELAY()); }
  } catch (err) { reportError('aiTurn', err); }
  // 오류가 나도 턴은 반드시 넘어감
  const ai = S.ai;
  try { if (!S.over) { endTurnXp(ai); turnEnd(ai); render(); checkEnd() || checkTimeout(); } } catch (err) { reportError('aiTurnEnd', err); }
  resetAnim(); S.busy = false; fastForward = false;
  if (!S.over) startTurn('me');
}

// ===== 렌더링 =====
const RARITY = {
  'NORMAL':      { short: 'N',  label: '노멀',       cls: 'rar-n' },
  'RARE':        { short: 'R',  label: '레어',       cls: 'rar-r' },
  'HIGH RARE':   { short: 'HR', label: '하이 레어',  cls: 'rar-hr' },
  'SUPER RARE':  { short: 'SR', label: '슈퍼 레어',  cls: 'rar-sr' },
  'ULTRA RARE':  { short: 'UR', label: '울트라 레어', cls: 'rar-ur' },
  'MYTHIC RARE': { short: 'MR', label: '미식 레어',  cls: 'rar-mr' },
};
const rarityOf = c => RARITY[c.grade] || RARITY.NORMAL;
function cardHTML(c, { hp, size = 'md', dim = false } = {}) {
  const e = ELEMENTS[c.class] || ELEMENTS.WIND;
  const small = size === 'sm';
  const rar = rarityOf(c), nSk = skillsOf(c.id).length;
  return `
  <div class="card-frame ${rar.cls} relative ${small ? 'w-[64px] md:w-[96px]' : 'w-[78px] md:w-[110px]'} bg-zinc-900 rounded-xl overflow-hidden ${dim ? 'opacity-50' : ''} shadow-lg" data-grade="${rar.short}">
    <img src="${IMG}${c.id}.webp" data-id="${c.id}" class="card-img w-full aspect-[3/4] object-cover" alt="${c.name}">
    <button type="button" class="zoom-btn absolute bottom-[46px] md:bottom-[58px] right-1" data-zoom="${c.id}"${hp != null ? ` data-hp="${hp}"` : ''} title="크게 보기" aria-label="크게 보기">🔍</button>
    <div class="absolute top-1 left-1 w-6 h-6 md:w-7 md:h-7 rounded-full bg-sky-600 text-white text-[11px] md:text-xs font-black flex items-center justify-center border border-white/40">${c.cost}</div>
    <div class="absolute top-1 right-1 text-sm md:text-base" title="${e.label}">${e.icon}</div>
    <div class="rar-badge absolute left-1 top-7 md:top-9" title="${rar.label}">${rar.short}</div>
    ${nSk ? `<div class="sk-count absolute right-1 top-6 md:top-8" title="스킬 ${nSk}개">✦${nSk}</div>` : ''}
    <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black via-black/85 to-transparent px-1 pt-4 pb-1">
      <div class="text-[10px] md:text-xs font-bold truncate">${c.name}</div>
      <div class="text-[9px] md:text-[10px] text-amber-400 font-bold">⚡${fmt(c.power)}</div>
      <div class="flex justify-between whitespace-nowrap tracking-tighter ${small ? 'text-[8px]' : 'text-[9px]'} md:text-[11px] font-bold">
        <span class="text-orange-400">⚔${fmt(c.ATK)}</span><span class="text-red-400">♥${fmt(hp ?? c.HP)}</span><span class="text-sky-400">🛡${fmt(c.DEF)}</span>
      </div>
    </div>
  </div>`;
}

function fixImages(root) {
  root.querySelectorAll('img.card-img').forEach(img => {
    img.onerror = () => { img.onerror = null; img.src = `${IMG}${img.dataset.id}.webp`; };
  });
}

function renderHero(who) {
  const p = S[who], max = p.maxHp || RULES.HERO_HP;
  $(`${who}-hp`).textContent = `${fmt(p.hp)} / ${fmt(max)}`;
  $(`${who}-hpbar`).style.width = Math.max(0, p.hp / max * 100) + '%';
  $(`${who}-mana`).textContent = `${p.mana} / ${p.maxMana}` + (p.accel ? ` ⚙️+${RULES.MANA_PER_TURN + p.accel * RULES.ACCEL_BONUS}/턴` : '');
  $(`${who}-deck`).textContent = p.deck.length;
  $(`${who}-handcount`).textContent = p.hand.length;
}

// ===== 내 남은 턴 표시 =====
const MY_MAX = RULES.MAX_TURNS / 2;
function myTurnsLeft() { return Math.max(0, MY_MAX - S.myTurns + (S.turn === 'me' && !S.over ? 1 : 0)); }
function renderTurnsLeft() {
  const el = $('my-turns'); if (!el) return;
  const n = myTurnsLeft(), lvl = n <= 2 ? 'crit' : n <= 5 ? 'warn' : 'ok';
  el.className = `turns-${lvl}`;
  $('my-turns-n').textContent = n; $('my-turns-max').textContent = '/' + MY_MAX;
  $('my-turns-pips').className = `mt-1 turns-${lvl}-p`;
  $('my-turns-pips').innerHTML = Array.from({ length: MY_MAX }, (_, i) => `<i class="${i < n ? 'on' : ''}"></i>`).join('');
}
function lastTurnToast() {
  const t = document.createElement('div');
  t.className = 'last-turn-toast'; t.textContent = '⏳ 마지막 턴!';
  document.body.appendChild(t); setTimeout(() => t.remove(), 2200);
}

const hpPrev = new Map();
const hpText = t => String(t || '').replace(/체력/g, 'HP');
function render() {
  if (S) preloadFx([...S.me.field, ...S.ai.field].map(u => u.base || u.card));
  renderTurnsLeft();
  if (!S) return;
  renderHero('me'); renderHero('ai');
  const myTurn = S.turn === 'me' && !S.over && !S.busy;
  const tl = `${Math.min(S.totalTurns, RULES.MAX_TURNS)}/${RULES.MAX_TURNS}턴`;
  $('turn-info').textContent = S.over ? '게임 종료' : (S.turn === 'me' ? `내 턴 · ${tl}` : `상대 턴 · ${tl}...`);
  $('end-turn').disabled = !myTurn;
  for (const type of Object.keys(ACTIONS)) {
    const c = canAction(type, S.me), btn = $(`act-${type}`);
    btn.disabled = !myTurn || !c.ok;
    btn.querySelector('.reason').textContent = !myTurn ? '' : (c.ok ? '' : c.reason);
  }
  { const btn = $('act-merc'), done = S.mercBought >= Merc.MAX_PER_BATTLE;
    btn.disabled = !myTurn || done || !!S.story;
    btn.querySelector('.reason').textContent = S.story ? '스토리 불가' : myTurn && done ? '이번 판 고용 완료' : ''; }
  if (S.story) { const b = $('act-shuffle'); b.disabled = true; b.querySelector('.reason').textContent = '스토리 불가'; }
  $('attack-all').disabled = !myTurn || !S.me.field.some(u => u.canAttack);
  const tg = attackTargets(S.me, S.ai);
  $('ai-hero').classList.toggle('ring-4', selected != null && tg.hero);
  $('ai-hero').classList.toggle('ring-red-500', selected != null && tg.hero);
  $('ai-hero').classList.toggle('opacity-70', S.turn === 'me' && !tg.hero);
  $('hero-hint').textContent = S.story && S.over ? '' : S.ai.noBase ? (S.over ? '' : '⚔️ 일반전: 상대 카드를 모두 쓰러뜨리면 승리') : S.turn === 'me' && !S.over ? (tg.hero ? '🎯 상대 진영 공격 가능' : '🛡️ ' + tg.reason) : '';
  $('hero-hint').className = `text-center text-[11px] md:text-xs font-bold ${tg.hero ? 'text-emerald-400' : 'text-amber-300'}`;

  for (const who of ['ai', 'me']) {
    const p = S[who];
    $(`${who}-syn`).innerHTML = [
      ...p.activeSyn.map(x => { const el = ELEMENTS[x.cls] || {}; return `<span class="px-1.5 rounded-full bg-white/10 text-[10px] font-bold" title="속성 시너지: ${el.label || x.cls} ${x.n}장 → ATK·DEF +${Math.round(x.pct * 100)}%">${el.icon || ''}×${x.n} +${Math.round(x.pct * 100)}%</span>`; }),
      ...p.activeCombos.map(c => `<span class="px-1.5 rounded-full bg-fuchsia-700/60 text-[10px] font-bold" title="조합 [${c.name}]: ${c.scope === 'all' ? '아군 전체' : '조합 카드'} ${hpText(c.desc)} +${Math.round(c.value * 100)}%">🔗${c.name}</span>`),
      p.actionLock > 0 ? '<span class="px-1.5 rounded-full bg-red-800 text-[10px] font-bold" title="셔플·보강·강화·필드 회복 사용 불가">🔒고유기술 봉인</span>' : '',
      p.st?.heroShield ? '<span class="px-1.5 rounded-full bg-sky-800 text-[10px] font-bold" title="본진 방어력 +300% (피해 1/4)">🛡️본진 방어</span>' : '',
      p.st?.heroInvuln ? '<span class="px-1.5 rounded-full bg-sky-800 text-[10px] font-bold" title="본진 공격 무효">🔰본진 무적</span>' : '',
    ].join('');
    const box = $(`${who}-field`); box.innerHTML = '';
    const bossBox = $(`${who}-boss`); if (bossBox) { bossBox.innerHTML = ''; bossBox.classList.toggle('hidden', !S[who].field.some(u => u.undying)); }
    if (!S[who].field.some(u => !u.undying)) box.innerHTML = '<div class="text-zinc-600 text-xs self-center">빈 필드</div>';
    S[who].field.forEach(u => {
      const w = document.createElement('div');
      const isSel = selected === u.uid;
      const ready = who === 'me' && u.canAttack && myTurn;
      w.className = `unit ${u.undying ? 'boss-unit' : ''} cursor-pointer transition ${isSel ? '-translate-y-2 drop-shadow-[0_0_10px_#34d399]' : ''} ${ready ? 'ready' : ''} ${selected != null && who === 'ai' && tg.units.includes(u) ? 'target' : ''}`;
      w.dataset.uid = u.uid;
      const hero = u.level >= RULES.LEVEL_MAX;
      const sts = statusIcons(u);
      const skReady = who === 'me' && myTurn && u.sk.some(s => skillState(u, s).ok);
      const icons = [u.items?.weapon && ITEMS.weapon.icon, u.items?.armor && ITEMS.armor.icon, ...u.skills.map(k => SKILLS[k]?.icon)].filter(Boolean);
      w.innerHTML = `<div class="relative ${hero ? 'hero-card' : ''}">${cardHTML(u.card, { hp: u.hp, size: 'sm', dim: who === 'me' && !u.canAttack && myTurn })}` +
        `<div class="lv-badge absolute -top-1.5 left-1/2 -translate-x-1/2 px-1.5 rounded-full ${hero ? 'bg-gradient-to-r from-yellow-300 to-amber-500 shadow-[0_0_8px_#fbbf24]' : u.level > 1 ? 'bg-amber-400' : 'bg-zinc-600 text-white'} text-black text-[9px] md:text-[10px] font-black whitespace-nowrap">${hero ? '👑 ' : ''}Lv${u.level}</div>` +
        (icons.length ? `<div class="item-icons absolute top-7 right-0.5 flex flex-col text-[11px] md:text-sm leading-tight drop-shadow">${icons.map(x => `<span>${x}</span>`).join('')}</div>` : '') +
        (sts.length ? `<div class="status-icons absolute top-7 left-0.5 flex flex-col text-[11px] md:text-sm leading-tight drop-shadow">${sts.map(x => `<span title="${x.title}">${x.icon}</span>`).join('')}</div>` : '') + `</div>` +
        `<div class="hp-bar h-1.5 bg-white/10 rounded-full mt-0.5 overflow-hidden" title="HP ${u.hp}/${u.maxHp}"><div class="hp-fill h-full bg-red-500" data-to="${u.maxHp ? Math.max(0, Math.min(100, u.hp / u.maxHp * 100)) : 0}" style="width:${hpPrev.get(String(u.uid)) ?? (u.maxHp ? Math.max(0, Math.min(100, u.hp / u.maxHp * 100)) : 0)}%"></div></div>` +
        `<div class="mp-bar h-1.5 bg-white/10 rounded-full mt-0.5 overflow-hidden" title="MP ${u.mp}/${u.maxMp} (+${u.mpRegen}/턴)"><div class="h-full bg-blue-500" style="width:${u.maxMp ? Math.min(100, u.mp / u.maxMp * 100) : 0}%"></div></div>` +
        `<div class="flex justify-center gap-1 h-4">${ready ? '<span class="text-[10px] text-emerald-400 font-bold">공격 가능</span>' : ''}${skReady ? '<button class="skill-btn text-[10px] px-1 rounded bg-fuchsia-600 hover:bg-fuchsia-500 font-bold">✦스킬</button>' : ''}</div>`;
      w.onclick = ev => { if (dragJustEnded) { ev.stopPropagation(); return; } onUnitClick(who, u); };
      if (who === 'me' && myTurn) enableDrag(w, u);
      const sb = w.querySelector('.skill-btn'); if (sb) sb.onclick = ev => { ev.stopPropagation(); showDetail(u.card, { hp: u.hp, unit: u }); };
      if (u.undying && bossBox) {   // 스토리 보스: 진영 안에 표시 (공격 대상 아님, 쓰러지지 않음)
        w.insertAdjacentHTML('afterbegin', '<div class="boss-crown" title="보스: 진영 안에 있어 공격할 수 없고 쓰러지지 않아요">👑</div>');
        const wrap = document.createElement('div'); wrap.className = 'flex items-center gap-2';
        wrap.appendChild(w);
        wrap.insertAdjacentHTML('beforeend', `<div class="text-[10px] md:text-xs leading-snug"><div class="font-black text-amber-300">👑 보스</div><div class="text-zinc-300 font-bold truncate max-w-[64px] md:max-w-[120px]">${u.card.name}</div><div class="text-zinc-400">진영 안 · 불사</div><div class="text-zinc-500 hidden md:block">매 턴 공격·스킬 사용</div></div>`);
        bossBox.appendChild(wrap);
      } else box.appendChild(w);
    });
    fixImages(box); if (bossBox) fixImages(bossBox);
    requestAnimationFrame(() => [...box.querySelectorAll('.hp-fill'), ...(bossBox ? bossBox.querySelectorAll('.hp-fill') : [])].forEach(f => { f.style.width = f.dataset.to + '%'; hpPrev.set(f.closest('[data-uid]').dataset.uid, +f.dataset.to); }));
  }

  const hand = $('me-hand'); hand.innerHTML = '';
  renderSortBar();
  sortedHand(S.me.hand).forEach(c => {
    const w = document.createElement('div');
    const ok = myTurn && canSummon(c, S.me, S.ai).ok;
    w.className = `hand-card shrink-0 cursor-pointer transition hover:-translate-y-2 ${ok ? '' : 'opacity-60'}`;
    w.dataset.id = c.id;
    w.innerHTML = cardHTML(c);
    w.onclick = () => showDetail(c, { fromHand: true });
    hand.appendChild(w);
  });
  fixImages(hand);
  $('ai-handcards').innerHTML = S.ai.hand.map(() => '<div class="w-4 h-6 md:w-5 md:h-7 rounded bg-gradient-to-br from-zinc-700 to-zinc-900 border border-white/20"></div>').join('');
}

// ===== 손패 정렬 =====
const SORT_KEY = 'tcg_hand_sort';
const GRADE_RANK = { 'NORMAL': 0, 'RARE': 1, 'HIGH RARE': 2, 'SUPER RARE': 3, 'ULTRA RARE': 4, 'MYTHIC RARE': 5 };
const SORTS = { none: '획득순', grade: '등급순', cost: '코스트순', atk: '공격력순', def: '방어력순', hp: 'HP순' };
const sortVal = { grade: c => GRADE_RANK[c.grade] ?? 0, cost: c => c.cost, atk: c => c.ATK, def: c => c.DEF, hp: c => c.HP };
let handSort = localStorage.getItem(SORT_KEY) || 'none';
if (!SORTS[handSort]) handSort = 'none';
function sortedHand(hand) {
  const f = sortVal[handSort]; if (!f) return [...hand];
  return [...hand].sort((a, b) => (f(b) || 0) - (f(a) || 0) || (b.cost || 0) - (a.cost || 0));
}
function renderSortBar() {
  const bar = $('hand-sort'); if (!bar) return;
  bar.innerHTML = '<span class="text-zinc-400 mr-1">정렬</span>' + Object.entries(SORTS).map(([k, v]) =>
    `<button data-sort="${k}" class="px-2 py-0.5 rounded-full border ${k === handSort ? 'bg-emerald-600 border-emerald-400 text-white' : 'bg-zinc-800 border-white/15 text-zinc-300'}">${v}</button>`).join('');
  bar.querySelectorAll('[data-sort]').forEach(b => b.onclick = () => { handSort = b.dataset.sort; localStorage.setItem(SORT_KEY, handSort); render(); });
}

// ===== 필드 카드 드래그 앤 드롭 (내 턴만) =====
let dragJustEnded = false;
const DRAG_THRESHOLD = 8;
function enableDrag(el, u) {
  el.style.touchAction = 'none';
  el.addEventListener('pointerdown', e => {
    if (e.button > 0 || e.target.closest('.skill-btn')) return;
    const sx = e.clientX, sy = e.clientY; let dragging = false;
    const move = ev => {
      const dx = ev.clientX - sx, dy = ev.clientY - sy;
      if (!dragging && Math.hypot(dx, dy) < DRAG_THRESHOLD) return;
      if (!dragging) { dragging = true; el.classList.add('dragging'); el.style.zIndex = 50; el.style.transition = 'none'; try { el.setPointerCapture(e.pointerId); } catch {} }
      el.style.transform = `translate(${dx}px, ${dy}px) scale(1.06)`;
    };
    const up = ev => {
      window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); window.removeEventListener('pointercancel', up);
      if (!dragging) return;
      dragJustEnded = true; setTimeout(() => { dragJustEnded = false; }, 0);
      const f = S.me.field, from = f.indexOf(u);
      if (ev.type !== 'pointercancel' && from >= 0 && S.turn === 'me' && !S.busy && !S.over) {
        const others = [...$('me-field').children].filter(x => x !== el && x.dataset.uid);
        let to = others.findIndex(x => { const r = x.getBoundingClientRect(); return ev.clientX < r.left + r.width / 2; });
        if (to < 0) to = others.length;
        f.splice(from, 1); f.splice(to, 0, u);
      }
      render();
    };
    window.addEventListener('pointermove', move); window.addEventListener('pointerup', up); window.addEventListener('pointercancel', up);
  });
}

function onUnitClick(who, u) {
  const myTurn = S.turn === 'me' && !S.over && !S.busy;
  if (who === 'me') {
    if (myTurn && u.canAttack && selected !== u.uid) { selected = u.uid; render(); return; }
    if (selected === u.uid) { selected = null; render(); }
    showDetail(u.card, { hp: u.hp, unit: u });
  } else {
    if (myTurn && selected != null) {
      const a = S.me.field.find(x => x.uid === selected);
      if (a) { attack('me', a, u); return; }
    }
    showDetail(u.card, { hp: u.hp, view: u });
  }
}

function onHeroClick() {
  if (selected == null || S.turn !== 'me' || S.busy) return;
  const a = S.me.field.find(x => x.uid === selected);
  if (a) attack('me', a, null); // 규칙 위반이면 attack()이 사유를 보여줌
}

function showDetail(c, { fromHand = false, hp, unit = null, view = null } = {}) {
  const e = ELEMENTS[c.class] || ELEMENTS.WIND;
  const check = fromHand ? canSummon(c, S.me, S.ai) : null;
  const myTurn = S.turn === 'me' && !S.over && !S.busy;
  $('detail-body').innerHTML = `
    <div class="flex gap-4">
      <div class="relative shrink-0"><img src="${IMG}${c.id}.webp" data-id="${c.id}" class="card-img w-32 md:w-40 aspect-[3/4] object-cover rounded-xl ring-2 ${e.ring}">${window.rarityStars?.(c, c.ex ? 'ex' : 'base', 'rstars-over') || ''}<button type="button" class="zoom-btn absolute bottom-1 right-1" data-zoom="${c.id}"${c.ex ? ` data-ex="${c.ex}" data-name="${String(c.name).replace(/[&"<>]/g, ch => `&#${ch.charCodeAt(0)};`)}"` : ''}${hp != null ? ` data-hp="${hp}"` : ''} title="크게 보기" aria-label="크게 보기">🔍</button></div>
      <div class="flex-1 min-w-0">
        <div class="text-2xl font-black">${c.name}</div>
        <div class="text-zinc-400 text-sm"><span class="rar-badge rar-inline ${rarityOf(c).cls}">${rarityOf(c).short}</span> ${c.grade} · 스킬 ${skillsOf(c.id).length}개 · ${c.region} · ${c.age}세</div>
        <div class="mt-2 ${e.color} font-bold">${e.icon} ${e.label} (${c.class})</div>
        <div class="text-zinc-300 text-sm">타입: ${c.attribute}</div>
        <div class="mt-2 text-amber-400 font-black text-xl">⚡ ${fmt(c.power)}</div>
        <div class="text-sky-400 font-bold">코스트 ${c.cost}</div>
      </div>
    </div>
    <div class="grid grid-cols-3 gap-2 mt-4 text-center">
      <div class="bg-zinc-800 rounded-xl p-2"><div class="text-[10px] text-zinc-400">ATK</div><div class="font-bold text-orange-400">${fmt(c.ATK)}</div></div>
      <div class="bg-zinc-800 rounded-xl p-2"><div class="text-[10px] text-zinc-400">HP</div><div class="font-bold text-red-400">${hp != null ? fmt(hp) + ' / ' : ''}${fmt(c.HP)}</div></div>
      <div class="bg-zinc-800 rounded-xl p-2"><div class="text-[10px] text-zinc-400">DEF</div><div class="font-bold text-sky-400">${fmt(c.DEF)}</div></div>
    </div>
    ${skillListHTML(c, unit || view, myTurn)}
    ${fromHand ? `
      ${check.ok || !myTurn ? '' : `<div id="summon-reason" class="mt-3 text-sm text-red-400">${check.reason}</div>`}
      <button id="summon-btn" ${check.ok && myTurn ? '' : 'disabled'} class="mt-4 w-full py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 disabled:opacity-40 text-black font-bold">소환하기</button>` : ''}
    ${unit ? `
      <div class="mt-3 flex items-center gap-2 text-sm"><span class="font-black ${unit.level >= RULES.LEVEL_MAX ? 'text-amber-300' : ''}">${unit.level >= RULES.LEVEL_MAX ? '👑 영웅 ' : ''}Lv${unit.level}</span>
        ${unit.level < RULES.LEVEL_MAX ? `<div class="flex-1 h-2 bg-white/10 rounded-full overflow-hidden"><div class="h-full bg-amber-400" style="width:${Math.min(100, unit.xp / xpToNext(unit.level) * 100)}%"></div></div><span class="text-[11px] text-zinc-400">XP ${unit.xp}/${xpToNext(unit.level)}</span>` : '<span class="text-[11px] text-zinc-400">최대 레벨</span>'}</div>
      ${unit.skills.length ? `<div class="mt-1 text-xs text-zinc-300">${unit.skills.map(k => `${SKILLS[k]?.icon || ''} ${SKILLS[k]?.label || k}`).join(' · ')}</div>` : ''}
      <div class="grid grid-cols-2 gap-2 mt-3">${Object.entries(ITEMS).map(([type, it]) => { const ce = canEquip(type, unit, S.me); return `
        <button data-equip="${type}" ${ce.ok && myTurn ? '' : 'disabled'} class="py-2 rounded-xl bg-amber-500 hover:bg-amber-400 disabled:opacity-40 text-black text-sm font-bold">${it.icon} ${it.label} ${it.desc()} <span class="text-sky-900">💧${it.cost()}</span><div class="text-[10px] font-normal h-3">${unit.items?.[type] ? '장착됨' : (!myTurn || ce.ok ? '' : ce.reason)}</div></button>`; }).join('')}</div>` : ''}
    ${unit ? (() => { const rc = canRecall(unit, S.me); return `
      ${rc.ok || !myTurn ? '' : `<div id="recall-reason" class="mt-3 text-sm text-red-400">${rc.reason}</div>`}
      <button id="recall-btn" ${rc.ok && myTurn ? '' : 'disabled'} class="mt-4 w-full py-3 rounded-2xl bg-sky-500 hover:bg-sky-400 disabled:opacity-40 text-black font-bold">회수 (마나 ${rc.cost})</button>
      <div class="text-[11px] text-zinc-500 mt-1 text-center">손패로 돌아가며 HP가 회복되고, 레벨·XP·아이템은 초기화됩니다</div>`; })() : ''}
    ${unit ? (() => { const sc = canSacrifice(unit, S.me); return `
      <button id="sacrifice-btn" ${sc.ok && myTurn ? '' : 'disabled'} class="mt-2 w-full py-2.5 rounded-2xl bg-rose-600 hover:bg-rose-500 disabled:opacity-40 text-white font-bold">🩸 희생 (마나 +${sc.gain})${sc.ok || !myTurn ? '' : ` — ${sc.reason}`}</button>
      <div class="text-[11px] text-zinc-500 mt-1 text-center">카드를 없애고 코스트의 ${Math.round(RULES.SACRIFICE_RATIO * 100)}%를 마나로 (턴당 1회)</div>`; })() : ''}`;
  fixImages($('detail-body'));
  if (unit) $('detail-body').querySelectorAll('[data-skill]').forEach(b => b.onclick = () => { const s = unit.sk[+b.dataset.skill]; hideModal('detail'); castSkill('me', unit, s); });
  if (unit) $('detail-body').querySelectorAll('[data-equip]').forEach(b => b.onclick = () => { const r = equipItem('me', unit, b.dataset.equip); if (r.ok) showDetail(unit.card, { hp: unit.hp, unit }); });
  if (unit && $('sacrifice-btn')) $('sacrifice-btn').onclick = () => { const r = doSacrifice('me', unit); if (r.ok) hideModal('detail'); };
  if (unit && $('recall-btn')) $('recall-btn').onclick = () => { const r = recall('me', unit); if (r.ok) hideModal('detail'); };
  if (fromHand) $('summon-btn').onclick = () => { const r = summon('me', c); if (r.ok) hideModal('detail'); };
  showModal('detail');
}

function skillListHTML(c, unit, myTurn) {
  const list = unit ? unit.sk : skillsOf(c.id);
  const mine = unit && unit.owner === S.me;
  const head = unit ? `<div class="mt-3 flex items-center gap-2 text-xs"><span class="text-blue-300 font-bold">MP ${unit.mp}/${unit.maxMp}</span><div class="flex-1 h-2 bg-white/10 rounded-full overflow-hidden"><div class="h-full bg-blue-500" style="width:${unit.mp / unit.maxMp * 100}%"></div></div><span class="text-zinc-400">턴당 +${unit.mpRegen}</span></div>` +
    (statusIcons(unit).length ? `<div class="mt-1 text-xs text-purple-300">${statusIcons(unit).map(x => `${x.icon} ${x.title}`).join(' · ')}</div>` : '') : '';
  if (!list.length) return head;
  return head + `<div class="mt-3 space-y-2 max-h-64 overflow-y-auto pr-1">${list.map((s, i) => {
    const st = unit ? skillState(unit, s) : { ok: false, reason: `Lv${s.unlock} 해금` };
    const locked = (unit ? unit.level : 1) < s.unlock;
    return `<div class="rounded-xl p-2 ${locked ? 'bg-zinc-800/50 opacity-60' : 'bg-zinc-800'}">
      <div class="flex items-center gap-1.5 flex-wrap"><span class="px-1.5 rounded text-[10px] font-bold ${TYPE_COLOR[s.type] || 'bg-zinc-600'}">${s.type}</span><span class="text-[10px] text-zinc-400">${s.mode === 'active' ? '액티브' : '패시브'}</span><span class="font-bold text-sm">${s.name}</span>
        <span class="ml-auto text-[10px] text-zinc-400">${locked ? '🔒' : ''}Lv${s.unlock}${s.mode === 'active' ? ` · MP ${s.mp} · 쿨 ${s.cooldown}` : ''}</span></div>
      <div class="text-[11px] text-zinc-300 mt-0.5">${hpText(s.desc)}${s.note ? ` <span class="text-zinc-500">(${hpText(s.note)})</span>` : ''}</div>
      ${s.mode === 'active' && mine ? `<button data-skill="${i}" ${st.ok && myTurn ? '' : 'disabled'} class="mt-1 w-full py-1.5 rounded-lg bg-fuchsia-600 hover:bg-fuchsia-500 disabled:opacity-40 text-xs font-bold">${st.ok ? '사용 (공격 대신)' : st.reason}</button>` : ''}
      ${s.mode === 'passive' && unit ? `<div class="text-[10px] mt-0.5 ${locked ? 'text-zinc-500' : 'text-emerald-400'}">${locked ? `Lv${s.unlock}에 해금` : (unit.fired[s.name] ? '발동됨' : '활성')}</div>` : ''}
    </div>`; }).join('')}</div>`;
}

function showModal(id) { $(id).classList.remove('hidden'); $(id).classList.add('flex'); }
function hideModal(id) { $(id).classList.add('hidden'); $(id).classList.remove('flex'); }

function renderStats() {
  const s = Stats.load();
  $('stats').textContent = `${window.VRCloud?.user ? '☁️ ' : ''}아케이드 전적: ${s.wins}승 ${s.losses}패${s.draws ? ` ${s.draws}무` : ''}`;
}

// ===== 용병 고용 UI =====
function renderMerc() {
  $('merc-list').innerHTML = S.mercOffer.map(c => {
    const r = Merc.canBuy(c, S.me), price = Merc.price(c);
    return `<div class="flex flex-col items-center gap-1">${cardHTML(c, { dim: !r.ok })}
      <button data-merc="${c.id}" ${r.ok ? '' : 'disabled'} class="w-full px-2 py-1.5 rounded-lg bg-amber-400 hover:bg-amber-300 disabled:bg-zinc-700 disabled:text-zinc-400 text-black text-xs font-bold">${r.hired ? '✅ 고용됨' : `💧${price}`}</button>
      <div class="text-[10px] h-3 ${r.ok ? 'text-zinc-500' : r.hired ? 'text-amber-300' : 'text-red-400'}">${r.ok ? `기본 ${c.cost} ×${Merc.PRICE[c.grade]}` : r.reason}</div></div>`;
  }).join('');
  $('merc-msg').textContent = `보유 마나 💧${S.me.mana}`;
  $('merc-list').querySelectorAll('[data-merc]').forEach(b => b.onclick = () => buyMerc(b.dataset.merc));
}
function buyMerc(id) {
  if (S.turn !== 'me' || S.over || S.busy) return;
  const c = S.mercOffer.find(x => String(x.id) === String(id)), r = c && Merc.canBuy(c, S.me);
  if (!r?.ok) return;
  S.me.mana -= r.cost; S.mercBought++; S.mercHired = String(c.id); S.log.merc = c;
  S.me.hand.push(c);
  preloadFx([c]);
  log(`나: 🗡️ 용병 ${c.name} 고용 (마나 ${r.cost}) — 손패에 추가 (이번 판 한정)`, 'text-amber-300');
  floatText(`🗡️ ${c.name} 고용!`, 'text-amber-300', 'me');
  hideModal('merc'); render();
}
$('act-merc').onclick = () => { if (S?.story || S?.turn !== 'me' || S.over || S.busy) return; renderMerc(); showModal('merc'); };

// ===== 초기화 =====
document.querySelectorAll('[data-close]').forEach(b => b.onclick = () => hideModal(b.dataset.close));
// 바깥(어두운 배경) 탭 → 닫기. 누르기 시작과 끝이 모두 배경일 때만 (패널 안 스크롤/드래그로는 안 닫힘)
const MODAL_IDS = ['detail', 'help', 'endturn-confirm', 'merc'];
for (const id of MODAL_IDS) { const m = $(id); let downOnBg = false;
  m.addEventListener('pointerdown', e => { downOnBg = e.target === m; });
  m.addEventListener('click', e => { if (downOnBg && e.target === m) hideModal(id); downOnBg = false; }); }
document.addEventListener('keydown', e => { if (e.key !== 'Escape' || $('zoom-view')?.classList.contains('open')) return;
  const open = MODAL_IDS.filter(id => !$(id).classList.contains('hidden')); if (open.length) hideModal(open[open.length - 1]); });
// 턴 종료 확인: 행동 가능한 카드가 남아 있으면 물어봄 (내 턴 UI 전용, AI·시뮬레이터와 무관)
const CONFIRM_KEY = 'tcg_skip_endturn_confirm';
function idleUnits() {
  const tg = attackTargets(S.me, S.ai);
  if (!tg.hero && !tg.units.length) return [];
  return S.me.field.filter(u => u.canAttack && !u.st?.para && !u.st?.confuse && !u.st?.stun);
}
function requestEndTurn() {
  if (S.turn !== 'me' || S.over || S.busy) return;
  const n = idleUnits().length;
  if (!n || localStorage.getItem(CONFIRM_KEY) === '1') return endTurn();
  $('endturn-msg').textContent = `행동 안 한 카드가 ${n}장 있어요. 턴을 넘길까요?`;
  $('endturn-noask').checked = false;
  showModal('endturn-confirm');
}
$('endturn-ok').onclick = () => { if ($('endturn-noask').checked) localStorage.setItem(CONFIRM_KEY, '1'); hideModal('endturn-confirm'); endTurn(); };
$('endturn-cancel').onclick = () => hideModal('endturn-confirm');
$('end-turn').onclick = requestEndTurn;
$('attack-all').onclick = attackAll;
for (const type of Object.keys(ACTIONS)) $(`act-${type}`).onclick = () => { if (S.story && type === 'shuffle') return; if (S.turn === 'me' && !S.busy && !S.over) useAction('me', type); };
$('ai-hero').onclick = onHeroClick;
$('help-btn').onclick = () => showModal('help');
$('main-help').onclick = () => showModal('help');
$('main-skip').onclick = () => { skipFx = !skipFx; localStorage.setItem(SKIP_KEY, skipFx ? '1' : '0'); renderSkipBtn(); };
$('voice-toggle').onclick = e => { e.stopPropagation(); voiceOn = !voiceOn; localStorage.setItem(VOICE_ON_KEY, voiceOn ? '1' : '0'); if (!voiceOn && voiceCur) try { voiceCur.pause(); } catch {} renderVoiceBtn(); };
$('voice-vol').oninput = e => { voiceVol = (+e.target.value || 0) / 100; localStorage.setItem(VOICE_VOL_KEY, String(voiceVol)); if (voiceCur) voiceCur.volume = voiceVol; };
$('voice-vol').onclick = e => e.stopPropagation();
renderVoiceBtn();
$('fx-skip').onclick = e => { e.stopPropagation(); skipFx = !skipFx; localStorage.setItem(SKIP_KEY, skipFx ? '1' : '0'); if (S?.busy) fastForward = true; renderSkipBtn(); };
// 연출 중 화면을 누르면 현재 연출 빨리 감기
$('game').addEventListener('click', () => { if (S?.busy && !S.over) fastForward = true; }, true);
renderSkipBtn();
$('share-btn').onclick = shareResult;
$('restart-btn').onclick = () => { renderStats(); startGame(); };
/** 스토리 모드 전투 시작 (js/story.js에서 호출) */
function startStory(cfg) { hideModal('detail'); startGame(cfg); }
$('home-btn').onclick = () => { $('end-screen').classList.add('hidden'); $('game').classList.add('hidden'); $('start-screen').classList.remove('hidden'); renderStats(); };
renderStats();
window.addEventListener('vr:user', renderStats);   // 로그인·로그아웃·계정 변경 시 바로 갱신

(async () => {
  try {
    POOL = parseCSV(await (await fetch('data/cards.csv')).text()); setCardPool(POOL);
    const [sk, co] = await Promise.all(['data/skills.json', 'data/combos.json'].map(u => fetch(u).then(r => r.json())));
    setSkillData(sk, co); setEmitter(onEngine);
    $('start-btn').disabled = false; $('start-btn').textContent = '⚔️ 아케이드 모드';
    $('start-btn').onclick = () => startGame();
    window.dispatchEvent(new CustomEvent('tcg:ready'));
  } catch (e) { $('start-btn').textContent = '카드 데이터를 불러오지 못했어요'; }
})();

// 테스트/디버그용
// 디버그: 카드 배치 TCG.put('me', id, 레벨)
function debugPut(who, id, lv = 1) { const c = POOL.find(x => String(x.id) === String(id)); const u = placeUnit(S[who], c, makeUnit); while (u.level < lv) gainXp(u, xpToNext(u.level)); u.mp = u.maxMp; render(); return u; }
function dupCheck() {
  const out = [];
  for (const who of ['me', 'ai']) { const P = S[who], seen = new Map();
    for (const [where, list] of [['deck', P.deck], ['hand', P.hand], ['field', P.field.map(u => u.base)]]) for (const c of list) { const k = String(c.id); if (seen.has(k)) out.push(`${who}:${c.name} ${seen.get(k)}+${where}`); else seen.set(k, where); } }
  return out;
}
// ===== 이미지 크게 보기 (🔍 버튼 전용) =====
function openZoom({ src, title, sub = '', stats = '', stars = '' }) {
  let ov = $('zoom-view');
  if (!ov) { ov = document.createElement('div'); ov.id = 'zoom-view'; document.body.appendChild(ov);
    ov.addEventListener('click', e => { if (!e.target.closest('.zoom-img, .zoom-info') || e.target.closest('.zoom-close')) closeZoom(); }); }
  ov.innerHTML = `<button type="button" class="zoom-close" aria-label="닫기">✕</button>
    ${stars}<img class="zoom-img" src="${src}" alt="${title}">
    <div class="zoom-info"><div class="text-xl font-black">${title}</div>${sub ? `<div class="text-sm text-zinc-300 mt-0.5">${sub}</div>` : ''}${stats ? `<div class="mt-1 font-bold text-sm flex gap-3 justify-center flex-wrap">${stats}</div>` : ''}</div>`;
  ov.classList.add('open');
}
function closeZoom() { const ov = $('zoom-view'); if (ov) ov.classList.remove('open'); }
function zoomFromBtn(b) {
  const c = POOL.find(x => String(x.id) === b.dataset.zoom); if (!c) return;
  const r = rarityOf(c), e = ELEMENTS[c.class] || ELEMENTS.WIND, hp = b.dataset.hp;
  openZoom({ src: `${IMG}${c.id}.webp`, title: b.dataset.name || c.name, stars: window.rarityStars?.(c, b.dataset.ex ? 'ex' : 'base', 'rstars-lg') || '',   // 스토리 EX 카드: 빨간 별
    sub: `<span class="rar-badge rar-inline ${r.cls}">${r.short}</span> ${r.label} · ${e.icon} ${e.label} · 코스트 ${c.cost}`,
    stats: `<span class="text-amber-400">⚡${fmt(c.power)}</span><span class="text-orange-400">⚔ ATK ${fmt(c.ATK)}</span><span class="text-red-400">♥ HP ${hp != null ? fmt(+hp) + ' / ' : ''}${fmt(c.HP)}</span><span class="text-sky-400">🛡 DEF ${fmt(c.DEF)}</span>` });
}
// 캡처 단계에서 가로채서 카드 선택/드래그/상세창이 같이 동작하지 않게 함
['pointerdown', 'mousedown', 'touchstart'].forEach(t => document.addEventListener(t, e => { if (e.target.closest?.('.zoom-btn')) e.stopPropagation(); }, { capture: true, passive: true }));
document.addEventListener('click', e => { const b = e.target.closest?.('.zoom-btn'); if (!b) return; e.stopPropagation(); e.preventDefault(); zoomFromBtn(b); }, true);
document.addEventListener('keydown', e => { if (e.key === 'Escape' && $('zoom-view')?.classList.contains('open')) { e.stopPropagation(); closeZoom(); } }, true);

window.TCG = { voiceTest(k) { if (!voiceSet?.has(k)) return false; const a = voiceAudio(k); a.volume = voiceVol; a.currentTime = 0; voiceCur = a; a.play().catch(() => {}); return true; }, get voiceActive() { return voiceActive.size; }, get voice() { return { on: voiceOn, vol: voiceVol, cur: voiceCur && { src: voiceCur.src, paused: voiceCur.paused, t: voiceCur.currentTime }, set: voiceSet && voiceSet.size }; }, openZoom, closeZoom, dupCheck, get errors() { return window.TCG_ERRORS || []; }, cutIn, passiveCutIn, sortedHand, get handSort() { return handSort; }, put: debugPut, castSkill, skillState, get S() { return S; }, RULES, elementMultiplier, calcDamage, canSummon, buildDeck, summon, attack, recall, attackAll, endTurn, canRecall, recallCost, makeUnit, resolveAttack, useAction, canAction, startGame, startStory, cardHTML, get ready() { return POOL.length > 0; }, equipItem, doSacrifice, finish, attackTargets, get POOL() { return POOL; }, render, Stats };
