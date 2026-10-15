import { RULES, ELEMENTS, elementMultiplier, calcDamage, canSummon, buildDeck, parseCSV, aiSummonOrder, aiPickTarget, recallCost, canRecall, aiShouldRecall, makeUnit, resolveAttack, refillMana, ACTIONS, canAction, doAction, clearBuff, aiWantShuffle, aiWantBuff, aiWantHeal, aiWantFieldHeal, aiPickItem, endTurnXp, ITEMS, canEquip, equip, attackTargets, canTarget, autoTarget, heroLocked, xpToNext, SKILLS, gainXp, setCardPool, canSacrifice, sacrifice, aiPickSacrifice, aiWantAccel, judgeTimeout, JUDGE_LABEL } from './rules.js';
import { setSkillData, setEmitter, initPlayers, placeUnit, turnStart, turnEnd, useSkill, skillState, aiPickSkill, refreshAll, statusIcons, skillsOf, combos, STATUS, SK, maleLure } from './skills.js';

const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const NF = new Intl.NumberFormat('ko-KR');
const fmt = n => NF.format(n);
const $ = id => document.getElementById(id);
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ===== 전적 저장 (나중에 서버 저장으로 교체 가능하도록 분리) =====
const Stats = {
  KEY: 'vrTcgStats.v1',
  load() { try { return { wins: 0, losses: 0, draws: 0, ...JSON.parse(localStorage.getItem(this.KEY)) }; } catch { return { wins: 0, losses: 0, draws: 0 }; } },
  record(win) { const s = this.load(); win === null ? s.draws++ : win ? s.wins++ : s.losses++; localStorage.setItem(this.KEY, JSON.stringify(s)); return s; },
};

let POOL = [];
let S = null;          // 게임 상태
let selected = null;   // 선택된 공격 유닛 uid
let uidSeq = 1;
// 연출 스킵: 토글(localStorage 저장) 또는 연출 중 클릭으로 현재 연출 빨리 감기
const SKIP_KEY = 'vrTcgSkipFx';
let skipFx = localStorage.getItem(SKIP_KEY) === '1';
let fastForward = false;
const FX_OFF = () => !!(window.TCG_FAST || skipFx || fastForward);
const AI_DELAY = () => (window.TCG_FAST ? 0 : (skipFx || fastForward) ? 120 : 650);

function newPlayer(name, second) {
  const deck = buildDeck(POOL);
  const n = RULES.OPENING_HAND + (second ? RULES.SECOND_PLAYER_BONUS_CARDS : 0);
  return { name, hp: RULES.HERO_HP, deck, hand: deck.splice(0, n), field: [], mana: 0, maxMana: 0, second };
}

function log(msg, cls = '') {
  const el = document.createElement('div');
  el.className = 'py-0.5 ' + cls; el.textContent = msg;
  $('log').prepend(el);
}

function startGame() {
  const first = Math.random() < 0.5 ? 'me' : 'ai';   // 선공 동전 던지기
  S = { me: newPlayer('나', first !== 'me'), ai: newPlayer('컴퓨터', first !== 'ai'), first, turn: first, turnNo: 0, totalTurns: 0, myTurns: 0, over: false, busy: false, fxSeen: new Set() };
  preloadFx([...S.me.deck, ...S.me.hand, ...S.ai.deck, ...S.ai.hand]);
  selected = null; $('log').innerHTML = '';
  $('end-screen').classList.add('hidden'); $('start-screen').classList.add('hidden'); $('game').classList.remove('hidden');
  initPlayers(S.me, S.ai);
  log(first === 'me' ? '🪙 동전 던지기: 내가 선공!' : `🪙 동전 던지기: 컴퓨터가 선공! (나는 후공, 시작 손패 +${RULES.SECOND_PLAYER_BONUS_CARDS})`, 'text-emerald-400');
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
  if (p.deck.length) p.hand.push(p.deck.shift()); else log(`${p.name}: 덱이 비어 드로우를 건너뜁니다.`, 'text-zinc-500');
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
  const detail = type === 'accel' ? `다음 턴부터 매 턴 마나 +${r.n * RULES.ACCEL_BONUS} (${r.n}/${RULES.ACCEL_MAX})` : type === 'shuffle' ? `전체 카드에서 새 카드 ${r.n}장` : type === 'heal' ? `영웅 HP +${fmt(r.healed)}` : type === 'fieldheal' ? `필드 ${r.n}장 HP 총 +${fmt(r.healed)}` : `필드 ${r.n}장 이번 턴 ATK +${Math.round(RULES.BUFF_RATIO * 100)}%`;
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
  const p = S[who], check = canRecall(unit, p);
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
const unitEl = (who, u) => document.querySelector(`#${who}-field [data-uid="${u.uid}"]`);
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
    // 남성 공격 유도(최윤희·이혜경): 영웅을 노려도 유도 카드 쪽으로 돌진하도록 미리 계산
    const lure = maleLure(unit, o);
    const shown = lure && lure !== target ? lure : target;
    const tEl = shown ? (unitEl(oWho, shown) || heroEl(oWho)) : heroEl(oWho);
    const hit = await withTimeout(lunge(aEl, tEl), 1500);

    const cls = who === 'me' ? 'text-emerald-300' : 'text-red-300';
    pendingDying = [];
    for (const e of resolveAttack(p, o, unit, target)) {
      if (e.type === 'hero') { log(`${unit.card.name} → ${o.name} 영웅 ${fmt(e.dmg)} 피해`, cls); shake(tEl); dmgNumber(tEl, `-${fmt(e.dmg)}`); }
      else if (e.type === 'hit') {
        const real = e.target || shown;
        const rEl = (real && (unitEl(oWho, real) || unitEl(who, real))) || tEl;
        const orig = shown || null;
        log(`${unit.card.name} → ${real?.card?.name ?? '?'}${orig && real !== orig ? ` (${orig.card.name} 대신)` : (!orig ? ' (영웅 공격 유도)' : '')} ${fmt(e.d1)} 피해${e.mult !== 1 ? ` (속성 ×${e.mult})` : ''}, 반격 ${fmt(e.d2)}`, cls);
        shake(rEl); dmgNumber(rEl, `-${fmt(e.d1)}`);
        if (e.d2) { shake(aEl); dmgNumber(aEl, `-${fmt(e.d2)}`, '#fca5a5'); }
      }
      else if (e.type === 'overflow') { log(`초과 피해 ${fmt(e.dmg)} → ${o.name} 영웅`, 'text-orange-300'); const h = heroEl(oWho); shake(h); dmgNumber(h, `💥 -${fmt(e.dmg)}`, '#fdba74'); }
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
  const st = Stats.record(win);
  $('end-title').innerHTML = win === null ? '<span class="text-zinc-200">무승부</span>' : win ? '<span class="text-emerald-400">승리!</span>' : '<span class="text-red-400">패배...</span>';
  const why = reason === 'ko' ? '진영 붕괴 (KO)' : `${RULES.MAX_TURNS}턴 종료 판정 · ${JUDGE_LABEL[reason]}`;
  const detail = reason === 'ko' ? '' : `<div class="text-sm text-zinc-400 mt-1">진영 HP 나 ${fmt(S.me.hp)} : ${fmt(S.ai.hp)} 상대 · 필드 카드 ${S.me.field.length} : ${S.ai.field.length}</div>`;
  $('end-text').innerHTML = `<div id="end-reason" class="font-bold text-amber-300">${why}</div>${detail}<div class="mt-2">${S.turnNo}라운드 · 전적 ${st.wins}승 ${st.losses}패${st.draws ? ` ${st.draws}무` : ''}</div>`;
  $('end-screen').classList.remove('hidden');
  render();
  return true;
}

function checkEnd() {
  if (S.over) return true;
  if (S.ai.hp <= 0 || S.me.hp <= 0) return finish(S.ai.hp <= 0, 'ko');
  return false;
}
/** 턴 종료 후: 전체 턴 제한 도달 시 판정 */
function checkTimeout() {
  if (S.over || S.totalTurns < RULES.MAX_TURNS) return S.over;
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

// ===== 스킬 =====
const whoOf = p => (p === S.me ? 'me' : 'ai');
let pendingDying = [];
async function fadeDying() {
  const els = pendingDying.filter(Boolean); pendingDying = [];
  if (els.length && !FX_OFF()) { els.forEach(el => el.classList.add('fx-dying')); await sleep(fxMs(300)); }
}
const TYPE_COLOR = { '공격': 'bg-red-600', '도발': 'bg-orange-500', '회복': 'bg-emerald-600', '버프': 'bg-sky-600', '디버프': 'bg-purple-600' };

/** 스킬 컷인: 스킬 이름 배너 + 연출 이미지(data/fx/<파일>, 16:9, 모바일 세로는 가운데 기준으로 양옆 잘림) */
const fxLoaded = new Set();
function preloadFx(cards) {
  for (const c of cards) for (const s of skillsOf(c.id)) {
    if (!s.fx || fxLoaded.has(s.fx) || /\.(mp4|webm)$/i.test(s.fx)) continue;
    fxLoaded.add(s.fx); const img = new Image(); img.decoding = 'async'; img.src = `data/fx/${s.fx}`;
  }
}
function cutInHTML(u, name, fx, passive) {
  const media = fx ? (/\.(mp4|webm)$/i.test(fx) ? `<video src="data/fx/${fx}" autoplay muted playsinline class="cutin-media"></video>` : `<img src="data/fx/${fx}" class="cutin-media" alt="" onerror="this.remove()">`) : '';
  return `${media}<div class="cutin-text"><div class="text-[11px] md:text-xs text-zinc-200">${u.owner.name} · ${u.card.name}${passive ? ' · 패시브' : ''}</div><div class="text-xl md:text-3xl font-black tracking-tight">${passive ? '✨ ' : '⚡ '}${name}</div></div>`;
}
async function cutIn(u, name, fx, passive = false) {
  if (FX_OFF()) return;
  const el = $('cutin');
  el.innerHTML = cutInHTML(u, name, fx, passive);
  el.className = `cutin ${fx ? 'cutin-img' : ''} fixed left-0 right-0 z-40 pointer-events-none text-center ${whoOf(u.owner) === 'me' ? 'cutin-me' : 'cutin-ai'}`;
  await sleep(fxMs(fx ? 1300 : passive ? 500 : 750));
  el.className = 'hidden';
}
/** 패시브 발동 연출: 카드별·스킬별 게임당 첫 발동만 큰 이미지(비동기, 턴 진행을 막지 않음), 이후는 작은 글자만 */
let passiveTimer = null;
function passiveCutIn(u, name) {
  if (FX_OFF() || !S) return;
  const s = u.sk?.find(x => x.name === name); if (!s?.fx) return;
  S.fxSeen ||= new Set(); const key = `${u.uid}:${name}`;
  if (S.fxSeen.has(key)) return;
  S.fxSeen.add(key);
  const el = $('cutin');
  el.innerHTML = cutInHTML(u, name, s.fx, true);
  el.className = `cutin cutin-img fixed left-0 right-0 z-40 pointer-events-none text-center ${whoOf(u.owner) === 'me' ? 'cutin-me' : 'cutin-ai'}`;
  clearTimeout(passiveTimer); passiveTimer = setTimeout(() => { el.className = 'hidden'; }, fxMs(1100));
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
  switch (e.type) {
    case 'skill': log(`${e.unit.owner.name}: ${nm(e.unit)} ⚡[${e.skill.name}] (MP ${e.skill.mp})`, 'text-fuchsia-300'); break;
    case 'passive': log(`${e.unit.owner.name}: ${nm(e.unit)} ✨[${e.name}]${e.text ? ' — ' + e.text : ''}`, 'text-fuchsia-200'); if (!FX_OFF()) { dmgNumber(uEl(e.unit), `✨${e.name}`, '#f0abfc'); passiveCutIn(e.unit, e.name); } break;
    case 'dmg': { const el = uEl(e.unit); shake(el); dmgNumber(el, typeof e.dmg === 'number' ? `-${fmt(e.dmg)}` : e.dmg); break; }
    case 'hero': { const el = heroEl(whoOf(e.p)); shake(el); dmgNumber(el, `-${fmt(e.dmg)}`, e.kind === 'self' ? '#fca5a5' : undefined); log(`${e.p.name} 본진 ${fmt(e.dmg)} 피해${e.kind === 'self' ? ' (자기 공격)' : ''}`, 'text-orange-300'); break; }
    case 'heal': dmgNumber(uEl(e.unit), `+${fmt(e.amt)}`, '#6ee7b7'); break;
    case 'heroHeal': dmgNumber(heroEl(whoOf(e.p)), `+${fmt(e.amt)}`, '#6ee7b7'); log(`${e.p.name} 본진 HP +${fmt(e.amt)}`, 'text-emerald-300'); break;
    case 'destroy': log(`${nm(e.unit)} 파괴!`, 'text-zinc-400'); pendingDying.push(uEl(e.unit)); break;
    case 'refund': log(`${nm(e.killer)} 처치 보상: 마나 +${e.refund}`, 'text-sky-300'); if (e.refund > 0 && !FX_OFF()) dmgNumber(heroEl(whoOf(e.owner)), `💧 +${e.refund} 마나`, '#7dd3fc'); renderHero(whoOf(e.owner)); break;
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
  const p = S[who];
  $(`${who}-hp`).textContent = `${fmt(p.hp)} / ${fmt(RULES.HERO_HP)}`;
  $(`${who}-hpbar`).style.width = (p.hp / RULES.HERO_HP * 100) + '%';
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
  $('attack-all').disabled = !myTurn || !S.me.field.some(u => u.canAttack);
  const tg = attackTargets(S.me, S.ai);
  $('ai-hero').classList.toggle('ring-4', selected != null && tg.hero);
  $('ai-hero').classList.toggle('ring-red-500', selected != null && tg.hero);
  $('ai-hero').classList.toggle('opacity-70', S.turn === 'me' && !tg.hero);
  $('hero-hint').textContent = S.turn === 'me' && !S.over ? (tg.hero ? '🎯 상대 영웅 공격 가능' : '🛡️ ' + tg.reason) : '';
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
    if (!S[who].field.length) box.innerHTML = '<div class="text-zinc-600 text-xs self-center">빈 필드</div>';
    S[who].field.forEach(u => {
      const w = document.createElement('div');
      const isSel = selected === u.uid;
      const ready = who === 'me' && u.canAttack && myTurn;
      w.className = `unit cursor-pointer transition ${isSel ? '-translate-y-2 drop-shadow-[0_0_10px_#34d399]' : ''} ${ready ? 'ready' : ''} ${selected != null && who === 'ai' && tg.units.includes(u) ? 'target' : ''}`;
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
      box.appendChild(w);
    });
    fixImages(box);
    requestAnimationFrame(() => box.querySelectorAll('.hp-fill').forEach(f => { f.style.width = f.dataset.to + '%'; hpPrev.set(f.closest('[data-uid]').dataset.uid, +f.dataset.to); }));
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
      <img src="${IMG}${c.id}.webp" data-id="${c.id}" class="card-img w-32 md:w-40 aspect-[3/4] object-cover rounded-xl ring-2 ${e.ring}">
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
  $('stats').textContent = `전적: ${s.wins}승 ${s.losses}패${s.draws ? ` ${s.draws}무` : ''}`;
}

// ===== 초기화 =====
document.querySelectorAll('[data-close]').forEach(b => b.onclick = () => hideModal(b.dataset.close));
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
for (const type of Object.keys(ACTIONS)) $(`act-${type}`).onclick = () => { if (S.turn === 'me' && !S.busy && !S.over) useAction('me', type); };
$('ai-hero').onclick = onHeroClick;
$('help-btn').onclick = () => showModal('help');
$('main-help').onclick = () => showModal('help');
$('main-skip').onclick = () => { skipFx = !skipFx; localStorage.setItem(SKIP_KEY, skipFx ? '1' : '0'); renderSkipBtn(); };
$('fx-skip').onclick = e => { e.stopPropagation(); skipFx = !skipFx; localStorage.setItem(SKIP_KEY, skipFx ? '1' : '0'); if (S?.busy) fastForward = true; renderSkipBtn(); };
// 연출 중 화면을 누르면 현재 연출 빨리 감기
$('game').addEventListener('click', () => { if (S?.busy && !S.over) fastForward = true; }, true);
renderSkipBtn();
$('restart-btn').onclick = () => { renderStats(); startGame(); };
$('home-btn').onclick = () => { $('end-screen').classList.add('hidden'); $('game').classList.add('hidden'); $('start-screen').classList.remove('hidden'); renderStats(); };
renderStats();

(async () => {
  try {
    POOL = parseCSV(await (await fetch('data/cards.csv')).text()); setCardPool(POOL);
    const [sk, co] = await Promise.all(['data/skills.json', 'data/combos.json'].map(u => fetch(u).then(r => r.json())));
    setSkillData(sk, co); setEmitter(onEngine);
    $('start-btn').disabled = false; $('start-btn').textContent = '게임 시작';
    $('start-btn').onclick = startGame;
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
window.TCG = { dupCheck, get errors() { return window.TCG_ERRORS || []; }, cutIn, passiveCutIn, sortedHand, get handSort() { return handSort; }, put: debugPut, castSkill, skillState, get S() { return S; }, RULES, elementMultiplier, calcDamage, canSummon, buildDeck, summon, attack, recall, attackAll, endTurn, canRecall, recallCost, makeUnit, resolveAttack, useAction, canAction, startGame, equipItem, doSacrifice, finish, attackTargets, get POOL() { return POOL; }, render, Stats };
