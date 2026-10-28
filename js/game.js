import { levelUpOnce, RULES, calcPower, skillLvPowerMult, skillCountMult, ELEMENTS, elementMultiplier, calcDamage, canSummon, buildDeck, parseCSV, aiSummonOrder, aiPickTarget, recallCost, canRecall, aiShouldRecall, makeUnit, resolveAttack, refillMana, ACTIONS, canAction, doAction, clearBuff, aiWantShuffle, aiWantBuff, aiWantHeal, aiWantFieldHeal, aiPickItem, endTurnXp, ITEMS, canEquip, equip, attackTargets, canTarget, autoTarget, heroLocked, xpToNext, SKILLS, gainXp, setCardPool, canSacrifice, sacrifice, aiPickSacrifice, aiWantAccel, judgeTimeout, JUDGE_LABEL, genderMult, GRADES, GRADE_SHORT, allowedGrades, baseEvade, swapField } from './rules.js';
import { autoNext, noteUsed } from './auto-ai.js';
import { setSpare, spareBlocked, setSkillData, setEmitter, initPlayers, placeUnit, turnStart, turnEnd, useSkill, skillState, aiPickSkill, skillLvOf, skillCdAt, skillLvMult, skillLvProb, SKILL_LV_MAX, refreshAll, statusIcons, skillsOf, combos, STATUS, SK, maleLure, checkDeath } from './skills.js';

const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const NF = new Intl.NumberFormat('ko-KR');
const fmt = n => NF.format(n);
const $ = id => document.getElementById(id);
// 2배속: 전투 화면의 대기·연출 타이머와 CSS 애니메이션만 빠르게 (게임 규칙·난수 무관). PvP 재생과 같은 저장 키
const SPD_KEY = 'vrTcgSpd2';
let spd2 = localStorage.getItem(SPD_KEY) === '1';
const spdOn = () => spd2 && !!S && !S.over && !window.VRTutorial?.locked('speed');
const setTimeout = (f, ms = 0, ...a) => window.setTimeout(f, spdOn() ? ms / 2 : ms, ...a);   // 이 모듈 안의 타이머만 영향
let spdTick = 0;
function spdSync() {
  window.clearInterval(spdTick); spdTick = 0;
  const rate = () => { const r = spdOn() ? 2 : 1; for (const a of document.getAnimations()) if (a.playbackRate !== r) a.playbackRate = r; };
  rate(); if (spd2) spdTick = window.setInterval(rate, 80);
}
function renderSpdBtn() { const b = $('spd-btn'); if (!b) return; b.classList.toggle('on', spd2); b.setAttribute('aria-pressed', String(spd2)); b.textContent = 'X2'; }
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ===== 전적 저장 (나중에 서버 저장으로 교체 가능하도록 분리) =====
// 아케이드 전적: 게스트는 브라우저 기록, 로그인하면 계정별 키(서버 matches 집계로 채움)라 계정끼리 섞이지 않음
const Stats = {
  get KEY() { const u = window.VRCloud?.user?.id; return u ? `vrTcgStats.v1:${u}` : 'vrTcgStats.v1'; },
  load() { try { return { wins: 0, losses: 0, draws: 0, ...JSON.parse(localStorage.getItem(this.KEY)) }; } catch { return { wins: 0, losses: 0, draws: 0 }; } },
  record(win) { const s = this.load(); win === null ? s.draws++ : win ? s.wins++ : s.losses++; localStorage.setItem(this.KEY, JSON.stringify(s)); return s; },
};

// 카드 그림 대체: bt_img(외부 저장소)에 없는 카드(NPC 등)는 img/cards/<id>.webp
document.addEventListener('error', e => { const t = e.target; if (t?.tagName !== 'IMG' || t.dataset.fb) return; const m = /\/bt_img\/(\d+)\.webp$/.exec(t.src || ''); if (m) { t.dataset.fb = '1'; t.src = `img/cards/${m[1]}.webp`; } }, true);
let POOL = [], NPC = [];   // NPC: 스토리 적 전용 카드
const isNpc = c => !!c && /^(1|true|npc|y)$/i.test(String(c.npc || '').trim());

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
// ===== 아케이드 게임 설정 (등급 룰 · 라운드 리미트 · 카드 먼저 제거) =====
// 기본값은 기존과 동일: 전 등급, 40턴, 카드 먼저 제거 OFF
const ArcadeOpts = {
  KEY: 'vrTcgArcadeOpts.v1',
  DEF: { grades: null, turns: 40, clearFirst: false },
  TURNS: [10, 40, 0],   // 0 = 무제한
  PRESETS: [
    { k: 'all', label: '전체 등급', grades: null },
    { k: 'n', label: 'N만', grades: ['NORMAL'] },
    { k: 'lehr', label: 'HR 이하', grades: ['NORMAL', 'RARE', 'HIGH RARE'] },
    { k: 'gesr', label: 'SR 이상', grades: ['SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE'] },
    { k: 'nomr', label: 'MR 제외', grades: ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE'] },
  ],
  load() { try { const o = { ...this.DEF, ...JSON.parse(localStorage.getItem(this.KEY) || '{}') }; if (!this.TURNS.includes(o.turns)) o.turns = 40; if (o.grades && !o.grades.length) o.grades = null; return o; } catch { return { ...this.DEF }; } },
  save(o) { localStorage.setItem(this.KEY, JSON.stringify(o)); renderArcadeOptsBtn(); },
  isDefault(o) { return !o.grades && o.turns === 40 && !o.clearFirst; },
  gradeLabel(o) { if (!o.grades) return '전체 등급'; const p = this.PRESETS.find(x => x.grades && x.grades.length === o.grades.length && x.grades.every(g => o.grades.includes(g))); return p ? p.label : o.grades.map(g => GRADE_SHORT[g]).join('·'); },
  summary(o) { return `${this.gradeLabel(o)} · ${o.turns ? o.turns + '턴' : '턴 무제한'}${o.clearFirst ? ' · 카드 먼저 제거' : ''}`; },
};
/** 현재 판의 턴 제한 (스토리는 기존 규칙, 아케이드는 설정. Infinity = 무제한) */
const maxTurns = () => S?.maxTurns ?? RULES.MAX_TURNS;
let S = null;          // 게임 상태
let selected = null;   // 선택된 공격 유닛 uid
const TUT = (ev, d) => { try { window.VRTutorial?.emit(ev, d); } catch {} };   // 튜토리얼 가이드 (js/tutorial.js)
const TUT_LOCK = k => !!window.VRTutorial?.locked(k);
let uidSeq = 1;
// 연출 스킵: 토글(localStorage 저장) 또는 연출 중 클릭으로 현재 연출 빨리 감기
const SKIP_KEY = 'vrTcgSkipFx';
let skipFx = localStorage.getItem(SKIP_KEY) === '1';
let fastForward = false;
const SWEEPING = () => !!window.VR_SWEEPING;   // 탑 소탕 중: 스킬 컷인·보이스·영상 없음
const FX_OFF = () => !!(window.TCG_FAST || skipFx || fastForward || SWEEPING());
// 스킬 컷인 이미지는 '공격 연출 스킵'·탭 빨리감기 중에도 짧게(600ms) 보여 줌. 테스트·탑 소탕에서만 완전히 끔
const CUT_OFF = () => !!(window.TCG_FAST || SWEEPING());
const CUT_QUICK = 600;
// 자동 전투: 스토리·탑(S.story)에서만. 사용자별 localStorage. 전투 중 언제든 끄면 다음 행동부터 수동
const AUTO_KEY = () => `vrTcgAuto:${window.VRCloud?.user?.id || 'guest'}`;
let autoOn = localStorage.getItem(AUTO_KEY()) === '1', autoRunning = false;
// 자동 전투 해금: 계정 레벨(플레이어 레벨, player_status.level) 5 이상
const AUTO_LV = 5;
const autoLocked = () => (window.VRPlayer?.now?.()?.level ?? 0) < AUTO_LV;
const autoActive = () => autoOn && !autoLocked() && !!S?.story && !S.over && !S.view && !TUT_LOCK('auto');
function renderAutoBtn() {
  const b = $('auto-btn'); if (!b) return;
  b.classList.toggle('hidden', !S?.story); b.classList.toggle('on', autoOn);
  if (S?.view) { const on = S.view.auto; b.classList.toggle('on', on); b.classList.remove('locked'); b.title = '자동 전투'; b.setAttribute('aria-pressed', String(on)); b.textContent = on ? '⏸ AUTO' : '▶ AUTO'; return; }
  const lk = autoLocked(); b.classList.toggle('locked', lk); b.title = lk ? `자동 전투 · 계정 Lv${AUTO_LV}부터` : '자동 전투';
  b.setAttribute('aria-pressed', String(autoOn && !lk)); b.textContent = lk ? '🔒 AUTO' : autoOn ? '⏸ AUTO' : '▶ AUTO';
  if (lk && S?.story && !b.dataset.lvReq) { b.dataset.lvReq = '1'; window.VRPlayer?.status?.().then(() => { delete b.dataset.lvReq; if (!autoLocked()) { renderAutoBtn(); if (autoActive() && S.turn === 'me' && !S.busy) autoTurn(); } }); }
}
/** 조건 안내·스토리 대사 등 화면 위 창이 떠 있으면 자동 진행 대기 */
const autoBlocked = () => [...document.querySelectorAll('#story-cond, #story-dlg, .story-pop')].some(e => e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden');
async function autoTurn() {
  if (autoRunning) return; autoRunning = true;
  const turn = { used: new Set(), scopes: new Set() };
  try {
    for (let guard = 0; guard < 40; guard++) {
      await vidWait();
      while ((S.busy || autoBlocked()) && !S.over) await sleep(80);
      if (!autoActive() || S.turn !== 'me') return;
      const a = autoNext(S.me, S.ai, turn);
      if (!a) break;
      if (a.kind === 'skill') { noteUsed(turn, a.s); await castSkill('me', a.u, a.s); }
      else { const before = a.u.canAttack; await attack('me', a.u, a.t); if (before && a.u.canAttack) a.u.canAttack = false; }
      await sleep(AI_DELAY());
    }
    while (S.busy && !S.over) await sleep(50);
    if (autoActive() && S.turn === 'me') endTurn();
  } catch (err) { reportError('autoTurn', err); }
  finally { autoRunning = false; }
}
const AI_DELAY = () => (window.TCG_FAST ? 0 : (skipFx || fastForward) ? 60 : 325);

function newPlayer(name, second, deckOverride = null, hp = RULES.HERO_HP, fieldStart = false, grades = null) {
  const deck = deckOverride ? (fieldStart ? [...deckOverride] : shuffleArr(deckOverride)) : buildDeck(POOL, Math.random, grades);
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
  autoOn = localStorage.getItem(AUTO_KEY()) === '1';
  if (story && typeof story.then === 'function' || story instanceof Event) story = null;
  setSpare(story?.spare);   // 스토리 보호 규칙 (없으면 해제)
  const first = story?.first || (Math.random() < 0.5 ? 'me' : 'ai');   // 선공 동전 던지기
  if (!story) { try { window.VRSound?.setTrack?.('audio/arcade_battle.mp3'); } catch {} }   // 아케이드 전용 BGM (나가면 메인으로)
  const fs = !!story;   // 스토리: 손패 없이 출전 카드 전부 필드에서 시작
  const ao = story ? ArcadeOpts.DEF : ArcadeOpts.load(), grades = story ? null : allowedGrades(ao);
  const gPool = grades ? POOL.filter(c => grades.has(c.grade)) : null;
  S = { me: newPlayer('나', first !== 'me', story?.me, story?.meHp, fs, grades), ai: newPlayer(story?.aiName || '적군', first !== 'ai', story?.ai, story?.aiHp, fs, grades), opts: ao, maxTurns: story ? RULES.MAX_TURNS : (ao.turns || Infinity), first, story, turn: first, turnNo: 0, totalTurns: 0, myTurns: 0, over: false, busy: false, fxSeen: new Set(), mercBought: 0, mercHired: null, mercOffer: [], log: { dmg: new Map(), total: 0, skills: 0, merc: null, played: new Set(), kills: {} } };
  // 아케이드 일반대전(기본 설정)만 기지 보강·필드 회복·용병 고용 가능. 스토리·퀘스트·아케이드 변형 설정은 공격력 강화만
  S.limitedAids = !!story || !ArcadeOpts.isDefault(ao);
  S.mercOffer = S.limitedAids ? [] : Merc.roll(gPool || POOL, S.me);
  if (gPool) S.me.pool = S.ai.pool = gPool;   // 패 섞기도 허용 등급에서만
  S.me.clearFirst = S.ai.clearFirst = !story && !!ao.clearFirst;   // 카드 먼저 제거: 양측 공통 규칙
  // 스토리: 내 진영 없음(일반·보스 공통). 상대 진영은 보스전에만 존재
  S.me.noBase = !!story; S.ai.noBase = story?.win === 'wipe';
  S.me.noActs = S.ai.noActs = !!story;   // 스토리: 마나 가속기·필드 회복 없음 (공격력 강화는 가능)
  S.me.limitedAids = S.ai.limitedAids = S.limitedAids;
  for (const t of ['accel', 'buff', 'fieldheal', 'heal']) $(`act-${t}`)?.classList.toggle('hidden', t === 'buff' ? false : t === 'accel' ? !!story : S.limitedAids);
  $('act-merc')?.classList.toggle('hidden', S.limitedAids);
  $('story-giveup')?.classList.toggle('hidden', !story);
  for (const w of ['me', 'ai']) { $(`${w}-hp`).classList.toggle('hidden', S[w].noBase); $(`${w}-hpbar`).parentElement.classList.toggle('hidden', S[w].noBase); }
  $('game').classList.toggle('story-field', !!story);
  setBattleBg(story?.win === 'ko' ? 'boss' : 'normal'); preloadHit();
  { const lbl = $('ai-order').parentElement.firstChild; if (lbl?.nodeType === 3) lbl.textContent = story ? `${story.aiName || '적군'} ` : '🤖 컴퓨터 '; }
  preloadFx([...S.me.deck, ...S.me.hand, ...S.ai.deck, ...S.ai.hand]);
  selected = null; $('log').innerHTML = ''; fxQueue.length = 0; vidGate = Promise.resolve();
  $('end-screen').classList.add('hidden'); $('start-screen').classList.add('hidden'); $('game').classList.remove('hidden');
  initPlayers(S.me, S.ai, S[first]);   // 0턴 배치 상태(불사·회피 등) 지속 턴 기준 = 선공
  if (fs) {   // 스토리: 양측 카드 전부 필드에 배치 (최대 FIELD_MAX)
    S.holdPassive = [];   // 0턴 패시브 컷인은 UR 등장 컷인 뒤로 미룸 (아래 onEnter 뒤에 재생)
    for (const who of ['me', 'ai']) {
      const p = S[who];
      for (const c of p.deck.splice(0, RULES.FIELD_MAX)) {
        const u = placeUnit(p, c, makeUnit);
        if (who === 'me') S.log.played.add(String(c.id));
        if (who === 'me' && story.leader && c.uid && c.uid === story.leader.uid && !p.field.some(x => x.isLeader)) { u.isLeader = true; p.leaderSkill = story.leader; }
        if (who === 'ai' && story.bossId != null && String(c.id) === String(story.bossId) && !p.field.some(x => x.undying)) { u.undying = true; u.boss = true; }
        if (who === 'me') { const lv = +(story.meLevels?.[String(c.id)] || 0); while (u.level < Math.min(lv, RULES.LEVEL_MAX)) levelUpOnce(u); if (story.fullMp) u.mp = u.maxMp; }   // 챕터 0: 내 카드 시작 레벨(party.battleLevels) · 시작 MP 가득
        if (who === 'ai') { const lv = +(story.enemyLevels?.[String(c.id)] || 0); while (u.level < Math.min(lv, RULES.LEVEL_MAX)) levelUpOnce(u); }   // 페이즈 적 시작 레벨 (enemies.levels)
        if (who === 'ai' && (story.rules?.undying || []).map(String).includes(String(c.id))) u.undying = true;   // 불사 적 (피해는 받지만 쓰러지지 않음)
        if (who === 'ai' && story.rules?.invuln != null && String(c.id) === String(story.rules.invuln) && !p.field.some(x => x.noDamage)) { u.undying = true; u.noDamage = true; u.boss = true; }
      }
      p.deck = [];
    }
    S.reserve = (story.reserve || []).map(c => ({ card: c, cost: 0 }));   // 소환 대기 (챕터 0). cost: 나중에 '마나 100 고정 · 코스트 소환' 설계에서 쓸 자리 (지금은 0 = 무료)
    { const PS = story.rules?.pairShield;   // 챕터 3 밸런스: 조윤하·조윤이가 둘 다 내 필드에 있으면 조윤하 처음 N턴 피해 무효
      const tgt = PS && S.me.field.find(u => String(u.card.id) === String(PS.id));
      if (tgt && S.me.field.some(u => String(u.card.id) === String(PS.with))) { tgt.noDamage = true; tgt.pairShield = PS.turns; S.pairShield = { u: tgt, turns: PS.turns }; log(`🛡️ 자매의 가호: ${tgt.card.name}은(는) ${PS.turns}턴 동안 피해를 입지 않아요.`, 'text-sky-300'); } }
    refreshAll(S.me); refreshAll(S.ai);
    setTimeout(() => { if (S && !S.over) { for (const w of ['me', 'ai']) for (const u of S[w].field) onEnter(w, u); flushHeldPassives(); } }, 400);
    if (story.tutorial) window.setTimeout(() => window.VRTutorial?.start(story.tutorial, { force: !!story.tutorialForce }), 900);   // 페이즈의 tutorial id → 가이드 (data/tutorials/<id>.json)   // 출전 카드 등장 컷인·이벤트
    if (S.me.leaderSkill) log(`👑 리더 스킬 [${S.me.leaderSkill.name} · ${S.me.leaderSkill.label}]: ${S.me.leaderSkill.text}. 리더가 쓰러지면 해제되고 아군 진영 HP −${Math.round((S.me.leaderSkill.deathPenalty ?? 0.3) * 100)}%`, 'text-amber-300');
    log(story.win === 'ko' ? '👑 보스전: 보스는 진영 안에서 쓰러지지 않아요. 상대 진영 HP를 0으로!' : '⚔️ 일반전: 상대 카드를 모두 쓰러뜨리세요!', 'text-amber-300');
  }
  if (fs) log('⚔️ 출전 카드가 모두 필드에서 시작합니다 (손패·드로우 없음).', 'text-emerald-400');
  if (!story && !ArcadeOpts.isDefault(ao)) log(`🎛️ 게임 설정: ${ArcadeOpts.summary(ao)}`, 'text-amber-300');
  if (!fs) log(first === 'me' ? '🪙 동전 던지기: 내가 선공!' : `🪙 동전 던지기: 컴퓨터가 선공! (나는 후공, 시작 손패 +${RULES.SECOND_PLAYER_BONUS_CARDS})`, 'text-emerald-400');
  $('me-order').textContent = first === 'me' ? '선공' : '후공';
  $('ai-order').textContent = first === 'ai' ? '선공' : '후공';
  startTurn(first);
}

function startTurn(who) {
  const p = S[who];
  S.turn = who; if (who === S.first) S.turnNo++; S.totalTurns++;
  if (S.pairShield && S.turnNo > S.pairShield.turns) { const u = S.pairShield.u; S.pairShield = null; u.noDamage = false; delete u.pairShield; log(`🛡️ 자매의 가호가 사라졌다: ${u.card.name}`, 'text-zinc-400'); }
  if (S.story?.rules && storyTurnRules(who)) return true;
  if (who === 'me') { S.myTurns++; setTimeout(() => TUT('turn_start', { turn: S.turnNo }), 50); if (myTurnsLeft() === 1) lastTurnToast(); }
  clearBuff(opp(who));                   // 지난 턴 강화 해제
  const bonus = refillMana(p);
  if (bonus) { log(`${p.name}: 처치 보너스 마나 +${bonus}`, 'text-sky-300'); if (who === 'me') floatText(`${ic('mana')} +${bonus}`, 'text-sky-300', 'me', true); }
  if (S.story) { /* 스토리: 드로우 없음 */ } else if (p.deck.length) p.hand.push(p.deck.shift()); else log(`${p.name}: 덱이 비어 드로우를 건너뜁니다.`, 'text-zinc-500');
  p.field.forEach(u => u.canAttack = true);
  turnStart(p);                           // 쿨타임·MP 회복, 턴 시작 패시브, 마비/혼란/교란 처리
  render();
  if (checkEnd()) return;
  if (who === 'ai') aiTurn();
  else if (autoActive()) setTimeout(autoTurn, AI_DELAY());
}

function useAction(who, type) {
  const p = S[who], r = doAction(type, p);
  if (!r.ok) return r;
  const a = ACTIONS[type];
  const detail = type === 'accel' ? `다음 턴부터 매 턴 마나 +${r.n * RULES.ACCEL_BONUS} (${r.n}/${RULES.ACCEL_MAX})` : type === 'shuffle' ? `전체 카드에서 새 카드 ${r.n}장` : type === 'heal' ? `진영 HP +${fmt(r.healed)}` : type === 'fieldheal' ? `필드 ${r.n}장 HP 총 +${fmt(r.healed)}` : `필드 ${r.n}장 이번 턴 ATK +${Math.round(RULES.BUFF_RATIO * 100)}%`;
  log(`${p.name}: ${a.icon} ${a.label} (마나 ${a.cost()}) — ${detail}`, 'text-violet-300');
  if (type === 'heal') floatText(`+${fmt(r.healed)}`, 'text-emerald-300', who === 'me' ? 'me' : 'ai');
  if (type === 'fieldheal') floatText(`${ic('heal')} +${fmt(r.healed)}`, 'text-emerald-300', who, true);
  if (type === 'buff') floatText(`${ic('atk')} ATK +${Math.round(RULES.BUFF_RATIO * 100)}%`, 'text-violet-300', who, true);
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
  const u = placeUnit(p, card, makeUnit, true);   // 새로 소환한 카드는 필드 맨 앞
  playSe(card.grade === 'MYTHIC RARE' || card.grade === 'LEGENDARY RARE' ? 6 : card.grade === 'ULTRA RARE' ? 5 : 2);
  render();
  onEnter(who, u);
  return { ok: true };
}

function doSacrifice(who, unit) {
  const p = S[who], r = sacrifice(unit, p);
  if (!r.ok) return r;
  if (selected === unit.uid) selected = null;
  log(`${p.name}: ${unit.card.name} 희생 — 마나 +${r.gain}`, 'text-rose-300');
  floatText(`${ic('bleed')} 마나 +${r.gain}`, 'text-sky-300', who, true);
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
  if (S?.view) {   // 화면 전투(토벌·PvP·구역 전쟁): 공격 가능한 내 카드가 차례로 공격 → 행동마다 기록(raid_log 재생 검증)
    if (!S.view.ask || S.turn !== 'me') return;
    S.view.batch = S.me.field.filter(u => u.canAttack && u.hp > 0).map(u => u);
    log(`일괄 공격! (${S.view.batch.length}장)`, 'text-emerald-400');
    S.view.nextBatch?.(); return;
  }
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

function setStartLabel(t) { const b = $('start-btn'), l = b?.querySelector('.main-banner-title'); if (l) l.textContent = t; else if (b) b.textContent = t; }
function renderSkipBtn() {
  const m = $('main-skip'); if (m) { m.textContent = skipFx ? 'ON' : 'OFF'; m.setAttribute('aria-checked', String(skipFx)); m.classList.toggle('on', skipFx); }
  const b = $('fx-skip');
  b.innerHTML = skipFx ? '⏩ 스킵 ON' : `${ic('opening', { alt: '' })} 연출`;
  b.classList.toggle('border-amber-400', skipFx); b.classList.toggle('text-amber-300', skipFx);
}

// ===== 공격 연출 =====
const REDUCED = () => !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
const FX_SPEED = 0.5; // 공격·피격·사망 연출 2배속 (컷인은 cutinMs로 원래 속도 유지)
const fxMs = ms => (FX_OFF() ? 0 : REDUCED() ? Math.round(ms * 0.3 * FX_SPEED) : Math.round(ms * FX_SPEED));
const cutinMs = ms => (FX_OFF() ? 0 : REDUCED() ? Math.round(ms * 0.3) : ms);
const unitEl = (who, u) => document.querySelector(`#${who}-field [data-uid="${u.uid}"], #${who}-boss [data-uid="${u.uid}"]`);
const heroEl = who => $(`${who}-hero`);

// ===== 아이콘 (js/icons.js) =====
const ic = (n, o) => window.VRIcon?.icon(n, o) || '';
const icOf = d => (d?.img && ic(d.img)) || d?.icon || '';   // 데이터(ELEMENTS·STATUS·ACTIONS·ITEMS)의 img 가 있으면 그림, 없으면 이모지
const escHtml = t => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** 타격 스프라이트: kind 'impact'(일반 타격) | 'blood'(속성 유리·스킬 피해). 대상 카드 위에 확대+페이드. 스킬 컷인(data/fx)과 별개 */
const HIT_IMG = { impact: 'img/ui/hit_impact.webp', blood: 'img/ui/hit_blood.webp' };
function hitFx(el, kind = 'impact') {
  if (!el || FX_OFF() || REDUCED() || !el.isConnected) return;
  const r = el.getBoundingClientRect(); if (!r.width) return;
  const img = document.createElement('img');
  img.src = HIT_IMG[kind] || HIT_IMG.impact; img.alt = ''; img.className = `fx-hit ${kind}`; img.setAttribute('aria-hidden', 'true');
  const size = Math.round(Math.min(Math.max(r.width, r.height) * (kind === 'blood' ? 1.25 : 1.1), 340));
  img.style.width = img.style.height = size + 'px';
  img.style.left = (r.left + r.width / 2) + 'px'; img.style.top = (r.top + r.height / 2) + 'px';
  img.style.setProperty('--rot', `${Math.round(Math.random() * 60 - 30)}deg`);
  document.body.appendChild(img);
  setTimeout(() => img.remove(), 225);
}
let hitPreloaded = false;
function preloadHit() { if (hitPreloaded) return; hitPreloaded = true; for (const src of Object.values(HIT_IMG)) { const i = new Image(); i.src = src; } }

/** 전투 배경: 전투가 시작될 때만 이미지를 받음 (CSS data-bg). 아케이드·스토리 일반 = normal, 스토리 보스 = boss */
function setBattleBg(kind) {
  const bg = $('battle-bg'); if (!bg) return;
  bg.dataset.bg = kind; bg.classList.add('on');
  if (!bg._watch) { bg._watch = new MutationObserver(() => bg.classList.toggle('on', !$('game').classList.contains('hidden'))); bg._watch.observe($('game'), { attributes: true, attributeFilter: ['class'] }); }
}

function shake(el) {
  if (!el || FX_OFF()) return;
  el.classList.remove('fx-shake', 'fx-hitflash'); void el.offsetWidth;
  el.classList.add('fx-shake', 'fx-hitflash');
  setTimeout(() => el.classList.remove('fx-shake', 'fx-hitflash'), 165);
}

/** 치명타 연출: 노란 섬광 + 방사선 링 (속성 유리 피 튀김과 별개, 짧게) */
const critSet = new Set();
function critFx(el) {
  if (!el || FX_OFF() || !el.isConnected) return;
  const r = el.getBoundingClientRect(); if (!r.width) return;
  const d = document.createElement('div'); d.className = 'fx-crit'; d.setAttribute('aria-hidden', 'true');
  const size = Math.round(Math.min(Math.max(r.width, r.height) * 1.5, 380));
  d.style.width = d.style.height = size + 'px'; d.style.left = (r.left + r.width / 2) + 'px'; d.style.top = (r.top + r.height / 2) + 'px';
  d.innerHTML = '<i></i><b>CRIT</b>';
  document.body.appendChild(d); setTimeout(() => d.remove(), REDUCED() ? 250 : 520);
}
const critNum = (el, n, unit) => { const c = critSet.delete(unit); dmgNumber(el, `-${fmt(n)}`, c ? '#fde047' : undefined, false, c ? 'fx-dmg-crit' : ''); };
const EL_FX = { guard: ['🛡️', '#7dd3fc', '얼음 방어: 피해 절반'], drain: ['🩸', '#f0abfc', '어둠 흡혈'], cleanse: ['✨', '#fef08a', '빛 정화: 디버프 해제'], darkCounter: ['🌑×2', '#c4b5fd', '어둠 반격 2배'], nullCounter: ['🚫', '#fef9c3', '빛: 반격 무효'] };
function dmgNumber(el, text, color, html = false, extra = '') {
  if (!el || FX_OFF()) return;
  const r = el.getBoundingClientRect();
  const d = document.createElement('div');
  d.className = 'fx-dmg' + (extra ? ' ' + extra : ''); if (html) d.innerHTML = text; else d.textContent = text;
  if (color) d.style.color = color;
  d.style.left = (r.left + r.width / 2 + (Math.random() - 0.5) * 16) + 'px';
  d.style.top = (r.top + r.height * 0.4) + 'px';
  document.body.appendChild(d);
  d.addEventListener('animationend', () => d.remove(), { once: true }); setTimeout(() => d.remove(), 1800);   // 천천히 사라짐 (CSS fxDmg 1.3s · 크리 1.5s)
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
  if (S?.view) { if (who === 'me' && S.view.ask && target) S.view.ask({ k: 'atk', i: S.view.A0.indexOf(unit), t: S.view.B0.indexOf(target) }); return; }
  const o = opp(who), p = S[who];
  if (!unit.canAttack || S.over) return;
  if (!fromBatch && who === 'me' && S.busy) return;
  if (!canTarget(p, o, target, unit)) { if (who === 'me') { const r = attackTargets(p, o, unit).reason; log(r, 'text-red-400'); floatText(r, 'text-red-400 text-sm', 'ai'); } return; }
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
    playSe(7);
    const hit = await withTimeout(lunge(aEl, tEl), 750);

    const cls = who === 'me' ? 'text-emerald-300' : 'text-red-300';
    pendingDying = [];
    for (const e of resolveAttack(p, o, unit, target)) {
      playSe(e.type === 'hit' ? 1 : (e.type === 'hero' || e.type === 'overflow') ? 3 : 0);
      if (e.type === 'hero') { log(`${unit.card.name} → ${o.name} 진영 ${fmt(e.dmg)} 피해`, cls); shake(tEl); hitFx(tEl); dmgNumber(tEl, `-${fmt(e.dmg)}`); }
      else if (e.type === 'hit') {
        const real = e.target || shown;
        const rEl = (real && (unitEl(oWho, real) || unitEl(who, real))) || tEl;
        const orig = shown || null;
        log(`${unit.card.name} → ${real?.card?.name ?? '?'}${orig && real !== orig ? ` (${orig.card.name} 대신)` : (!orig ? ' (진영 공격 유도)' : '')} ${fmt(e.d1)} 피해${e.mult !== 1 ? ` (속성 ×${e.mult})` : ''}${real?.card && genderMult(unit.card, real.card) !== 1 ? ` (성별 ×${genderMult(unit.card, real.card)})` : ''}${e.killed ? ', 처치 (반격 없음)' : `, 반격 ${fmt(e.d2)}${e.survived ? ' (HP 1로 버팀)' : ''}`}`, cls);
        shake(rEl); hitFx(rEl, e.mult > 1 ? 'blood' : 'impact'); critNum(rEl, e.d1, real);   // 속성 유리 = 피 튀김, 치명타 = 노란 숫자
        if (e.d2) { shake(aEl); hitFx(aEl); if (critSet.delete(unit)) dmgNumber(aEl, `-${fmt(e.d2)}`, '#fde047', false, 'fx-dmg-crit'); else dmgNumber(aEl, `-${fmt(e.d2)}`, '#fca5a5'); }
      }
      else if (e.type === 'evade') { const rEl = unitEl(oWho, e.target) || tEl; log(`${unit.card.name} → ${e.target.card.name} 공격 회피! (피해·반격 없음)`, cls); dmgNumber(rEl, 'MISS', '#e0f2fe'); }
      else if (e.type === 'overflow') { log(`초과 피해 ${fmt(e.dmg)} → ${o.name} 진영`, 'text-orange-300'); const h = heroEl(oWho); shake(h); hitFx(h); dmgNumber(h, `💥 -${fmt(e.dmg)}`, '#fdba74'); }
    }
    critSet.clear();
    renderHero(oWho); renderHero(who);
    await withTimeout(hit?.back?.() ?? Promise.resolve(), 750);
    await vidWait();
    await withTimeout(fadeDying(), 750);
  } catch (err) {
    reportError('attack', err);
  } finally {
    resetAnim(aEl);
    unit.canAttack = false;
    S.busy = prevBusy;
    if (!prevBusy) fastForward = false;
    render();
    checkEnd();
    if (who === 'me') TUT('attack_done');
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
function floatText(text, cls, side = 'me', html = false) {
  const anchor = $(side === 'me' ? 'me-field' : 'ai-field');
  if (!anchor) return;
  const r = anchor.getBoundingClientRect();
  const el = document.createElement('div');
  el.className = `float-text fixed z-30 pointer-events-none font-black text-lg drop-shadow ${cls}`;
  if (html) el.innerHTML = text; else el.textContent = text;
  el.style.left = (r.left + r.width / 2 + (Math.random() - 0.5) * 80) + 'px';
  el.style.top = (r.top + r.height / 2) + 'px';
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 1200);
}

function finish(win, reason) {
  S.over = true; hideModal('detail'); TUT('battle_end', { win: !!win });
  try { window.VRSound?.jingle?.(win === null ? 'draw' : win ? 'victory' : 'defeat'); } catch {}   // 전투 종료 징글 (전 모드, 1회)
  if (S.story) {   // 스토리 모드: 아케이드 전적·랭킹·갤러리에 기록하지 않고 스토리 화면으로 결과 전달
    render();
    const cb = S.story.onEnd;
    setTimeout(() => { $('game').classList.add('hidden'); try { cb?.(win, reason, { turns: S.turnNo, damage: S.log.total, played: [...S.log.played], kills: { ...S.log.kills } }); } catch (err) { reportError('storyEnd', err); } }, FX_OFF() ? 0 : 900);
    return true;
  }
  const st = Stats.record(win);
  $('end-title').innerHTML = win === null ? '<span class="text-zinc-200">무승부</span>' : win ? '<span class="text-emerald-400">승리!</span>' : '<span class="text-red-400">패배...</span>';
  const why = reason === 'ko' ? '진영 붕괴 (KO)' : `${maxTurns()}턴 종료 판정 · ${JUDGE_LABEL[reason]}`;
  const detail = reason === 'ko' ? '' : `<div class="text-sm text-zinc-400 mt-1">진영 HP 나 ${fmt(S.me.hp)} : ${fmt(S.ai.hp)} 상대 · 필드 카드 ${S.me.field.length} : ${S.ai.field.length}</div>`;
  $('end-text').innerHTML = `<div id="end-reason" class="font-bold text-amber-300">${why}</div>${detail}<div class="mt-2">${S.turnNo}라운드 · 아케이드 전적 ${st.wins}승 ${st.losses}패${st.draws ? ` ${st.draws}무` : ''}</div>`;
  try { showEnding(win, reason); } catch (err) { reportError('ending', err); }
  try { const mvp = pickMvp(); window.dispatchEvent(new CustomEvent('vr:match', { detail: { result: win === null ? 'draw' : win ? 'win' : 'lose', reason, turns: S.turnNo, damage: S.log.total, skills: S.log.skills, mvpId: mvp?.card.id, mvpName: mvp?.card.name, mercId: S.log.merc?.id, fieldIds: S.me.field.map(u => (u.base || u.card).id) } })); } catch {}
  $('end-screen').classList.remove('hidden');
  render();
  return true;
}

// ===== 스토리 페이즈 규칙 (story.rules) =====
// mustLive: [카드 id] 내 카드가 쓰러지면 패배 · revive: [{ id, level: 1|'keep', times, delay }] 적 카드가 쓰러지면 적의 delay 번째 턴 시작에 부활 (times 없으면 무제한)
// 승리 판정: 그 순간 적 카드가 모두 쓰러져 있으면 승리 (부활 대기는 막지 않음)
// invuln: 적 카드 id (피해 없음·쓰러지지 않음) · expire: invuln 카드가 이 라운드 수가 지나면 자동 사망 (부활 대기·부활 카드도 함께 소멸)
function storyOnDeath(u) {
  const R = S.story.rules, id = String(u.card.id);
  if (u.owner === S.me && (R.mustLive || []).map(String).includes(id)) { S.mustLiveDown = u.card.name; log(`💔 ${u.card.name} 카드가 쓰러졌다! 이 페이즈는 ${u.card.name} 카드가 살아 있어야 해요`, 'text-red-400'); }
  if (u.owner === S.ai && !S.expired) {
    const r = (R.revive || []).find(x => String(x.id) === id); if (!r) return;
    const used = (S.reviveUsed ||= {}), k = id + ':' + (u.reviveSlot ?? u.uid);
    if (r.times && (used[k] | 0) >= r.times) return;
    used[k] = (used[k] | 0) + 1;
    const delay = Math.max(1, r.delay | 0 || 1);
    (S.ai.reviveQ ||= []).push({ card: u.base, level: r.level === 'keep' ? u.level : 1, slot: u.reviveSlot ?? u.uid, key: k, wait: delay });
    log(`🩸 ${u.card.name}: ${delay}턴 후 부활해요 (그 전에 적을 모두 쓰러뜨리면 승리)`, 'text-fuchsia-300');
  }
}
/** 턴 시작 규칙. true 를 돌려주면 전투가 끝남 */
function storyTurnRules(who) {
  const R = S.story.rules, p = S[who];
  if (R.expire && R.invuln != null && !S.expired && S.turnNo > R.expire) {
    S.expired = true; S.ai.reviveQ = [];
    for (const u of [...S.ai.field]) {
      const isBoss = String(u.card.id) === String(R.invuln);
      u.undying = false; u.noDamage = false; delete u.st.endure; (u.fired ||= {})['나는 쓰러지지 않아:rev'] = 1; u.hp = 0; checkDeath(u);   // 불사·부활 효과 무시하고 강제 소멸
      if (isBoss) log(`🔥 ${R.expire}턴 경과: ${u.card.name}의 각성이 다 타 버렸다!`, 'text-amber-300');
    }
    render(); if (checkEnd()) return true;
  }
  if (p.reviveQ?.length) {
    const q = p.reviveQ.splice(0);
    for (const r of q) {
      if (--r.wait > 0 || p.field.length >= RULES.FIELD_MAX) { p.reviveQ.push(r); continue; }
      const u = placeUnit(p, { ...r.card }, makeUnit); u.reviveSlot = r.slot;
      while (u.level < r.level) { const need = xpToNext(u.level) - (u.xp | 0); if (!isFinite(need) || !gainXp(u, Math.max(1, need))) break; }
      log(`🩸 ${u.card.name} 부활! (Lv${u.level})`, 'text-fuchsia-300');
    }
    refreshAll(p); render();
  }
  return false;
}
function checkEnd() {
  if (S.over) return true;
  if (S.ai.hp <= 0 || S.me.hp <= 0) return finish(S.ai.hp <= 0, 'ko');
  if (S.story) {   // 스토리: 내 필드 카드 전멸 시 패배 / 일반전은 상대 카드 전멸 시 승리 (보스전은 진영 HP 0)
    const gone = p => !p.field.length && !p.hand.length && !p.deck.length;
    if (S.mustLiveDown) return finish(false, 'mustlive');
    awakenCheck();
    if (S.story.win === 'wipe' && gone(S.ai)) return finish(true, 'wipe');   // 그 순간 적 카드가 모두 쓰러져 있으면 승리 (부활 대기 중이어도)
    if (gone(S.me)) return finish(false, 'wipe');
  }
  return false;
}
/** 챕터 0 P3: story.awaken.on 카드가 필드에서 사라지면 각성 카드 난입 (한 번) — 전멸 판정보다 먼저 */
function awakenCheck() {
  const A = S.story?.awaken;
  if (!A || S.awakened || !A.card || S.me.field.some(u => String(u.card.id) === String(A.on))) return;
  S.awakened = true;
  const u = placeUnit(S.me, { ...A.card }, makeUnit, true);
  while (u.level < Math.min(A.battleLevel || 1, RULES.LEVEL_MAX)) levelUpOnce(u);
  u.hp = u.maxHp; u.mp = u.maxMp; u.canAttack = true;
  S.log.played.add(String(A.card.id));
  log(`⚡ ${A.card.name} 난입!`, 'text-fuchsia-300');
  render(); playSe(6);
  fxQueue.push(async () => {
    const t = document.createElement('div'); t.className = 'awaken-toast'; if (A.image) t.style.backgroundImage = `linear-gradient(rgba(30,0,50,.35),rgba(30,0,50,.75)),url(${A.image})`; t.innerHTML = `<b>⚡ 각성</b><span>${escHtml(A.line || A.card.name)}</span>`;
    document.body.appendChild(t); setTimeout(() => t.remove(), 2600);
    await withTimeout(cutIn(u, '각성', null), 2500);
    TUT('awaken', { id: A.card.id });
  });
  runFxQueue();
}
/** 소환 대기 카드(S.reserve) 소환 — 내 턴에 버튼. 지금은 무료(cost 0); 마나 코스트 설계가 오면 cost 만 채우면 됨 */
function summonReserve() {
  const r = S?.reserve?.[0];
  if (!r || S.turn !== 'me' || S.over || S.busy) return;
  if ((r.cost || 0) > S.me.mana) return;
  S.me.mana -= r.cost || 0; S.reserve.shift();
  const u = placeUnit(S.me, { ...r.card }, makeUnit);
  u.canAttack = true; S.log.played.add(String(r.card.id));
  log(`${S.me.name}: ${r.card.name} 소환`, 'text-violet-300');
  playSe(2); render(); onEnter('me', u); TUT('summoned', { id: r.card.id });
}
/** 턴 종료 후: 전체 턴 제한 도달 시 판정 */
function checkTimeout() {
  if (S.over || S.totalTurns < Math.min(maxTurns(), 400)) return S.over;   // 무제한도 400턴에서 안전 판정
  if (S.story) return finish(false, 'timeout');   // 스토리(일반·보스): 턴 제한 도달 = 패배
  const j = judgeTimeout(S.me, S.ai);
  return finish(j.winner === null ? null : j.winner === S.me, j.reason);
}

function endTurn() {
  if (S?.view) { S.view.ask?.({ k: 'end' }); return; }
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
    // 승리 보이스: <id>_9 가 있으면 우선, 없으면 기존처럼 스킬 보이스
    if (voiceSet.has(`${card.id}_9`)) return playVoiceKey(`${card.id}_9`) ? `${card.id}_9` : undefined;
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
    + row('고용한 용병', L.merc ? `${ic('merc')} ${L.merc.name}` : '없음') + row('진영 HP', `나 ${fmt(Math.max(0, S.me.hp))} : ${fmt(Math.max(0, S.ai.hp))} 상대`);
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
    if (!voiceOn || !voiceSet || !u || SWEEPING()) return;
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
  if (b) { b.innerHTML = ic(voiceOn ? 'sound_on' : 'sound_off'); b.title = voiceOn ? '스킬 보이스 끄기' : '스킬 보이스 켜기'; }
  if (r) { r.value = String(Math.round(voiceVol * 100)); r.disabled = !voiceOn; }
}
// ===== 효과음 (SE 시트: 코드 → audio/se/00코드_0n.mp3, 변형 중 무작위) =====
// 1 맞는 소리 · 2 카드 소환 · 3 본진 타격 · 4 버튼 클릭 · 5 UR 소환 · 6 MR 소환 · 7 공격하는 소리
const SE_FILES = { 1: 4, 2: 2, 3: 4, 4: 3, 5: 1, 6: 1, 7: 3 };
const SE_ON_KEY = 'vrTcgSe', SE_VOL = { 1: 0.1125, 2: 0.15, 3: 0.15, 4: 0.0875, 5: 0.1875, 6: 0.2, 7: 0.1125 };   // 효과음 음량: 다시 50% (2026-10-22 2차, 처음 값의 25%). 보이스·BGM 은 그대로
let seOn = localStorage.getItem(SE_ON_KEY) !== '0';
const seCache = new Map(), seLast = {};
function playSe(code) {
  try {
    if (!seOn || !code || !SE_FILES[code] || window.TCG_FAST) return;
    const now = performance.now(); if (now - (seLast[code] || 0) < 90) return; seLast[code] = now;
    const k = `${String(code).padStart(3, '0')}_${String(1 + Math.floor(Math.random() * SE_FILES[code])).padStart(2, '0')}`;
    let base = seCache.get(k); if (!base) { base = new Audio(`audio/se/${k}.mp3`); base.preload = 'auto'; seCache.set(k, base); }
    const a = base.paused || base.ended ? base : base.cloneNode();   // 겹쳐 재생 허용
    a.volume = (SE_VOL[code] || 0.125) * (voiceVol || 0.8); a.currentTime = 0;
    const pr = a.play(); if (pr?.catch) pr.catch(() => {});
  } catch {}
}
/** 뽑기 등급 스팅어(gacha_sr/ur): 효과음 취급 — 효과음 토글·음량 규칙(원래 값의 25%) 적용, 재생 중 BGM 덕킹으로 들리게 */
function playStinger(url) {
  try {
    if (!seOn || !url || window.TCG_FAST) return null;
    const a = new Audio(url); a.volume = 0.25 * (voiceVol || 0.8);
    const S2 = window.VRSound; S2?.duck?.(true);
    const off = () => S2?.duck?.(false); a.addEventListener('ended', off); a.addEventListener('error', off);
    a.play().catch(off); return a;
  } catch { return null; }
}
function setSeOn(on) { seOn = !!on; localStorage.setItem(SE_ON_KEY, seOn ? '1' : '0'); renderSeBtn(); }
function renderSeBtn() {
  const b = $('se-toggle'); if (b) { b.innerHTML = ic(seOn ? 'se_on' : 'se_off', { alt: '' }) || (seOn ? '🔔' : '🔕'); b.title = seOn ? '효과음 끄기' : '효과음 켜기'; b.setAttribute('aria-pressed', String(seOn)); }
  const m = $('main-se'); if (m) { m.textContent = seOn ? 'ON' : 'OFF'; m.setAttribute('aria-checked', String(seOn)); m.classList.toggle('on', seOn); }
}
// 버튼 클릭음: 모든 화면의 버튼 (연타는 90ms 간격으로 묶음)
document.addEventListener('pointerdown', e => { const b = e.target.closest?.('button'); if (b && !b.disabled && b.id !== 'se-toggle' && b.id !== 'main-se') playSe(4); }, true);
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
  return `${media}<div class="cutin-text"><div class="text-[11px] md:text-xs text-zinc-200">${u.owner.name} · ${u.card.name}${passive ? ' · 패시브' : ''}</div><div class="text-xl md:text-3xl font-black tracking-tight">${passive ? '✨ ' : ic('skill', { alt: '스킬' }) + ' '}${name}</div></div>`;
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
  if (CUT_OFF() || (FX_OFF() && !fx)) return;   // 연출 스킵 중엔 이미지 있는 스킬만 짧게
  const el = $('cutin');
  el.innerHTML = cutInHTML(u, name, fx, passive);
  const ms = FX_OFF() ? CUT_QUICK : cutinMs(fx ? 1300 : passive ? 500 : 750);
  el.style.setProperty('--dur', `${ms}ms`);
  el.className = `cutin ${fx ? 'cutin-img' : ''} fixed left-0 right-0 z-40 pointer-events-none text-center ${whoOf(u.owner) === 'me' ? 'cutin-me' : 'cutin-ai'}`;
  slashImpact(ms);
  await sleep(ms);
  el.className = 'hidden'; resetHScroll();
}
// ===== 등장 컷인 (data/voice/<id>_0 보이스 + data/fx/<id>_0 이미지, 없으면 프로필) · 만남/인연 이벤트 (data/events.json) =====
let EVENTS = { entry: { fx: [] }, events: [] };
fetch('data/events.json').then(r => r.ok ? r.json() : null).then(d => { if (d) EVENTS = { entry: { fx: [], ...(d.entry || {}) }, events: Array.isArray(d.events) ? d.events : [] }; }).catch(() => {});
function playVoiceKey(k) {
  try {
    if (!voiceOn || !voiceSet?.has(k)) return null;
    if (voiceCur) { try { voiceCur.pause(); voiceCur.currentTime = 0; } catch {} }
    const a = voiceAudio(k); a.volume = voiceVol; a.currentTime = 0; voiceCur = a;
    const pr = a.play(); if (pr?.catch) pr.catch(() => {}); return a;
  } catch { return null; }
}
const fxQueue = []; let fxQueueRun = false;
async function runFxQueue() {
  if (fxQueueRun) return; fxQueueRun = true;
  try { while (fxQueue.length) { const job = fxQueue.shift(); try { await job(); } catch (err) { reportError('fxQueue', err); } } } finally { fxQueueRun = false; }
}
/** 카드가 필드에 나왔을 때: 등장 컷인(있으면) → 이벤트 확인 */
function onEnter(who, u) {
  if (!S || !u) return;
  const id = String((u.base || u.card).id);
  // 등장 컷인: 등장 보이스(<id>_0) 또는 전용 이미지(events.json entry.fx) 중 하나라도 있으면
  if ((voiceSet?.has(`${id}_0`) || (EVENTS.entry.fx || []).map(String).includes(id)) && !S.fxSeen.has(`entry:${u.uid}`)) {
    S.fxSeen.add(`entry:${u.uid}`);
    if (S.story?.quest && questEntrySeenToday(u, id)) { checkEvents(); return; }
    if (S.story && !S.story.quest && who === 'me' && isUrMr(u)) { checkEvents(); return; }   // 스토리: 아군 UR·MR 등장 컷인(이미지·보이스) 생략, 적군은 그대로
    fxQueue.push(() => entryCutIn(u, id)); runFxQueue();
  }
  checkEvents();
}
// 시련의 탑: UR·MR 등장 컷인은 카드마다 하루 1번 (00:00 KST 초기화, 이 브라우저 기준). 스토리·아케이드는 그대로
const isUrMr = u => ['ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE'].includes((u.base || u.card).grade);
const Q_ENTRY_KEY = 'vrTcgQuestEntryCutin';
function questEntrySeenToday(u, id) {
  const g = (u.base || u.card).grade; if (g !== 'ULTRA RARE' && g !== 'MYTHIC RARE' && g !== 'LEGENDARY RARE') return false;
  const day = new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
  let d; try { d = JSON.parse(localStorage.getItem(Q_ENTRY_KEY) || '{}'); } catch { d = {}; }
  if (d.day !== day) d = { day, ids: [] };
  if (d.ids.includes(id)) return true;
  d.ids.push(id); try { localStorage.setItem(Q_ENTRY_KEY, JSON.stringify(d)); } catch {}
  return false;
}
async function entryCutIn(u, id) {
  if (!S || S.over) return;
  playVoiceKey(`${id}_0`);
  if (FX_OFF()) return;
  const el = $('cutin');
  const img = (EVENTS.entry.fx || []).map(String).includes(id) ? `data/fx/${id}_0.webp` : `${IMG}${id}.webp`;
  el.innerHTML = `<img src="${img}" class="cutin-media ${img.startsWith('data/') ? '' : 'cutin-portrait'}" alt="" onerror="this.remove()"><div class="cutin-text"><div class="text-xl md:text-3xl font-black tracking-tight">${escHtml(u.card.name)}</div></div>`;
  const ms = cutinMs(1300);
  el.style.setProperty('--dur', `${ms}ms`);
  el.className = 'hidden'; resetHScroll(); void el.offsetWidth;
  el.className = `cutin cutin-img cutin-entry fixed left-0 right-0 z-40 pointer-events-none text-center ${whoOf(u.owner) === 'me' ? 'cutin-me' : 'cutin-ai'}`;
  slashImpact(ms);
  await sleep(ms);
  if (el.classList.contains('cutin-entry')) el.className = 'hidden'; resetHScroll();
}
const fieldIds = p => new Set(p.field.map(x => String((x.base || x.card).id)));
/** 이벤트 조건 확인 (게임당 이벤트별 1회) */
function checkEvents() {
  if (!S || S.over) return;
  S.evSeen ||= new Set();
  const A = fieldIds(S.me), B = fieldIds(S.ai);
  const has = (set, ids) => ids.some(x => set.has(String(x)));
  for (const ev of EVENTS.events) {
    if (!ev?.id || S.evSeen.has(ev.id)) continue;
    let ok = false;
    if (ev.type === 'encounter' && Array.isArray(ev.sides) && ev.sides.length === 2) {
      const [x, y] = ev.sides; ok = (has(A, x) && has(B, y)) || (has(A, y) && has(B, x));
    } else if (ev.type === 'combo') {
      const c = combos().find(c => c.name === ev.combo); if (c) ok = c.cards.every(id => A.has(String(id))) || c.cards.every(id => B.has(String(id)));
    }
    if (!ok) continue;
    S.evSeen.add(ev.id);
    log(`🎬 이벤트: ${ev.title || ev.id}`, 'text-pink-300 font-bold');
    fxQueue.push(() => showEvent(ev)); runFxQueue();
  }
}
/** 이벤트 연출: 이미지 + 음성 + 짧은 대화. 탭하면 다음 대사, 마지막 대사 뒤 탭/자동으로 닫힘 */
function showEvent(ev) {
  if (window.TCG_FAST) return Promise.resolve();
  return new Promise(resolve => {
    let el = $('event-layer'); if (!el) { el = document.createElement('div'); el.id = 'event-layer'; document.body.appendChild(el); }
    const lines = Array.isArray(ev.lines) ? ev.lines : [];
    let i = 0, done = false, timer = null, audio = null;
    if (ev.voice && voiceOn) { try { if (voiceCur) voiceCur.pause(); audio = new Audio(ev.voice); audio.volume = voiceVol; trackVoice(audio); voiceCur = audio; audio.play().catch(() => {}); } catch {} }
    const close = () => { if (done) return; done = true; clearTimeout(timer); el.className = 'hidden'; resetHScroll(); el.innerHTML = ''; try { audio?.pause(); } catch {} resolve(); };
    const draw = () => {
      const L = lines[i];
      el.querySelector('.ev-line').innerHTML = L ? `${L.who && L.who !== 'NA' ? `<b>${escHtml(L.who)}</b>` : ''}<span class="${L.who === 'NA' ? 'ev-na' : ''}">${escHtml(L.text || '')}</span>` : '';
      el.querySelector('.ev-step').textContent = lines.length ? `${i + 1}/${lines.length} · 탭하여 계속` : '탭하여 닫기';
      clearTimeout(timer); timer = window.setTimeout(next, FX_OFF() ? 1600 : 2600);
    };
    const next = () => { if (++i >= lines.length) close(); else draw(); };
    el.className = 'ev-layer';
    el.innerHTML = `<div class="ev-panel"><div class="ev-title">🎬 ${escHtml(ev.title || '')}</div>${ev.image ? `<img class="ev-img" src="${ev.image}" alt="" onerror="this.remove()">` : ''}<div class="ev-line"></div><div class="ev-step"></div><button type="button" class="ev-skip">건너뛰기 ⏭</button></div>`;
    el.onclick = e => { e.stopPropagation(); if (e.target.closest('.ev-skip')) close(); else next(); };
    if (!lines.length) { timer = window.setTimeout(close, 4000); el.querySelector('.ev-step').textContent = '탭하여 닫기'; } else draw();
  });
}
/** 전투 시작 때 미뤄 둔 0턴 패시브 컷인: 등장 컷인 대기열 뒤에 차례로 (연출 스킵이면 각 0.6초) */
function flushHeldPassives() {
  const held = S?.holdPassive || []; if (S) S.holdPassive = null;
  for (const [u, n] of held) fxQueue.push(() => new Promise(r => { if (!S || S.over) return r(); passiveCutIn(u, n); setTimeout(r, FX_OFF() ? CUT_QUICK : cutinMs(1100)); }));
  if (held.length) runFxQueue();
}
/** 패시브 발동 연출: 카드별·스킬별 게임당 첫 발동만 큰 이미지(비동기, 턴 진행을 막지 않음), 이후는 작은 글자만 */
let passiveTimer = null;
// 패시브 MR 영상 대기열: 영상이 끝날 때까지 다음 행동(공격·스킬·AI 행동)이 vidWait() 로 기다림
let vidGate = Promise.resolve();
const vidWait = () => withTimeout(vidGate, 30000);
function passiveCutIn(u, name) {
  if (!S || SWEEPING()) return;
  if (S.holdPassive) { S.holdPassive.push([u, name]); return; }   // 전투 시작: 등장 컷인이 먼저
  S.fxSeen ||= new Set(); const key = `${u.uid}:${name}`;
  if (S.fxSeen.has(key)) return;
  const s = u.sk?.find(x => x.name === name);
  // MR 카드 패시브: 첫 발동 때 영상 (data/fx/mr/<id>_<n>.mp4). 없거나 실패하면 기존 패시브 컷인
  if (!FX_OFF() && (u.base || u.card).grade === 'MYTHIC RARE' && s) {
    S.fxSeen.add(key); const st = S;
    vidGate = vidGate.then(() => (S === st && !SWEEPING() ? mrVideo(u, s) : true)).then(ok => { if (!ok && S === st) passiveCutInPlain(u, name, s); }).catch(() => {});
    return;
  }
  passiveCutInPlain(u, name, s, key);
}
function passiveCutInPlain(u, name, s, key = null) {
  if (s?.fx || FX_OFF()) playVoice(u, name);
  if (CUT_OFF() || !s?.fx) { if (key && voiceKey(u, name)) S.fxSeen.add(key); return; }
  if (key) S.fxSeen.add(key);
  const el = $('cutin');
  el.innerHTML = cutInHTML(u, name, s.fx, true);
  const ms = FX_OFF() ? CUT_QUICK : cutinMs(1100);
  el.style.setProperty('--dur', `${ms}ms`);
  el.className = 'hidden'; resetHScroll(); void el.offsetWidth; // 애니메이션 재시작
  el.className = `cutin cutin-img fixed left-0 right-0 z-40 pointer-events-none text-center ${whoOf(u.owner) === 'me' ? 'cutin-me' : 'cutin-ai'}`;
  slashImpact(ms);
  clearTimeout(passiveTimer); passiveTimer = setTimeout(() => { el.className = 'hidden'; resetHScroll(); }, ms);
}

/** MR 스킬 영상: data/fx/mr/<카드id>_<스킬번호>.mp4 (영상은 항상 음소거, 소리는 기존 스킬 보이스).
 *  카드 인스턴스별 전투 중 스킬마다 첫 사용 때만. 탭하면 넘김. 파일 없음·로드 실패 → false (기존 컷인으로) */
function mrVideo(u, s) {
  if (FX_OFF() || (u.base || u.card).grade !== 'MYTHIC RARE') return Promise.resolve(false);
  const i = skillsOf(u.card.id).findIndex(x => x.name === s.name); if (i < 0) return Promise.resolve(false);
  const seen = (u.mrVid ||= new Set()); if (seen.has(i)) return Promise.resolve(false);
  seen.add(i);
  return new Promise(res => {
    const ov = document.createElement('div'); ov.className = 'mr-vid'; ov.setAttribute('role', 'button'); ov.setAttribute('aria-label', '탭하여 넘기기');
    const v = document.createElement('video'); v.muted = true; v.defaultMuted = true; v.playsInline = true; v.setAttribute('playsinline', ''); v.setAttribute('muted', ''); v.preload = 'auto';
    ov.innerHTML = `<div class="mr-vid-cap"><small>${escHtml(u.card.name)}</small><b>${escHtml(s.name)}</b></div><div class="mr-vid-skip">탭하여 넘기기</div>`; ov.prepend(v);
    let done = false, shown = false, t0, t1;
    const end = ok => { if (done) return; done = true; clearTimeout(t0); clearTimeout(t1); try { v.pause(); } catch {} ov.remove(); res(ok); };
    v.onerror = () => end(shown);
    v.onended = () => end(true);
    v.oncanplay = () => { if (shown || done) return; shown = true; clearTimeout(t0); document.body.appendChild(ov); playVoice(u, s.name);
      v.play().catch(() => end(true)); t1 = window.setTimeout(() => end(true), Math.min(15000, ((v.duration || 8) + 1.5) * 1000)); };
    ov.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); end(true); });
    t0 = window.setTimeout(() => end(false), 2500);   // 로드가 늦거나 파일 없음 → 기존 컷인
    v.src = `data/fx/mr/${u.card.id}_${i + 1}.mp4`; v.load();
  });
}

async function castSkill(who, u, s) {
  if (S?.view) { if (who === 'me' && S.view.ask && skillState(u, s).ok) S.view.ask({ k: 'skill', i: S.view.A0.indexOf(u), s: s.name }); return; }   // PvP·전쟁 화면: 엔진에 입력만 넘김
  const p = S[who];
  if (S.over || !p.field.includes(u) || !skillState(u, s).ok) return;
  const prevBusy = S.busy; S.busy = true; selected = null;
  try {
    render();
    if (!(await mrVideo(u, s))) await withTimeout(cutIn(u, s.name, s.fx), 3000);
    pendingDying = [];
    useSkill(u, s);
    await vidWait();
    if (who === 'me') S.log.skills++;
    renderHero('me'); renderHero('ai');
    await sleep(fxMs(450));
    await withTimeout(fadeDying(), 750);
  } catch (err) {
    reportError('skill', err);
  } finally {
    $('cutin').className = 'hidden'; resetAnim();
    S.busy = prevBusy;
    if (!prevBusy) fastForward = false;
    render();
    if (who === 'me') TUT('skill_used', { skill: s.name });
    checkEnd();
  }
}

/** 엔진 이벤트 → 로그·연출 */
function onEngine(e) {
  if (!S) return;
  // 소탕 시뮬(quest-sim)의 유닛 이벤트는 화면 전투와 무관 → 무시 (rules.js 가 공용 skills.js 의 emit 을 거침)
  if (e.unit && e.unit.owner && e.unit.owner !== S.me && e.unit.owner !== S.ai) return;
  const uEl = u => u && unitEl(whoOf(u.owner), u);
  const nm = u => u.card.name;
  if (e.type === 'dealt') { if (e.src.owner === S.me) { const L = S.log, k = e.src.card.id, r = L.dmg.get(k) || { card: e.src.card, dmg: 0 }; r.dmg += e.dmg; L.dmg.set(k, r); L.total += e.dmg; } return; }
  switch (e.type) {
    case 'skill': log(`${e.unit.owner.name}: ${nm(e.unit)} ⚡[${e.skill.name}] (MP ${e.skill.mp})`, 'text-fuchsia-300'); break;
    case 'passive': log(`${e.unit.owner.name}: ${nm(e.unit)} ✨[${e.name}]${e.text ? ' — ' + e.text : ''}`, 'text-fuchsia-200'); if (!FX_OFF()) dmgNumber(uEl(e.unit), `✨${e.name}`, '#f0abfc'); if (!CUT_OFF()) passiveCutIn(e.unit, e.name); break;
    case 'dmg': { playSe(1); const el = uEl(e.unit); shake(el); if (typeof e.dmg !== 'number' || e.dmg > 0) hitFx(el, 'blood'); if (typeof e.dmg === 'number') critNum(el, e.dmg, e.unit); else dmgNumber(el, e.dmg); break; }
    case 'hero': { if (e.dmg > 0) playSe(3); const el = heroEl(whoOf(e.p)); shake(el); if (e.dmg > 0) hitFx(el, 'blood'); dmgNumber(el, `-${fmt(e.dmg)}`, e.kind === 'self' ? '#fca5a5' : undefined); log(`${e.p.name} 본진 ${fmt(e.dmg)} 피해${e.kind === 'self' ? ' (자기 공격)' : ''}`, 'text-orange-300'); break; }
    case 'heal': dmgNumber(uEl(e.unit), `+${fmt(e.amt)}`, '#6ee7b7'); break;
    case 'heroHeal': dmgNumber(heroEl(whoOf(e.p)), `+${fmt(e.amt)}`, '#6ee7b7'); log(`${e.p.name} 본진 HP +${fmt(e.amt)}`, 'text-emerald-300'); break;
    case 'leaderDown': {
      const pc = Math.round((e.pct || 0.3) * 100);
      if (e.base) { const el = heroEl(whoOf(e.p)); shake(el); dmgNumber(el, `-${fmt(e.dmg)}`, '#fca5a5'); }
      log(`👑 ${e.p.name}: 리더 ${nm(e.unit)} 쓰러짐! 리더 스킬 해제 · ${e.base ? `진영 HP −${fmt(e.dmg)} (최대의 ${pc}%)` : `아군 진영 HP −${pc}% (남은 아군 ${e.n}장, 총 ${fmt(e.dmg)} 피해)`}`, 'text-red-400 font-bold');
      break; }
    case 'destroy': log(`${nm(e.unit)} 파괴!`, 'text-zinc-400'); pendingDying.push(uEl(e.unit)); if (S.story?.rules) storyOnDeath(e.unit); break;
    case 'refund': if (S.story && e.owner === S.me && e.killer?.card) { const k = String(e.killer.swap?.base.id || e.killer.card.id); S.log.kills[k] = (S.log.kills[k] || 0) + 1; }
      log(`${nm(e.killer)} 처치 보상: 마나 +${e.refund}`, 'text-sky-300'); if (e.refund > 0 && !FX_OFF()) dmgNumber(heroEl(whoOf(e.owner)), `${ic('mana')} +${e.refund} 마나`, '#7dd3fc', true); renderHero(whoOf(e.owner)); break;
    case 'levelup': log(`${nm(e.unit)} Lv${e.level}`, 'text-amber-300'); dmgNumber(uEl(e.unit), `⬆ Lv${e.level}`, '#fcd34d'); break;
    case 'status': { const st = STATUS[e.kind]; const t = e.kind === 'mod' ? e.text : `${st?.icon || ''} ${st?.label || e.kind}`; dmgNumber(uEl(e.unit), e.kind === 'mod' ? escHtml(t) : `${icOf(st)} ${escHtml(st?.label || e.kind)}`, '#c4b5fd', true); log(`${nm(e.unit)}: ${t}`, 'text-purple-300'); break; }
    case 'crit': critSet.add(e.unit); critFx(uEl(e.unit)); playSe(3); log(`💥 치명타! ${nm(e.src)} → ${nm(e.unit)}`, 'text-yellow-300'); break;
    case 'elfx': { const f = EL_FX[e.kind]; if (f) { dmgNumber(uEl(e.unit), f[0], f[1], false, 'fx-dmg-mini'); log(`${nm(e.unit)}: ${f[2]}`, 'text-zinc-300'); } break; }
    case 'immune': dmgNumber(uEl(e.unit), `${ic('immune')} 면역`, '#93c5fd', true); break;
    case 'heroImmune': dmgNumber(heroEl(whoOf(e.p)), `${ic('immune')} 무효`, '#93c5fd', true); break;
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
  await vidWait();
  for (const u of [...ai.field]) {
    await vidWait();
    if (S.over) break;
    if (!ai.field.includes(u) || !u.canAttack) continue;
    if (spareBlocked(u)) { u.canAttack = false; log(`${u.card.name}: 공격할 대상이 없어 턴을 넘깁니다`, 'text-zinc-400'); floatText(`${u.card.name} 행동 안 함`, 'text-zinc-300 text-sm', 'ai'); await sleep(AI_DELAY()); continue; }
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
  'LEGENDARY RARE': { short: 'LR', label: '레전더리 레어', cls: 'rar-lr' },
};
const rarityOf = c => RARITY[c.grade] || RARITY.NORMAL;
// ===== 카드 정보 공통 (전투 상세·확대·마이페이지·내 카드·갤러리): 그림 위주, 글자 최소 =====
/** 지역: 끝의 '구' 제거 (강남구 → 강남), 단 '중구'는 그대로 */
const regionShort = r => { r = String(r || '').trim(); return r === '중구' || r.length < 2 ? r : r.replace(/구$/, ''); };
const escA = s => String(s ?? '').replace(/[&<>"']/g, ch => `&#${ch.charCodeAt(0)};`);
/** 머리줄: 이름 (나이/지역) */
function cardTitle(c, lead = '') { const a = [c.age, regionShort(c.region)].filter(Boolean).join('/'); return `<span class="ci-name">${lead}${escA(c.name)}</span>${a ? ` <span class="ci-sub">(${escA(a)})</span>` : ''}`; }
/** 스킬 수 아이콘: 그림순이 img/ui/skill_count.webp (icons.js skill_count), 없으면 📜 */
/** 태그줄: 등급 약자 · 속성 아이콘 · 스킬 수 · 클래스 + 작은 태그(추가) */
function cardTags(c, extra = []) {
  const r = rarityOf(c), e = ELEMENTS[c.class] || ELEMENTS.WIND, n = skillsOf(c.id).length;
  return `<div class="ci-tags"><span class="rar-badge rar-inline ${r.cls}" title="${r.label}">${r.short}</span><span class="ci-el" title="${e.label}">${icOf(e)}</span>${n ? `<span class="ci-tag" title="스킬 ${n}개">${window.VRIcon?.or?.('skill_count', '📜') || '📜'}${n}</span>` : ''}<span class="ci-tag ci-cls">${escA(c.attribute || '')}</span>${extra.filter(Boolean).map(t => `<span class="ci-tag">${t}</span>`).join('')}</div>`;
}
/** ATK/DEF/HP: 아이콘 + 숫자 */
function cardStats(c, hp = null, power = false) {
  return `${power ? `<div class="ci-power" title="전투력 (레벨 반영)">⚡ <span>POWER</span> <b>${fmt(c.power)}</b></div>` : ''}<div class="ci-stats"><span class="ci-st atk" title="ATK">${ic('atk', { alt: 'ATK' })}<b>${fmt(c.ATK)}</b></span><span class="ci-st def" title="DEF">${ic('def', { alt: 'DEF' })}<b>${fmt(c.DEF)}</b></span><span class="ci-st hp" title="HP">${ic('hp', { alt: 'HP' })}<b>${hp != null ? fmt(+hp) + '/' : ''}${fmt(c.HP)}</b></span></div>`;
}
function cardHTML(c, { hp, size = 'md', dim = false } = {}) {
  const e = ELEMENTS[c.class] || ELEMENTS.WIND;
  const small = size === 'sm';
  const rar = rarityOf(c), nSk = skillsOf(c.id).length;
  return `
  <div class="card-frame ${rar.cls} relative ${small ? 'w-[64px] md:w-[96px]' : 'w-[78px] md:w-[110px]'} bg-zinc-900 rounded-xl overflow-hidden ${dim ? 'opacity-50' : ''} shadow-lg" data-grade="${rar.short}">
    <img src="${IMG}${c.id}.webp" data-id="${c.id}" class="card-img w-full aspect-[3/4] object-cover" alt="${c.name}">
    <button type="button" class="zoom-btn absolute bottom-[46px] md:bottom-[58px] right-1" data-zoom="${c.id}"${hp != null ? ` data-hp="${hp}"` : ''} title="크게 보기" aria-label="크게 보기">🔍</button>
    <div class="absolute top-1 left-1 w-6 h-6 md:w-7 md:h-7 rounded-full bg-sky-600 text-white text-[11px] md:text-xs font-black flex items-center justify-center border border-white/40">${c.cost}</div>
    <div class="absolute top-1 right-1 text-sm md:text-base" title="${e.label}">${icOf(e)}</div>
    <div class="rar-badge absolute left-1 top-7 md:top-9" title="${rar.label}">${rar.short}</div>
    ${nSk ? `<div class="sk-count absolute right-1 top-6 md:top-8" title="스킬 ${nSk}개">✦${nSk}</div>` : ''}
    <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black via-black/85 to-transparent px-1 pt-4 pb-1">
      <div class="text-[10px] md:text-xs font-bold truncate">${c.name}</div>
      <div class="text-[9px] md:text-[10px] text-amber-400 font-bold">⚡${fmt(c.power)}</div>
      <div class="flex justify-between whitespace-nowrap tracking-tighter ${small ? 'text-[8px]' : 'text-[9px]'} md:text-[11px] font-bold">
        <span class="text-orange-400">${ic('atk', { cls: 'ui-ic-sm' })}${fmt(c.ATK)}</span><span class="text-red-400">${ic('hp', { cls: 'ui-ic-sm' })}${fmt(hp ?? c.HP)}</span><span class="text-sky-400">${ic('def', { cls: 'ui-ic-sm' })}${fmt(c.DEF)}</span>
      </div>
    </div>
  </div>`;
}

// ===== DOM 차이 반영 (깜빡임 방지): 같은 자리의 같은 태그면 속성·글자만 고치고, 카드는 data-uid 로 짝을 맞춤 =====
function morphNode(o, n) {
  if (o.nodeType !== n.nodeType || o.nodeName !== n.nodeName || (o.nodeType === 1 && (o.dataset.uid || '') !== (n.dataset.uid || ''))) { o.replaceWith(n); return n; }
  if (o.nodeType === 3 || o.nodeType === 8) { if (o.nodeValue !== n.nodeValue) o.nodeValue = n.nodeValue; return o; }
  for (const a of [...o.attributes]) if (!n.hasAttribute(a.name)) o.removeAttribute(a.name);
  for (const a of n.attributes) if (o.getAttribute(a.name) !== a.value) o.setAttribute(a.name, a.value);
  morphChildren(o, n); return o;
}
function morphChildren(o, n) {
  const keyed = new Map(); for (const c of o.children) if (c.dataset?.uid) keyed.set(c.dataset.uid, c);
  const want = [...n.childNodes];
  want.forEach((nc, i) => {
    let cur = o.childNodes[i];
    const k = nc.nodeType === 1 && nc.dataset.uid;
    if (k && keyed.has(k) && keyed.get(k) !== cur) { const m = keyed.get(k); o.insertBefore(m, cur || null); cur = m; }   // 카드 순서가 바뀌어도 같은 노드 재사용
    if (!cur) o.appendChild(nc); else morphNode(cur, nc);
  });
  while (o.childNodes.length > want.length) o.lastChild.remove();
}
function patchHTML(el, html) { if (!el) return; const t = document.createElement('div'); t.innerHTML = html; morphChildren(el, t); }
function fixImages(root) {
  root.querySelectorAll('img.card-img').forEach(img => {
    img.onerror = () => { img.onerror = null; img.src = `${IMG}${img.dataset.id}.webp`; };
  });
}

function renderHero(who) {
  const p = S[who], max = p.maxHp || RULES.HERO_HP;
  $(`${who}-hp`).textContent = `${fmt(p.hp)} / ${fmt(max)}`;
  $(`${who}-hpbar`).style.width = Math.max(0, p.hp / max * 100) + '%';
  $(`${who}-mana`).innerHTML = `${p.mana} / ${p.maxMana}` + (p.accel ? ` ${ic('gear', { cls: 'ui-ic-sm' })}+${RULES.MANA_PER_TURN + p.accel * RULES.ACCEL_BONUS}/턴` : '');
  $(`${who}-deck`).textContent = p.deck.length;
  $(`${who}-handcount`).textContent = p.hand.length;
}

// ===== 내 남은 턴 표시 =====
const myMax = () => maxTurns() / 2;
function myTurnsLeft() { return Math.max(0, myMax() - S.myTurns + (S.turn === 'me' && !S.over ? 1 : 0)); }
function renderTurnsLeft() {
  const el = $('my-turns'); if (!el) return;
  if (!isFinite(myMax())) { el.className = 'turns-ok'; $('my-turns-n').textContent = '∞'; $('my-turns-max').textContent = ''; $('my-turns-pips').innerHTML = ''; return; }
  const n = myTurnsLeft(), lvl = n <= 2 ? 'crit' : n <= 5 ? 'warn' : 'ok';
  el.className = `turns-${lvl}`;
  $('my-turns-n').textContent = n; $('my-turns-max').textContent = '/' + myMax();
  $('my-turns-pips').className = `mt-1 turns-${lvl}-p`;
  $('my-turns-pips').innerHTML = Array.from({ length: myMax() }, (_, i) => `<i class="${i < n ? 'on' : ''}"></i>`).join('');
}
function lastTurnToast() {
  const t = document.createElement('div');
  t.className = 'last-turn-toast'; t.textContent = '⏳ 마지막 턴!';
  document.body.appendChild(t); setTimeout(() => t.remove(), 2200);
}

const hpPrev = new Map();
const hpText = t => String(t || '').replace(/체력/g, 'HP');
function render() {
  renderAutoBtn();
  if (S) preloadFx([...S.me.field, ...S.ai.field].map(u => u.base || u.card));
  renderTurnsLeft();
  if (!S) return;
  renderHero('me'); renderHero('ai');
  const myTurn = !!S && S.turn === 'me' && !S.over && !S.busy;
  const tl = isFinite(maxTurns()) ? `${Math.min(S.totalTurns, maxTurns())}/${maxTurns()}턴` : `${S.totalTurns}턴 (무제한)`;
  $('turn-info').textContent = S.over ? '게임 종료' : (S.turn === 'me' ? `내 턴 · ${tl}` : `상대 턴 · ${tl}...`);
  $('end-turn').disabled = !myTurn;
  for (const type of Object.keys(ACTIONS)) {
    const c = canAction(type, S.me), btn = $(`act-${type}`);
    btn.disabled = !myTurn || !c.ok;
    btn.querySelector('.reason').textContent = !myTurn ? '' : (c.ok ? '' : c.reason);
  }
  { const btn = $('act-merc'), done = S.mercBought >= Merc.MAX_PER_BATTLE;
    btn.disabled = !myTurn || done || !!S.limitedAids;
    btn.querySelector('.reason').textContent = S.limitedAids ? '일반대전 전용' : myTurn && done ? '이번 판 고용 완료' : ''; }
  if (S.story) { const b = $('act-shuffle'); b.disabled = true; b.querySelector('.reason').textContent = '스토리 불가'; }
  $('attack-all').disabled = !myTurn || !S.me.field.some(u => u.canAttack);
  { const rb = $('reserve-btn'), r = S.reserve?.[0]; if (rb) { rb.classList.toggle('hidden', !r || !!S.view); if (r) { rb.querySelector('img').src = `${IMG}${r.card.id}.webp`; rb.disabled = !myTurn || (r.cost || 0) > S.me.mana; } } }
  const selU = selected != null ? S.me.field.find(x => x.uid === selected) : null;
  if (selected != null && (!selU || !myTurn)) selected = null;
  const atkSel = selU?.canAttack ? selU : null;
  const tg = attackTargets(S.me, S.ai, atkSel);
  $('ai-hero').classList.toggle('ring-4', !!atkSel && tg.hero);
  $('ai-hero').classList.toggle('ring-red-500', !!atkSel && tg.hero);
  $('ai-hero').classList.toggle('opacity-70', S.turn === 'me' && !tg.hero);
  $('hero-hint').innerHTML = S.story && S.over ? '' : S.ai.noBase ? (S.over ? '' : $('game').classList.contains('view-raid') ? '🐉 균열 토벌: 15턴 동안 보스에게 최대한 큰 피해를!' : '⚔️ 일반전: 상대 카드를 모두 쓰러뜨리면 승리') : S.turn === 'me' && !S.over ? (tg.hero ? `${ic('taunt', { alt: '' })} 상대 진영 공격 가능` : `${ic('def', { alt: '' })} ${escHtml(tg.reason)}`) : '';
  $('hero-hint').className = `text-center text-[11px] md:text-xs font-bold ${tg.hero ? 'text-emerald-400' : 'text-amber-300'}`;

  for (const who of ['ai', 'me']) {
    const p = S[who];
    const lsk = p.leaderSkill, lAlive = lsk && p.field.some(x => x.isLeader);
    patchHTML($(`${who}-syn`), [
      lsk ? `<span class="px-1.5 rounded-full text-[10px] font-bold ${lAlive ? 'bg-amber-600/70 text-amber-50' : 'bg-zinc-700 text-zinc-400 line-through'}" title="리더 스킬 (${escHtml(lsk.name)} · ${escHtml(lsk.label)}): ${escHtml(lsk.text)}${lAlive ? '' : ' — 리더가 쓰러져 해제됨'}">${ic('crown', { alt: '' })}${escHtml(lsk.label)} ${escHtml(lsk.short)}</span>` : '',
      ...p.activeSyn.map(x => { const el = ELEMENTS[x.cls] || {}; return `<span class="px-1.5 rounded-full bg-white/10 text-[10px] font-bold" title="속성 시너지: ${el.label || x.cls} ${x.n}장 → ATK·DEF +${Math.round(x.pct * 100)}%">${icOf(el)}×${x.n} +${Math.round(x.pct * 100)}%</span>`; }),
      ...p.activeCombos.map(c => `<span class="px-1.5 rounded-full bg-fuchsia-700/60 text-[10px] font-bold" title="조합 [${c.name}]: ${c.scope === 'all' ? '아군 전체' : '조합 카드'} ${hpText(c.desc)} +${Math.round(c.value * 100)}%">🔗${c.name}</span>`),
      p.actionLock > 0 ? '<span class="px-1.5 rounded-full bg-red-800 text-[10px] font-bold" title="셔플·보강·강화·필드 회복 사용 불가">🔒고유기술 봉인</span>' : '',
      p.st?.heroShield ? `<span class="px-1.5 rounded-full bg-sky-800 text-[10px] font-bold" title="본진 방어력 +300% (피해 1/4)">${ic('def')}본진 방어</span>` : '',
      p.st?.heroInvuln ? `<span class="px-1.5 rounded-full bg-sky-800 text-[10px] font-bold" title="본진 공격 무효">${ic('immune')}본진 무적</span>` : '',
    ].join(''));
    const box = $(`${who}-field`);
    const bossBox = $(`${who}-boss`);
    // 깜빡임 방지: 새로 만든 뒤 기존 DOM 에 차이만 반영(morph, 카드 uid 기준). 바뀌지 않은 노드·그림·애니메이션은 그대로 유지
    const nb = document.createElement('div'), nbb = document.createElement('div'), binds = [];
    if (bossBox) bossBox.classList.toggle('hidden', !S[who].field.some(u => u.undying));
    if (!S[who].field.some(u => !u.undying)) nb.innerHTML = '<div class="text-zinc-600 text-xs self-center">빈 필드</div>';
    S[who].field.forEach(u => {
      const w = document.createElement('div');
      const isSel = selected === u.uid;
      const ready = who === 'me' && u.canAttack && myTurn;
      w.className = `unit ${u.undying ? 'boss-unit' : ''} cursor-pointer transition ${isSel ? '-translate-y-2 drop-shadow-[0_0_10px_#34d399]' : ''} ${ready ? 'ready' : ''} ${atkSel && who === 'ai' && tg.units.includes(u) ? 'target' : ''} ${isSel && !atkSel ? 'swap-sel' : ''}`;
      w.dataset.uid = u.uid;
      const hero = u.level >= RULES.LEVEL_MAX;
      const sts = statusIcons(u);
      const skReady = who === 'me' && myTurn && u.sk.some(s => skillState(u, s).ok);
      const icons = [u.items?.weapon && icOf(ITEMS.weapon), u.items?.armor && icOf(ITEMS.armor), ...u.skills.map(k => icOf(SKILLS[k]))].filter(Boolean);
      w.innerHTML = `<div class="relative ${hero ? 'hero-card' : ''}">${cardHTML(u.card, { hp: u.hp, size: 'sm', dim: who === 'me' && !u.canAttack && myTurn })}` +
        `<div class="lv-badge absolute -top-1.5 left-1/2 -translate-x-1/2 px-1.5 rounded-full ${hero ? 'bg-gradient-to-r from-yellow-300 to-amber-500 shadow-[0_0_8px_#fbbf24]' : u.level > 1 ? 'bg-amber-400' : 'bg-zinc-600 text-white'} text-black text-[9px] md:text-[10px] font-black whitespace-nowrap">${hero ? ic('crown', { cls: 'ui-ic-sm' }) + ' ' : ''}Lv${u.level}</div>` +
        (icons.length ? `<div class="item-icons absolute top-7 right-0.5 flex flex-col text-[11px] md:text-sm leading-tight drop-shadow">${icons.map(x => `<span>${x}</span>`).join('')}</div>` : '') +
        (sts.length ? `<div class="status-icons absolute top-7 left-0.5 flex flex-col text-[11px] md:text-sm leading-tight drop-shadow">${sts.map(x => `<span title="${x.title}">${icOf(x)}</span>`).join('')}</div>` : '') + `</div>` +
        `<div class="hp-bar h-1.5 bg-white/10 rounded-full mt-0.5 overflow-hidden" title="HP ${u.hp}/${u.maxHp}"><div class="hp-fill h-full bg-red-500" data-to="${u.maxHp ? Math.max(0, Math.min(100, u.hp / u.maxHp * 100)) : 0}" style="width:${hpPrev.get(String(u.uid)) ?? (u.maxHp ? Math.max(0, Math.min(100, u.hp / u.maxHp * 100)) : 0)}%"></div></div>` +
        `<div class="mp-bar h-1.5 bg-white/10 rounded-full mt-0.5 overflow-hidden" title="MP ${u.mp}/${u.maxMp} (+${u.mpRegen}/턴)"><div class="h-full bg-blue-500" style="width:${u.maxMp ? Math.min(100, u.mp / u.maxMp * 100) : 0}%"></div></div>` +
        // 상태 줄: 카드 너비를 넘지 않게 (width:0 + min-width:100% → 이 줄이 유닛 너비를 늘리지 않음). 둘 다면 '공격 가능'을 ⚔ 로 줄여 한 줄 유지
        `<div class="unit-tags flex justify-center items-center gap-1 h-4 whitespace-nowrap overflow-hidden" style="width:0;min-width:100%">${ready ? `<span class="text-[10px] text-emerald-400 font-bold" title="공격 가능">${skReady ? '⚔' : '공격 가능'}</span>` : ''}${skReady ? '<button class="skill-btn text-[10px] px-1 rounded bg-fuchsia-600 hover:bg-fuchsia-500 font-bold leading-4">✦스킬</button>' : ''}</div>`;
      binds.push([u.uid, el => {
        el.onclick = ev => { if (dragJustEnded) { ev.stopPropagation(); return; } onUnitClick(who, u); };
        if (who === 'me' && myTurn && el.__dragU !== u) { el.__dragU = u; enableDrag(el, u); }
        const sb = el.querySelector('.skill-btn'); if (sb) sb.onclick = ev => { ev.stopPropagation(); showDetail(u.card, { hp: u.hp, unit: u }); };
      }]);
      if (u.undying && bossBox) {   // 스토리 보스: 진영 안에 표시 (공격 대상 아님, 쓰러지지 않음)
        w.insertAdjacentHTML('afterbegin', `<div class="boss-crown" title="보스: 진영 안에 있어 공격할 수 없고 쓰러지지 않아요">${ic('crown', { alt: '보스' })}</div>`);
        const wrap = document.createElement('div'); wrap.className = 'flex items-center gap-2';
        wrap.appendChild(w);
        wrap.insertAdjacentHTML('beforeend', `<div class="text-[10px] md:text-xs leading-snug"><div class="font-black text-amber-300">${ic('crown', { alt: '' })} 보스</div><div class="text-zinc-300 font-bold truncate max-w-[64px] md:max-w-[120px]">${u.card.name}</div><div class="text-zinc-400">진영 안 · 불사</div><div class="text-zinc-500 hidden md:block">매 턴 공격·스킬 사용</div></div>`);
        nbb.appendChild(wrap);
      } else nb.appendChild(w);
    });
    morphChildren(box, nb); if (bossBox) morphChildren(bossBox, nbb);
    for (const [uid, fn] of binds) { const el = (box.querySelector(`[data-uid="${uid}"]`) || bossBox?.querySelector(`[data-uid="${uid}"]`)); if (el) fn(el); }
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
  patchHTML($('ai-handcards'), S.ai.hand.map(() => '<div class="flex-1 min-w-[3px] max-w-4 md:max-w-5 h-6 md:h-7 rounded bg-gradient-to-br from-zinc-700 to-zinc-900 border border-white/20"></div>').join(''));
}

// ===== 손패 정렬 =====
const SORT_KEY = 'tcg_hand_sort';
const GRADE_RANK = { 'NORMAL': 0, 'RARE': 1, 'HIGH RARE': 2, 'SUPER RARE': 3, 'ULTRA RARE': 4, 'MYTHIC RARE': 5, 'LEGENDARY RARE': 6 };
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
  const myTurn = !!S && S.turn === 'me' && !S.over && !S.busy;
  if (who === 'me') {
    // 탭 → 다른 내 카드 탭: 자리 바꾸기 (턴 소모 없음). 같은 카드 다시 탭: 선택 해제 + 정보
    const cur = selected != null ? S.me.field.find(x => x.uid === selected) : null;
    if (myTurn && cur && cur !== u && !u.undying) { if (swapField(S.me, cur, u)) { selected = null; playSe(4); render(); TUT('swapped'); return; } }
    if (myTurn && !u.undying && selected !== u.uid) { selected = u.uid; render(); TUT('card_selected', { index: S.me.field.indexOf(u) }); return; }
    if (selected === u.uid) { selected = null; render(); }
    showDetail(u.card, { hp: u.hp, unit: u });
  } else {
    if (myTurn && selected != null) {
      const a = S.me.field.find(x => x.uid === selected);
      if (a?.canAttack) { attack('me', a, u); return; }
      if (a) { selected = null; render(); }
    }
    showDetail(u.card, { hp: u.hp, view: u });
  }
}

function onHeroClick() {
  if (selected == null || S.turn !== 'me' || S.busy) return;
  const a = S.me.field.find(x => x.uid === selected);
  if (a?.canAttack) attack('me', a, null); // 규칙 위반이면 attack()이 사유를 보여줌
}

function showDetail(c, { fromHand = false, hp, unit = null, view = null, power = false } = {}) {
  const arcadeUi = !S?.story;   // 아케이드만: 아이템 장착·회수·희생 (스토리·탑·PvP·전쟁·토벌은 숨김)
  const e = ELEMENTS[c.class] || ELEMENTS.WIND;
  const check = fromHand ? canSummon(c, S.me, S.ai) : null;
  const myTurn = !!S && S.turn === 'me' && !S.over && !S.busy;
  $('detail-body').innerHTML = `
    <div class="flex gap-4">
      <div class="relative shrink-0"><img src="${IMG}${c.id}.webp" data-id="${c.id}" class="card-img w-32 md:w-40 aspect-[3/4] object-cover rounded-xl ring-2 ${e.ring}">${window.rarityStars?.(c, c.ex ? 'ex' : 'base', 'rstars-over') || ''}<button type="button" class="zoom-btn absolute bottom-1 right-1" data-zoom="${c.id}"${c.ex ? ` data-ex="${c.ex}" data-name="${String(c.name).replace(/[&"<>]/g, ch => `&#${ch.charCodeAt(0)};`)}"` : ''}${hp != null ? ` data-hp="${hp}"` : ''} title="크게 보기" aria-label="크게 보기">🔍</button></div>
      <div class="flex-1 min-w-0">
        <div class="text-xl font-black leading-tight">${cardTitle(c)}</div>
        ${cardTags(c, [power ? '' : `⚡${fmt(c.power)}`, `${ic('mana', { alt: '코스트' })}${c.cost}`])}
        ${cardStats(c, hp, power)}
      </div>
    </div>
    ${skillListHTML(c, unit || view, myTurn)}
    ${fromHand ? `
      ${check.ok || !myTurn ? '' : `<div id="summon-reason" class="mt-3 text-sm text-red-400">${check.reason}</div>`}
      <button id="summon-btn" ${check.ok && myTurn ? '' : 'disabled'} class="mt-4 w-full py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 disabled:opacity-40 text-black font-bold">소환하기</button>` : ''}
    ${unit ? `
      <div class="mt-3 flex items-center gap-2 text-sm"><span class="font-black ${unit.level >= RULES.LEVEL_MAX ? 'text-amber-300' : ''}">${unit.level >= RULES.LEVEL_MAX ? ic('crown') + ' 영웅 ' : ''}Lv${unit.level}</span>
        ${unit.level < RULES.LEVEL_MAX ? `<div class="flex-1 h-2 bg-white/10 rounded-full overflow-hidden"><div class="h-full bg-amber-400" style="width:${Math.min(100, unit.xp / xpToNext(unit.level) * 100)}%"></div></div><span class="text-[11px] text-zinc-400">XP ${unit.xp}/${xpToNext(unit.level)}</span>` : '<span class="text-[11px] text-zinc-400">최대 레벨</span>'}</div>
      ${unit.skills.length ? `<div class="mt-1 text-xs text-zinc-300">${unit.skills.map(k => `${icOf(SKILLS[k])} ${SKILLS[k]?.label || k}`).join(' · ')}</div>` : ''}
      ${arcadeUi ? `<div class="grid grid-cols-2 gap-2 mt-3">${Object.entries(ITEMS).map(([type, it]) => { const ce = canEquip(type, unit, S.me); return `
        <button data-equip="${type}" ${ce.ok && myTurn ? '' : 'disabled'} class="py-2 rounded-xl bg-amber-500 hover:bg-amber-400 disabled:opacity-40 text-black text-sm font-bold">${icOf(it)} ${it.label} ${it.desc()} <span class="text-sky-900">${ic('mana')}${it.cost()}</span><div class="text-[10px] font-normal h-3">${unit.items?.[type] ? '장착됨' : (!myTurn || ce.ok ? '' : ce.reason)}</div></button>`; }).join('')}</div>` : ''}` : ''}
    ${unit && arcadeUi ? (() => { const rc = canRecall(unit, S.me); return `
      ${rc.ok || !myTurn ? '' : `<div id="recall-reason" class="mt-3 text-sm text-red-400">${rc.reason}</div>`}
      <button id="recall-btn" ${rc.ok && myTurn ? '' : 'disabled'} class="mt-4 w-full py-3 rounded-2xl bg-sky-500 hover:bg-sky-400 disabled:opacity-40 text-black font-bold">회수 (마나 ${rc.cost})</button>
      <div class="text-[11px] text-zinc-500 mt-1 text-center">손패로 돌아가며 HP가 회복되고, 레벨·XP·아이템은 초기화됩니다</div>`; })() : ''}
    ${unit && arcadeUi ? (() => { const sc = canSacrifice(unit, S.me); return `
      <button id="sacrifice-btn" ${sc.ok && myTurn ? '' : 'disabled'} class="mt-2 w-full py-2.5 rounded-2xl bg-rose-600 hover:bg-rose-500 disabled:opacity-40 text-white font-bold">${ic('bleed', { alt: '' })} 희생 (마나 +${sc.gain})${sc.ok || !myTurn ? '' : ` — ${sc.reason}`}</button>
      <div class="text-[11px] text-zinc-500 mt-1 text-center">카드를 없애고 코스트의 ${Math.round(RULES.SACRIFICE_RATIO * 100)}%를 마나로 (턴당 1회)</div>`; })() : ''}`;
  fixImages($('detail-body'));
  if (unit) $('detail-body').querySelectorAll('[data-skill]').forEach(b => b.onclick = () => { const s = unit.sk[+b.dataset.skill]; hideModal('detail'); castSkill('me', unit, s); });
  if (unit) $('detail-body').querySelectorAll('[data-equip]').forEach(b => b.onclick = () => { const r = equipItem('me', unit, b.dataset.equip); if (r.ok) showDetail(unit.card, { hp: unit.hp, unit }); });
  if (unit && $('sacrifice-btn')) $('sacrifice-btn').onclick = () => { const r = doSacrifice('me', unit); if (r.ok) hideModal('detail'); };
  if (unit && $('recall-btn')) $('recall-btn').onclick = () => { const r = recall('me', unit); if (r.ok) hideModal('detail'); };
  if (fromHand) $('summon-btn').onclick = () => { const r = summon('me', c); if (r.ok) hideModal('detail'); };
  showModal('detail');
}

/** opt.skillLv: 보유 카드의 스킬 레벨 { "1": 3 } · opt.up: 레벨업 버튼(⬆) 표시 (스토리 내 카드 상세) */
function skillListHTML(c, unit, myTurn, lv = 1, opt = {}) {
  const list = unit ? unit.sk : skillsOf(c.id);
  const mine = unit && unit.owner === S.me;
  const head = unit ? `<div class="mt-3 flex items-center gap-2 text-xs"><span class="text-blue-300 font-bold">MP ${unit.mp}/${unit.maxMp}</span><div class="flex-1 h-2 bg-white/10 rounded-full overflow-hidden"><div class="h-full bg-blue-500" style="width:${unit.mp / unit.maxMp * 100}%"></div></div><span class="text-zinc-400">턴당 +${unit.mpRegen}</span></div>` +
    (statusIcons(unit).length ? `<div class="mt-1 text-xs text-purple-300">${statusIcons(unit).map(x => `${icOf(x)} ${x.title}`).join(' · ')}</div>` : '') : '';
  if (!list.length) return head;
  return head + `<div class="mt-3 space-y-2 max-h-64 overflow-y-auto pr-1">${list.map((s, i) => {
    const st = unit ? skillState(unit, s) : { ok: false, reason: `Lv${s.unlock} 해금` };
    const locked = (unit ? unit.level : lv) < s.unlock;
    const act = s.mode === 'active', slv = !act ? 1 : unit ? skillLvOf(unit, s) : Math.min(SKILL_LV_MAX, Math.max(1, (opt.skillLv || {})[i + 1] | 0 || 1));
    const showLv = act && (opt.up || slv > 1), cdNow = act ? skillCdAt(s.cooldown, slv) : 0;
    const lvBadge = showLv ? `<span class="sk-lv ${slv >= SKILL_LV_MAX ? 'max' : ''}" title="스킬 레벨 · 효과 +${Math.round((skillLvMult(slv) - 1) * 100)}% · 확률 +${+(skillLvProb(slv) * 100).toFixed(1)}%p">Lv${slv}</span>` : '';
    const upBtn = act && opt.up ? (locked ? `<span class="sk-up lock" title="카드 Lv${s.unlock}에 해금">🔒</span>` : slv >= SKILL_LV_MAX ? '' : `<button type="button" class="sk-up" data-skup="${i + 1}" title="스킬 레벨업">${ic('level_up', { alt: '⬆' }) || '⬆'}</button>`) : '';
    return `<div class="rounded-xl p-2 ${locked ? 'bg-zinc-800/50 opacity-60' : 'bg-zinc-800'}"><details class="ci-sk">
      ${opt.compact ? `<summary class="flex items-center gap-1.5"><span class="font-bold text-sm">${s.name}</span>${lvBadge || (act ? '' : '<span class="text-[10px] text-zinc-500">패시브</span>')}${locked ? `<span class="text-[10px] text-zinc-400">🔒 Lv${s.unlock}</span>` : ''}<span class="ml-auto">${upBtn}</span></summary>
      <div class="text-[10px] text-zinc-400 mt-1"><span class="px-1.5 rounded text-[10px] font-bold text-white ${TYPE_COLOR[s.type] || 'bg-zinc-600'}">${s.type}</span> ${act ? '액티브' : '패시브'} · Lv${s.unlock} 해금${act ? ` · MP ${s.mp} · 쿨 ${cdNow}` : ''}</div>` :
      `<summary class="flex items-center gap-1.5 flex-wrap"><span class="px-1.5 rounded text-[10px] font-bold ${TYPE_COLOR[s.type] || 'bg-zinc-600'}">${s.type}</span><span class="text-[10px] text-zinc-400">${s.mode === 'active' ? '액티브' : '패시브'}</span><span class="font-bold text-sm">${s.name}</span>${lvBadge}${upBtn}
        <span class="ml-auto text-[10px] text-zinc-400">${locked ? '🔒' : ''}Lv${s.unlock}${s.mode === 'active' ? ` · MP ${s.mp} · 쿨 ${cdNow}` : ''}</span></summary>`}
      <div class="text-[11px] text-zinc-300 mt-0.5">${hpText(s.desc)}${s.note ? ` <span class="text-zinc-500">(${hpText(s.note)})</span>` : ''}</div></details>
      ${s.mode === 'active' && mine ? `<button data-skill="${i}" ${st.ok && myTurn ? '' : 'disabled'} class="mt-1 w-full py-1.5 rounded-lg bg-fuchsia-600 hover:bg-fuchsia-500 disabled:opacity-40 text-xs font-bold">${st.ok ? '사용 (공격 대신)' : st.reason}</button>` : ''}
      ${s.mode === 'passive' && unit ? `<div class="text-[10px] mt-0.5 ${locked ? 'text-zinc-500' : 'text-emerald-400'}">${locked ? `Lv${s.unlock}에 해금` : (unit.fired[s.name] ? '발동됨' : '활성')}</div>` : ''}
    </div>`; }).join('')}</div>`;
}

function showModal(id) { $(id).classList.remove('hidden'); $(id).classList.add('flex'); }
function hideModal(id) { $(id).classList.add('hidden'); $(id).classList.remove('flex'); $(id).style.zIndex = ''; resetHScroll(); }
// 다른 화면(마이페이지 등) 위에서 카드 정보 보기: 전투 중이 아닌 보기 전용 상세
function showCardInfo(c, opt = {}) { if (!c) return; showDetail(c, { power: !!opt.power }); $('detail').style.zIndex = '130'; showModal('detail'); }
// 모바일에서 페이지가 옆으로 밀린 채 남지 않게 (컷인·모달 뒤) 가로 스크롤을 0으로
function resetHScroll() { if (window.scrollX || document.documentElement.scrollLeft || document.body.scrollLeft) { document.documentElement.scrollLeft = 0; document.body.scrollLeft = 0; window.scrollTo(0, window.scrollY); } }
window.addEventListener('scroll', () => { if (window.scrollX) resetHScroll(); }, { passive: true });

function renderStats() {
  const s = Stats.load();
  $('stats').textContent = `${window.VRCloud?.user ? '☁️ ' : ''}아케이드 전적: ${s.wins}승 ${s.losses}패${s.draws ? ` ${s.draws}무` : ''}`;
}

// ===== 용병 고용 UI =====
function renderMerc() {
  $('merc-list').innerHTML = S.mercOffer.map(c => {
    const r = Merc.canBuy(c, S.me), price = Merc.price(c);
    return `<div class="flex flex-col items-center gap-1">${cardHTML(c, { dim: !r.ok })}
      <button data-merc="${c.id}" ${r.ok ? '' : 'disabled'} class="w-full px-2 py-1.5 rounded-lg bg-amber-400 hover:bg-amber-300 disabled:bg-zinc-700 disabled:text-zinc-400 text-black text-xs font-bold">${r.hired ? '✅ 고용됨' : `${ic('mana')}${price}`}</button>
      <div class="text-[10px] h-3 ${r.ok ? 'text-zinc-500' : r.hired ? 'text-amber-300' : 'text-red-400'}">${r.ok ? `기본 ${c.cost} ×${Merc.PRICE[c.grade]}` : r.reason}</div></div>`;
  }).join('');
  $('merc-msg').innerHTML = `보유 마나 ${ic('mana')}${S.me.mana}`;
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
  floatText(`${ic('merc')} ${escHtml(c.name)} 고용!`, 'text-amber-300', 'me', true);
  hideModal('merc'); render();
}
$('act-merc').onclick = () => { if (S?.limitedAids || S?.story || S?.turn !== 'me' || S.over || S.busy) return; renderMerc(); showModal('merc'); };

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
{ const rb = $('reserve-btn'); if (rb) rb.onclick = summonReserve; }
for (const type of Object.keys(ACTIONS)) $(`act-${type}`).onclick = () => { if (S.story && type === 'shuffle') return; if (S.turn === 'me' && !S.busy && !S.over) useAction('me', type); };
$('ai-hero').onclick = onHeroClick;
$('help-btn').onclick = () => showModal('help');
$('main-help').onclick = () => showModal('help');
$('main-skip').onclick = () => { skipFx = !skipFx; localStorage.setItem(SKIP_KEY, skipFx ? '1' : '0'); renderSkipBtn(); };
$('voice-toggle').onclick = e => { e.stopPropagation(); voiceOn = !voiceOn; localStorage.setItem(VOICE_ON_KEY, voiceOn ? '1' : '0'); if (!voiceOn && voiceCur) try { voiceCur.pause(); } catch {} renderVoiceBtn(); };
$('se-toggle')?.addEventListener('click', e => { e.stopPropagation(); setSeOn(!seOn); });
// 전투 기록: 기본 접힘, 📜 버튼으로 펼치기 (상태 저장)
{ const LOG_KEY = 'vrTcgLogOpen', t = $('log-toggle'), lg = $('log');
  const set = on => { lg?.classList.toggle('hidden', !on); t?.setAttribute('aria-expanded', String(on)); };
  set(localStorage.getItem(LOG_KEY) === '1');
  t?.addEventListener('click', e => { e.stopPropagation(); const on = lg.classList.contains('hidden'); set(on); try { localStorage.setItem(LOG_KEY, on ? '1' : '0'); } catch {} }); }
$('main-se')?.addEventListener('click', e => { e.stopPropagation(); setSeOn(!seOn); });
renderSeBtn();
$('voice-vol').oninput = e => { voiceVol = (+e.target.value || 0) / 100; localStorage.setItem(VOICE_VOL_KEY, String(voiceVol)); if (voiceCur) voiceCur.volume = voiceVol; };
$('voice-vol').onclick = e => e.stopPropagation();
renderVoiceBtn();
$('spd-btn').onclick = e => { e.stopPropagation(); if (TUT_LOCK('speed')) return; spd2 = !spd2; localStorage.setItem(SPD_KEY, spd2 ? '1' : '0'); renderSpdBtn(); spdSync(); };
renderSpdBtn(); spdSync();
$('fx-skip').onclick = e => { e.stopPropagation(); if (TUT_LOCK('skip')) return; skipFx = !skipFx; localStorage.setItem(SKIP_KEY, skipFx ? '1' : '0'); if (S?.busy) fastForward = true; renderSkipBtn(); };
// 연출 중 화면을 누르면 현재 연출 빨리 감기
$('game').addEventListener('click', e => { if (S?.view && e.target.closest('button')) return; if (S?.busy && !S.over) fastForward = true; }, true);   // 화면 전투: AUTO·X2 등 버튼 탭은 빨리감기 아님
renderSkipBtn();
$('auto-btn').onclick = e => { e.stopPropagation(); if (TUT_LOCK('auto')) return; if (S?.view) { S.view.auto = !S.view.auto; renderAutoBtn(); if (S.view.auto) S.view.ask?.({ k: 'auto' }); return; } if (autoLocked()) return autoHint(); autoOn = !autoOn; localStorage.setItem(AUTO_KEY(), autoOn ? '1' : '0'); renderAutoBtn(); if (autoActive() && S.turn === 'me' && !S.busy) autoTurn(); };
function autoHint() {
  document.getElementById('auto-hint')?.remove();
  const t = document.createElement('div'); t.id = 'auto-hint'; t.className = 'auto-hint'; t.textContent = `🔒 계정 Lv${AUTO_LV}부터 AUTO`;
  document.body.appendChild(t); setTimeout(() => t.remove(), 1600);
}
renderAutoBtn();
$('share-btn').onclick = shareResult;
$('restart-btn').onclick = () => { renderStats(); startGame(); };
/** 스토리 모드 전투 시작 (js/story.js에서 호출) */
/** 스토리 [도전 포기]: 확인 후 패배 처리 */
function giveUp() {
  if (!S?.story || S.over) return;
  let ov = $('giveup-confirm');
  if (!ov) { ov = document.createElement('div'); ov.id = 'giveup-confirm'; ov.className = 'fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4'; document.body.appendChild(ov); }
  ov.innerHTML = `<div class="giveup-box bg-zinc-900 border border-white/15 rounded-2xl p-5 max-w-xs w-full text-center"><div class="text-lg font-black mb-1">도전을 포기할까요?</div><div class="text-sm text-zinc-400 mb-4">패배로 처리돼요. 전투 EXP·보상은 받지 않아요.</div><div class="flex gap-2"><button class="flex-1 py-2.5 rounded-xl bg-zinc-700 font-bold" data-gu="no">계속 싸우기</button><button class="flex-1 py-2.5 rounded-xl bg-red-600 font-bold" data-gu="yes">포기</button></div></div>`;
  ov.classList.remove('hidden');
  ov.onclick = e => { const b = e.target.closest('[data-gu]'); if (!b && e.target.closest('.giveup-box')) return; ov.classList.add('hidden'); if (b?.dataset.gu === 'yes' && !S.over) finish(false, 'giveup'); };
}
$('story-giveup')?.addEventListener('click', giveUp);
function startStory(cfg) { hideModal('detail'); startGame(cfg); }
$('home-btn').onclick = () => { try { window.VRSound?.setTrack?.('audio/main.mp3'); } catch {} $('end-screen').classList.add('hidden'); $('game').classList.add('hidden'); $('start-screen').classList.remove('hidden'); renderStats(); };
renderStats();
// ===== 아케이드 설정 팝업 =====
function renderArcadeOptsBtn() {
  const o = ArcadeOpts.load(), el = $('arcade-opts-sum'); if (!el) return;
  el.textContent = ArcadeOpts.isDefault(o) ? '기본' : ArcadeOpts.summary(o);
  $('arcade-opts-btn')?.classList.toggle('on', !ArcadeOpts.isDefault(o));
}
function openArcadeOpts() {
  let o = ArcadeOpts.load();
  const draw = () => {
    const sel = o.grades ? new Set(o.grades) : new Set(GRADES);
    $('ao-presets').innerHTML = ArcadeOpts.PRESETS.map(p => `<button type="button" class="ao-chip ${ArcadeOpts.gradeLabel(o) === p.label ? 'on' : ''}" data-pre="${p.k}">${p.label}</button>`).join('');
    $('ao-grades').innerHTML = GRADES.map(g => `<button type="button" class="ao-chip ao-g rar-${GRADE_SHORT[g].toLowerCase()} ${sel.has(g) ? 'on' : 'off'}" data-g="${g}" aria-pressed="${sel.has(g)}">${GRADE_SHORT[g]}</button>`).join('');
    const tot = [...sel].reduce((t, g) => t + RULES.DRAW_RATES[g], 0);
    $('ao-rates').textContent = '뽑기 확률: ' + GRADES.filter(g => sel.has(g)).map(g => `${GRADE_SHORT[g]} ${(RULES.DRAW_RATES[g] / tot * 100).toFixed(tot < 1 ? 1 : 0)}%`).join(' · ') + (sel.has('MYTHIC RARE') ? ' (MR은 덱당 최대 1장)' : '');
    $('ao-turns').innerHTML = ArcadeOpts.TURNS.map(t => `<button type="button" class="ao-chip ${o.turns === t ? 'on' : ''}" data-t="${t}">${t ? t + '턴' : '무제한'}${t === 40 ? ' (기본)' : ''}</button>`).join('');
    const c = $('ao-clear'); c.textContent = o.clearFirst ? 'ON' : 'OFF'; c.setAttribute('aria-checked', String(!!o.clearFirst)); c.classList.toggle('on', !!o.clearFirst);
    ArcadeOpts.save(o);
  };
  const m = $('arcade-opts');
  m.onclick = e => {
    const b = e.target.closest('button');
    if (e.target === m || e.target.closest('[data-ao-close]')) { hideModal('arcade-opts'); return; }
    if (!b) return;
    if (b.dataset.pre) { const p = ArcadeOpts.PRESETS.find(x => x.k === b.dataset.pre); o.grades = p.grades ? [...p.grades] : null; }
    else if (b.dataset.g) { const cur = new Set(o.grades || GRADES); cur.has(b.dataset.g) ? cur.delete(b.dataset.g) : cur.add(b.dataset.g); if (!cur.size) return; o.grades = cur.size === GRADES.length ? null : GRADES.filter(g => cur.has(g)); }
    else if (b.dataset.t != null) o.turns = Number(b.dataset.t);
    else if (b.id === 'ao-clear') o.clearFirst = !o.clearFirst;
    else if (b.id === 'ao-reset') o = { ...ArcadeOpts.DEF };
    else if (b.id === 'ao-start') { hideModal('arcade-opts'); startGame(); return; }
    else return;
    draw();
  };
  draw(); showModal('arcade-opts');
}
$('arcade-opts-btn')?.addEventListener('click', e => { e.stopPropagation(); playSe(4); openArcadeOpts(); });
renderArcadeOptsBtn();
window.addEventListener('vr:user', renderStats);   // 로그인·로그아웃·계정 변경 시 바로 갱신

(async () => {
  try {
    // NPC 카드 (npc 칸 = 1, data/npc_cards.csv): 스토리 적 전용. 뽑기·갤러리·보유 카드·아케이드·카드 풀(POOL)에서 제외
    { const all = parseCSV(await (await fetch('data/cards.csv')).text()), npc = await fetch('data/npc_cards.csv').then(r => r.ok ? r.text() : '').then(t => t ? parseCSV(t) : []).catch(() => []);
      POOL = all.filter(c => !isNpc(c)); NPC = [...all.filter(isNpc), ...npc.filter(isNpc)]; }
    setCardPool(POOL);
    const [sk, co] = await Promise.all(['data/skills.json', 'data/combos.json'].map(u => fetch(u).then(r => r.json())));
    setSkillData(sk, co); setEmitter(onEngine); globalThis.VRQuestSkillMult = c => skillCountMult(skillsOf(c?.id));
    $('start-btn').disabled = false; setStartLabel('아케이드');
    $('start-btn').onclick = () => startGame();
    window.dispatchEvent(new CustomEvent('tcg:ready'));
  } catch (e) { setStartLabel('카드 데이터를 불러오지 못했어요'); }
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
    ${stars}<img class="zoom-img" src="${src}" alt="${String(title).replace(/<[^>]*>/g, '').replace(/"/g, '')}">
    <div class="zoom-info"><div class="text-xl font-black">${title}</div>${sub ? `<div class="text-sm text-zinc-300 mt-0.5">${sub}</div>` : ''}${stats ? `<div class="mt-1 font-bold text-sm flex gap-3 justify-center flex-wrap">${stats}</div>` : ''}</div>`;
  ov.classList.add('open');
}
function closeZoom() { const ov = $('zoom-view'); if (ov) ov.classList.remove('open'); }
function zoomFromBtn(b) {
  const c = POOL.find(x => String(x.id) === b.dataset.zoom) || NPC.find(x => String(x.id) === b.dataset.zoom); if (!c) return;   // 스토리 NPC(불량배 등)도 같은 정보창
  const r = rarityOf(c), e = ELEMENTS[c.class] || ELEMENTS.WIND, hp = b.dataset.hp;
  openZoom({ src: `${IMG}${c.id}.webp`, stars: window.rarityStars?.(c, b.dataset.ex ? 'ex' : 'base', 'rstars-lg') || '',   // 스토리 EX 카드: 빨간 별
    title: cardTitle({ ...c, name: b.dataset.name || c.name }),
    sub: cardTags(c, [`⚡${fmt(c.power)}`, `${ic('mana', { alt: '코스트' })}${c.cost}`]),
    stats: cardStats(c, hp != null ? +hp : null) });
}
// 캡처 단계에서 가로채서 카드 선택/드래그/상세창이 같이 동작하지 않게 함
['pointerdown', 'mousedown', 'touchstart'].forEach(t => document.addEventListener(t, e => { if (e.target.closest?.('.zoom-btn')) e.stopPropagation(); }, { capture: true, passive: true }));
document.addEventListener('click', e => { const b = e.target.closest?.('.zoom-btn'); if (!b) return; e.stopPropagation(); e.preventDefault(); zoomFromBtn(b); }, true);
document.addEventListener('keydown', e => { if (e.key === 'Escape' && $('zoom-view')?.classList.contains('open')) { e.stopPropagation(); closeZoom(); } }, true);


// ===== PvP·구역 전쟁 전투 화면: 스토리·탑과 같은 화면/연출, 전투 계산은 서버 seed 엔진(pvp-core matchGen) 그대로 =====
// session = manualMatch/warSession(view:true). 화면은 엔진이 한 행동씩 멈출 때(anim) 연출하고, 내 차례(ask)면 입력을 기다림. 결과·행동 기록은 엔진 것 그대로
/** raid: { stage, bossId, bossName, hpLeft, hpMax, cap, weakLabel, deadline(ms) } → 균열 토벌 화면 (큰 보스 HP 바 · 누적 피해 · 남은 시간) */
async function viewBattle({ session, aiName = '상대', bg = 'normal', manual = false, maxTurns: mt = 40, title = '', raid = null, tutorial = null } = {}) {
  if (tutorial) setTimeout(() => window.VRTutorial?.start(tutorial), 900);   // 튜토리얼 가이드 (js/tutorial.js)
  // 전투 화면을 띄운 팝업 층(조직 .gd-ov · 토벌/전쟁 .gd-pop · PvP · 마이페이지 등)은 전투 동안 숨겼다가 끝나면 그대로 복원
  const LAYERS = '.pvp-modal, .pvp-vsx, .gd-ov, .gd-pop, .mp-modal, .gal-modal, .ad-modal, #start-screen, #story-screen';
  const hid = [...document.querySelectorAll(LAYERS)].filter(e => !e.classList.contains('hidden') && e.style.display !== 'none');
  hid.forEach(e => { e.dataset.vbHide = e.style.display; e.style.display = 'none'; });
  const hubWasOn = !$('start-screen').classList.contains('hidden');   // 메인 허브: 전투 후 class 'hidden' 도 원래대로 (조직 닫으면 검은 화면 방지)
  let x = session.next();
  const V = { auto: !manual, A0: x.value.A0, B0: x.value.B0, ask: null }; fastForward = false;
  S = { me: x.value.A, ai: x.value.B, view: V, story: { win: 'wipe', view: true, aiName }, maxTurns: mt, first: 'me', turn: 'me', turnNo: 0, totalTurns: 0, myTurns: 0, over: false, busy: true, fxSeen: new Set(), mercBought: 0, mercHired: null, mercOffer: [], limitedAids: true,
    log: { dmg: new Map(), total: 0, skills: 0, merc: null, played: new Set(), kills: {} } };
  S.me.name = '나'; S.ai.name = aiName;
  selected = null; $('log').innerHTML = ''; fxQueue.length = 0; vidGate = Promise.resolve(); hpPrev.clear();
  $('end-screen').classList.add('hidden'); $('start-screen').classList.add('hidden'); $('game').classList.remove('hidden');
  $('game').classList.add('story-field', 'view-battle'); $('game').classList.toggle('view-raid', !!raid);
  // ---- 균열 토벌: 보스 배너 (그림 · 단계 · 공유 HP 바 · 이번 판 피해 · 남은 시간) ----
  let RB = null, tick = 0;
  const raidPaint = (dmg, d = 0) => {
    if (!RB) return; const left = Math.max(0, raid.hpLeft - dmg), pct = raid.hpMax ? left / raid.hpMax * 100 : 0;
    RB.querySelector('.vbr-fill').style.width = pct + '%'; RB.querySelector('.vbr-lag').style.width = pct + '%';
    RB.querySelector('.vbr-hp').textContent = `${fmt(left)} / ${fmt(raid.hpMax)}`;
    const n = RB.querySelector('.vbr-dmg b'); n.textContent = fmt(dmg);
    if (d > 0 && !FX_OFF()) { n.classList.remove('pop'); void n.offsetWidth; n.classList.add('pop'); RB.classList.remove('hit'); void RB.offsetWidth; RB.classList.add('hit'); }
  };
  if (raid) {
    RB = document.createElement('div'); RB.id = 'vb-raid';
    RB.innerHTML = `<img class="vbr-pic" src="${IMG}${raid.bossId}.webp" alt=""><div class="vbr-main"><div class="vbr-top"><b>${escHtml(raid.bossName)}</b><span class="vbr-st">${raid.stage}단계</span>${raid.weakLabel ? `<span class="vbr-weak">약점 ${escHtml(raid.weakLabel)}</span>` : ''}<span class="vbr-time"></span></div>
      <div class="vbr-bar"><i class="vbr-lag"></i><i class="vbr-fill"></i><span class="vbr-hp"></span></div>
      <div class="vbr-dmg">이번 판 피해 <b>0</b><small>· 1회 상한 ${fmt(raid.cap)}</small></div></div>`;
    $('top-bar').before(RB);
    const t = () => { const ms = Math.max(0, (raid.deadline || 0) - Date.now()), m = Math.floor(ms / 60000), sec = Math.floor(ms / 1000) % 60, el = RB.querySelector('.vbr-time'); if (!el) return; el.textContent = `⏱ ${m}:${String(sec).padStart(2, '0')}`; el.classList.toggle('low', ms < 120000); };
    if (raid.deadline) { t(); tick = setInterval(t, 1000); }
    raidPaint(0);
  }
  for (const w of ['me', 'ai']) { $(`${w}-hp`).classList.add('hidden'); $(`${w}-hpbar`).parentElement.classList.add('hidden'); }
  { const lbl = $('ai-order').parentElement.firstChild; if (lbl?.nodeType === 3) lbl.textContent = `${aiName} `; }
  setBattleBg(bg); preloadHit(); preloadFx([...S.me.field, ...S.ai.field].map(u => u.base || u.card));
  if (title) log(title, 'text-amber-300');
  log(raid ? `🐉 균열 토벌 · 내 턴 ${mt / 2}번 동안 최대한 큰 피해를 (행동 1번 상한 ${fmt(raid.cap)})` : '⚔️ 마나 없음 · 상대를 모두 쓰러뜨리면 승리', 'text-amber-300');
  render();
  const drain = () => { const ev = session.events || []; const out = ev.splice(0, ev.length); return out; };
  // 마나 없음: 처치 마나(refund) 연출 생략. 같은 카드에 숫자가 겹치지 않게 조금씩 띄워 보여 줌
  const bossNum = (d, weak) => { if (!raid || !(d > 0)) return; const el = unitEl('ai', V.B0[0]); shake(el); hitFx(el, 'blood'); dmgNumber(el, `-${fmt(d)}`, d >= raid.cap ? '#f97316' : '#fde047', false, 'fx-dmg-crit fx-dmg-raid'); if (weak) dmgNumber(el, '약점!', '#fca5a5', false, 'fx-dmg-mini'); if (d >= raid.cap) dmgNumber(el, 'MAX', '#fb923c', false, 'fx-dmg-mini'); };
  const play = async (evs, gap = 0) => { const seen = new Map(); for (const e of evs) { if (e.type === 'refund') continue; if (raid && e.type === 'dmg' && e.unit === V.B0[0]) continue;   /* 보스 원래 피해 숫자 대신 상한 적용 피해(bossNum) */
    try { onEngine(e); } catch (err) { reportError('view', err); }   // ⚠️ 주석 뒤에 붙이면 통째로 꺼짐 (#190~#195 스킬 타격·상태·레벨업 연출 누락 원인)
    if (gap && e.unit && ['levelup', 'mp', 'status', 'heal', 'immune', 'miss', 'resist', 'elfx'].includes(e.type)) { const n = (seen.get(e.unit) || 0) + 1; seen.set(e.unit, n); if (n > 0) await sleep(fxMs(gap)); } } };
  try {
    for (let g = 0; !x.done && g < 20000; g++) {
      const v = x.value;
      if (v.anim) {
        const a = v.anim, who = a.side === 'A' ? 'me' : 'ai', evs = drain();
        fastForward = false;   // 탭 빨리감기는 그 행동 하나만 (스토리처럼) — 안 풀면 한 번 탭 뒤 전투 전체가 연출 없이 순식간에 끝남
        if (a.k === 'turn' && !S.totalTurns) { $('me-order').textContent = who === 'me' ? '선공' : '후공'; $('ai-order').textContent = who === 'ai' ? '선공' : '후공'; }
        if (a.k === 'turn') { S.turn = who; S.totalTurns++; if (who === 'me') S.myTurns++; S.busy = true; render(); if (raid && who === 'me') floatText(`T${a.t}/${mt / 2}`, 'text-amber-200 text-2xl', 'me'); await play(evs, 160); if (raid) { bossNum(v.damage - (S.vDmg || 0)); S.vDmg = v.damage; raidPaint(v.damage, 1); } await sleep(AI_DELAY()); }
        else if (a.k === 'skill') { S.busy = true; selected = null;   /* 컷인 전엔 다시 그리지 않음: 엔진은 이미 스킬 결과(처치 포함)를 반영 → 그리면 맞을 카드가 먼저 사라짐 */ if (!(await mrVideo(a.u, a.s))) await withTimeout(cutIn(a.u, a.s.name, a.s.fx), 3000); pendingDying = []; await play(evs, 160); if (raid) { bossNum(a.d, a.weak); S.vDmg = v.damage; raidPaint(v.damage, a.d); } if (who === 'me') S.log.skills++; render(); await sleep(fxMs(450)); await withTimeout(fadeDying(), 750); if (who === 'me') TUT('skill_used', { skill: a.s?.name }); }
        else if (a.k === 'atk') {
          S.busy = true; const oWho = who === 'me' ? 'ai' : 'me', aEl = unitEl(who, a.u), tEl = a.t ? unitEl(oWho, a.t) : null;
          playSe(7); const hit = await withTimeout(lunge(aEl, tEl), 750); pendingDying = [];
          { const h = (a.hits || []).find(e => e.type === 'hit'); log(`${a.u.card.name} → ${a.t?.card?.name || '?'}${h ? ` ${fmt(h.d1)} 피해${h.mult !== 1 ? ` (속성 ×${h.mult})` : ''}${h.killed ? ', 처치' : h.d2 ? `, 반격 ${fmt(h.d2)}` : ''}` : ' 회피'}`, who === 'me' ? 'text-emerald-300' : 'text-red-300'); }
          const late = evs.filter(e => !['dmg', 'crit', 'dealt', 'destroy', 'hero'].includes(e.type)); await play(evs.filter(e => !late.includes(e)));
          for (const e of a.hits || []) {
            playSe(e.type === 'hit' ? 1 : 0);
            if (e.type === 'hit') { const real = e.target || a.t, rEl = (real && unitEl(oWho, real)) || tEl; shake(rEl); hitFx(rEl, e.mult > 1 ? 'blood' : 'impact'); if (raid && real === V.B0[0]) critSet.delete(real); else critNum(rEl, e.d1, real); if (e.d2) { shake(aEl); hitFx(aEl); dmgNumber(aEl, `-${fmt(e.d2)}`, '#fca5a5'); } }
            else if (e.type === 'evade') dmgNumber(unitEl(oWho, e.target) || tEl, 'MISS', '#e0f2fe');
          }
          critSet.clear(); if (raid) { bossNum(a.d, a.weak); S.vDmg = v.damage; raidPaint(v.damage, a.d); }
          await withTimeout(hit?.back?.() ?? Promise.resolve(), 750); resetAnim(aEl); await play(late, 220); render(); await withTimeout(fadeDying(), 750); if (who === 'me') TUT('attack_done'); await sleep(AI_DELAY());
        } else { await play(evs, 160); if (raid && a.d) { bossNum(a.d); S.vDmg = v.damage; raidPaint(v.damage, a.d); } render(); }
        x = session.next(); continue;
      }
      if (v.ask) {
        await play(drain()); S.turn = 'me'; S.busy = false; render();
        // 일괄 공격 대기열: 아직 행동 가능한 카드부터 차례로 (대상 = 공격 가능한 첫 적, 토벌은 보스)
        const fromBatch = () => { while (V.batch?.length) { const u = V.batch.shift(); if (!u.canAttack || u.hp <= 0 || !S.me.field.includes(u)) continue; const t = autoTarget(u, S.me, S.ai); if (t == null) continue; return { k: 'atk', i: V.A0.indexOf(u), t: V.B0.indexOf(t) }; } V.batch = null; return null; };
        const inp = V.auto ? { k: 'auto' } : fromBatch() || await new Promise(res => { V.ask = i => { V.ask = null; V.nextBatch = null; res(i); }; V.nextBatch = () => { const b = fromBatch(); if (b) V.ask(b); }; });
        V.ask = null; selected = null; S.busy = true;
        x = session.next(inp); continue;
      }
      x = session.next();
    }
    await play(drain());
    S.over = true; render(); TUT('battle_end', { win: !!(x.value && x.value.win) });
    if (raid) { raidPaint(x.value?.damage || 0, 1); try { window.VRSound?.jingle?.('victory'); } catch {} floatText(`총 피해 ${fmt(x.value?.damage || 0)}`, 'text-amber-300 text-3xl', 'ai'); }
    else { try { window.VRSound?.jingle?.(x.value?.win ? 'victory' : 'defeat'); } catch {}
      floatText(x.value?.win ? 'WIN' : 'LOSE', x.value?.win ? 'text-emerald-300 text-5xl' : 'text-red-400 text-5xl', 'ai'); }
    await sleep(window.TCG_FAST ? 0 : 1200);
    return x.value;
  } finally {
    clearInterval(tick); RB?.remove();
    $('game').classList.remove('view-battle', 'view-raid', 'story-field'); $('game').classList.add('hidden');
    hid.forEach(e => { e.style.display = e.dataset.vbHide || ''; delete e.dataset.vbHide; });
    if (hubWasOn) $('start-screen').classList.remove('hidden');
    S = null; selected = null;
  }
}
window.TCG = { viewBattle, get NPC() { return NPC; }, cardById: id => POOL.find(c => String(c.id) === String(id)) || NPC.find(c => String(c.id) === String(id)), isNpc, cardTitle, cardTags, cardStats, regionShort, playStinger, showCardInfo, skillsOf, combos, arcadeOpts: ArcadeOpts, openArcadeOpts, playSe, onEnter, checkEvents, showEvent, mvpVoice, get events() { return EVENTS; }, get seOn() { return seOn; }, skillListHTML: (c, lv, opt) => skillListHTML(c, null, false, lv, opt), voiceTest(k) { if (!voiceSet?.has(k)) return false; const a = voiceAudio(k); a.volume = voiceVol; a.currentTime = 0; voiceCur = a; a.play().catch(() => {}); return true; }, get voiceActive() { return voiceActive.size; }, get voice() { return { on: voiceOn, vol: voiceVol, cur: voiceCur && { src: voiceCur.src, paused: voiceCur.paused, t: voiceCur.currentTime }, set: voiceSet && voiceSet.size }; }, openZoom, closeZoom, dupCheck, get errors() { return window.TCG_ERRORS || []; }, cutIn, passiveCutIn, sortedHand, get handSort() { return handSort; }, put: debugPut, castSkill, skillState, get S() { return S; }, RULES, calcPower: c => calcPower(c, skillsOf(c?.id)), skillLvPowerMult: (id, lvMap) => skillLvPowerMult(skillsOf(id), lvMap), elementMultiplier, calcDamage, canSummon, buildDeck, summon, attack, recall, attackAll, endTurn, canRecall, recallCost, makeUnit, resolveAttack, useAction, canAction, startGame, startStory, cardHTML, get ready() { return POOL.length > 0; }, equipItem, doSacrifice, finish, attackTargets, get POOL() { return POOL; }, render, Stats };
