import { RULES, ELEMENTS, elementMultiplier, calcDamage, canSummon, buildDeck, parseCSV, aiSummonOrder, aiPickTarget, recallCost, canRecall, aiShouldRecall, makeUnit, resolveAttack, refillMana, ACTIONS, canAction, doAction, clearBuff, aiWantShuffle, aiWantBuff, aiWantHeal } from './rules.js';

const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const NF = new Intl.NumberFormat('ko-KR');
const fmt = n => NF.format(n);
const $ = id => document.getElementById(id);
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ===== 전적 저장 (나중에 서버 저장으로 교체 가능하도록 분리) =====
const Stats = {
  KEY: 'vrTcgStats.v1',
  load() { try { return { wins: 0, losses: 0, ...JSON.parse(localStorage.getItem(this.KEY)) }; } catch { return { wins: 0, losses: 0 }; } },
  record(win) { const s = this.load(); win ? s.wins++ : s.losses++; localStorage.setItem(this.KEY, JSON.stringify(s)); return s; },
};

let POOL = [];
let S = null;          // 게임 상태
let selected = null;   // 선택된 공격 유닛 uid
let uidSeq = 1;
const AI_DELAY = () => (window.TCG_FAST ? 0 : 650);

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
  S = { me: newPlayer('나', first !== 'me'), ai: newPlayer('컴퓨터', first !== 'ai'), first, turn: first, turnNo: 0, over: false, busy: false };
  selected = null; $('log').innerHTML = '';
  $('end-screen').classList.add('hidden'); $('start-screen').classList.add('hidden'); $('game').classList.remove('hidden');
  log(first === 'me' ? '🪙 동전 던지기: 내가 선공!' : `🪙 동전 던지기: 컴퓨터가 선공! (나는 후공, 시작 손패 +${RULES.SECOND_PLAYER_BONUS_CARDS})`, 'text-emerald-400');
  $('me-order').textContent = first === 'me' ? '선공' : '후공';
  $('ai-order').textContent = first === 'ai' ? '선공' : '후공';
  startTurn(first);
}

function startTurn(who) {
  const p = S[who];
  S.turn = who; if (who === S.first) S.turnNo++;
  clearBuff(opp(who));                   // 지난 턴 강화 해제
  const bonus = refillMana(p);
  if (bonus) { log(`${p.name}: 처치 보너스 마나 +${bonus}`, 'text-sky-300'); if (who === 'me') floatText(`💧 +${bonus}`, 'text-sky-300'); }
  if (p.deck.length) p.hand.push(p.deck.shift()); else log(`${p.name}: 덱이 비어 드로우를 건너뜁니다.`, 'text-zinc-500');
  p.field.forEach(u => u.canAttack = true);
  render();
  if (who === 'ai') aiTurn();
}

function useAction(who, type) {
  const p = S[who], r = doAction(type, p);
  if (!r.ok) return r;
  const a = ACTIONS[type];
  const detail = type === 'shuffle' ? `손패 ${r.n}장 다시 뽑기` : type === 'heal' ? `영웅 HP +${fmt(r.healed)}` : `필드 ${r.n}장 이번 턴 ATK +${Math.round(RULES.BUFF_RATIO * 100)}%`;
  log(`${p.name}: ${a.icon} ${a.label} (마나 ${a.cost()}) — ${detail}`, 'text-violet-300');
  if (type === 'heal') floatText(`+${fmt(r.healed)}`, 'text-emerald-300', who === 'me' ? 'me' : 'ai');
  if (type === 'buff') floatText(`⚔️ ATK +${Math.round(RULES.BUFF_RATIO * 100)}%`, 'text-violet-300', who);
  render();
  return r;
}

function opp(who) { return who === 'me' ? S.ai : S.me; }

function summon(who, card) {
  const p = S[who], check = canSummon(card, p, opp(who));
  if (!check.ok) return check;
  p.mana -= card.cost;
  p.hand.splice(p.hand.indexOf(card), 1);
  p.field.push(makeUnit(card, uidSeq++));
  log(`${p.name}: ${card.name} 소환 (코스트 ${card.cost})`);
  render();
  return { ok: true };
}

function recall(who, unit) {
  const p = S[who], check = canRecall(unit, p);
  if (!check.ok || !p.field.includes(unit)) return check;
  p.mana -= check.cost;
  p.field = p.field.filter(u => u !== unit);
  p.hand.push(unit.base);               // 원본 카드로 복귀: HP·레벨 초기화
  if (selected === unit.uid) selected = null;
  log(`${p.name}: ${unit.card.name} 회수 (마나 ${check.cost})`, 'text-sky-300');
  render();
  return { ok: true };
}

async function attackAll() {
  if (S.turn !== 'me' || S.over || S.busy) return;
  const ready = S.me.field.filter(u => u.canAttack);
  if (!ready.length) return;
  S.busy = true; selected = null;
  log(`일괄 공격! (${ready.length}장)`, 'text-emerald-400');
  for (const u of ready) {
    if (S.over) break;
    S.busy = false; attack('me', u, null); S.busy = true;
    await sleep(window.TCG_FAST ? 0 : 250);
  }
  S.busy = false; render();
}

function attack(who, unit, target) {
  const o = opp(who), p = S[who];
  if (!unit.canAttack || S.over) return;
  const cls = who === 'me' ? 'text-emerald-300' : 'text-red-300';
  for (const e of resolveAttack(p, o, unit, target)) {
    if (e.type === 'hero') { log(`${unit.card.name} → ${o.name} 영웅 ${fmt(e.dmg)} 피해`, cls); floatText(`-${fmt(e.dmg)}`, 'text-red-400', who === 'me' ? 'ai' : 'me'); }
    else if (e.type === 'hit') log(`${unit.card.name} → ${target.card.name} ${fmt(e.d1)} 피해${e.mult !== 1 ? ` (속성 ×${e.mult})` : ''}, 반격 ${fmt(e.d2)}`, cls);
    else if (e.type === 'destroy') log(`${e.unit.card.name} 파괴!`, 'text-zinc-400');
    else if (e.type === 'refund') log(`${e.killer.card.name} 처치 보상: 다음 턴 마나 +${e.refund}`, 'text-sky-300');
    else if (e.type === 'levelup') { log(`${e.unit.card.name} 레벨 업! Lv${e.level} (ATK +${e.dAtk}, HP +${e.dHp})`, 'text-amber-300'); floatText(`⬆ Lv${e.level}`, 'text-amber-300', S.me.field.includes(e.unit) ? 'me' : 'ai'); }
    else if (e.type === 'overflow') { log(`초과 피해 ${fmt(e.dmg)} → ${o.name} 영웅`, 'text-orange-300'); floatText(`💥 -${fmt(e.dmg)}`, 'text-orange-300', who === 'me' ? 'ai' : 'me'); }
  }
  selected = null;
  render();
  checkEnd();
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

function checkEnd() {
  if (S.over) return true;
  if (S.ai.hp <= 0 || S.me.hp <= 0) {
    S.over = true;
    const win = S.ai.hp <= 0;
    const st = Stats.record(win);
    $('end-title').innerHTML = win ? '<span class="text-emerald-400">승리!</span>' : '<span class="text-red-400">패배...</span>';
    $('end-text').textContent = `${S.turnNo}턴 · 전적 ${st.wins}승 ${st.losses}패`;
    $('end-screen').classList.remove('hidden');
    return true;
  }
  return false;
}

function endTurn() {
  if (S.turn !== 'me' || S.over || S.busy) return;
  selected = null;
  startTurn('ai');
}

// ===== 간단한 AI =====
async function aiTurn() {
  S.busy = true; render();
  await sleep(AI_DELAY());
  const ai = S.ai, me = S.me;
  // 1) 비싼 카드부터 낼 수 있는 만큼 소환
  // 0) 위험한 고코스트 카드 회수
  for (const u of [...ai.field]) if (aiShouldRecall(u, ai, me)) { recall('ai', u); await sleep(AI_DELAY()); }
  if (aiWantShuffle(ai, me)) { useAction('ai', 'shuffle'); await sleep(AI_DELAY()); }
  for (const c of aiSummonOrder(ai.hand)) {
    if (canSummon(c, ai, me).ok) { summon('ai', c); await sleep(AI_DELAY()); }
  }
  if (aiWantBuff(ai)) { useAction('ai', 'buff'); await sleep(AI_DELAY()); }
  // 2) 공격: 유리한 교환(내가 죽이고 살아남음, 또는 더 비싼 카드 처치) 우선, 없으면 영웅 공격
  for (const u of [...ai.field]) {
    if (S.over) break;
    if (!ai.field.includes(u) || !u.canAttack) continue;
    const best = aiPickTarget(u, me.field);
    attack('ai', u, best);
    await sleep(AI_DELAY());
  }
  if (!S.over && aiWantHeal(ai)) { useAction('ai', 'heal'); await sleep(AI_DELAY()); }
  S.busy = false;
  if (!S.over) startTurn('me');
}

// ===== 렌더링 =====
function cardHTML(c, { hp, size = 'md', dim = false } = {}) {
  const e = ELEMENTS[c.class] || ELEMENTS.WIND;
  const small = size === 'sm';
  return `
  <div class="relative ${small ? 'w-[64px] md:w-[96px]' : 'w-[78px] md:w-[110px]'} bg-zinc-900 rounded-xl overflow-hidden ring-2 ${e.ring} ${dim ? 'opacity-50' : ''} shadow-lg">
    <img src="${IMG}${c.id}.jpg" data-id="${c.id}" class="card-img w-full aspect-[3/4] object-cover" alt="${c.name}">
    <div class="absolute top-1 left-1 w-6 h-6 md:w-7 md:h-7 rounded-full bg-sky-600 text-white text-[11px] md:text-xs font-black flex items-center justify-center border border-white/40">${c.cost}</div>
    <div class="absolute top-1 right-1 text-sm md:text-base" title="${e.label}">${e.icon}</div>
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
    img.onerror = () => { img.onerror = null; img.src = `${IMG}${img.dataset.id}.png`; };
  });
}

function renderHero(who) {
  const p = S[who];
  $(`${who}-hp`).textContent = `${fmt(p.hp)} / ${fmt(RULES.HERO_HP)}`;
  $(`${who}-hpbar`).style.width = (p.hp / RULES.HERO_HP * 100) + '%';
  $(`${who}-mana`).textContent = `${p.mana} / ${p.maxMana}`;
  $(`${who}-deck`).textContent = p.deck.length;
  $(`${who}-handcount`).textContent = p.hand.length;
}

function render() {
  if (!S) return;
  renderHero('me'); renderHero('ai');
  const myTurn = S.turn === 'me' && !S.over && !S.busy;
  $('turn-info').textContent = S.over ? '게임 종료' : (S.turn === 'me' ? `내 턴 (${S.turnNo}라운드)` : `상대 턴 (${S.turnNo}라운드)...`);
  $('end-turn').disabled = !myTurn;
  for (const type of Object.keys(ACTIONS)) {
    const c = canAction(type, S.me), btn = $(`act-${type}`);
    btn.disabled = !myTurn || !c.ok;
    btn.querySelector('.reason').textContent = !myTurn ? '' : (c.ok ? '' : c.reason);
  }
  $('attack-all').disabled = !myTurn || !S.me.field.some(u => u.canAttack);
  $('ai-hero').classList.toggle('ring-4', !!selected);
  $('ai-hero').classList.toggle('ring-red-500', !!selected);

  for (const who of ['ai', 'me']) {
    const box = $(`${who}-field`); box.innerHTML = '';
    if (!S[who].field.length) box.innerHTML = '<div class="text-zinc-600 text-xs self-center">빈 필드</div>';
    S[who].field.forEach(u => {
      const w = document.createElement('div');
      const isSel = selected === u.uid;
      const ready = who === 'me' && u.canAttack && myTurn;
      w.className = `unit cursor-pointer transition ${isSel ? '-translate-y-2 drop-shadow-[0_0_10px_#34d399]' : ''} ${ready ? 'ready' : ''} ${selected && who === 'ai' ? 'target' : ''}`;
      w.dataset.uid = u.uid;
      w.innerHTML = `<div class="relative">${cardHTML(u.card, { hp: u.hp, size: 'sm', dim: who === 'me' && !u.canAttack && myTurn })}${u.level > 1 ? `<div class="lv-badge absolute -top-1.5 left-1/2 -translate-x-1/2 px-1.5 rounded-full bg-amber-400 text-black text-[9px] md:text-[10px] font-black">Lv${u.level}</div>` : ''}</div>` +
        (ready ? '<div class="text-center text-[10px] text-emerald-400 font-bold">공격 가능</div>' : '');
      w.onclick = () => onUnitClick(who, u);
      box.appendChild(w);
    });
    fixImages(box);
  }

  const hand = $('me-hand'); hand.innerHTML = '';
  S.me.hand.forEach(c => {
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

function onUnitClick(who, u) {
  const myTurn = S.turn === 'me' && !S.over && !S.busy;
  if (who === 'me') {
    if (myTurn && u.canAttack && selected !== u.uid) { selected = u.uid; render(); return; }
    if (selected === u.uid) { selected = null; render(); }
    showDetail(u.card, { hp: u.hp, unit: u });
  } else {
    if (myTurn && selected) {
      const a = S.me.field.find(x => x.uid === selected);
      if (a) return attack('me', a, u);
    }
    showDetail(u.card, { hp: u.hp });
  }
}

function onHeroClick() {
  if (!selected || S.turn !== 'me' || S.busy) return;
  const a = S.me.field.find(x => x.uid === selected);
  if (a) attack('me', a, null);
}

function showDetail(c, { fromHand = false, hp, unit = null } = {}) {
  const e = ELEMENTS[c.class] || ELEMENTS.WIND;
  const check = fromHand ? canSummon(c, S.me, S.ai) : null;
  const myTurn = S.turn === 'me' && !S.over && !S.busy;
  $('detail-body').innerHTML = `
    <div class="flex gap-4">
      <img src="${IMG}${c.id}.jpg" data-id="${c.id}" class="card-img w-32 md:w-40 aspect-[3/4] object-cover rounded-xl ring-2 ${e.ring}">
      <div class="flex-1 min-w-0">
        <div class="text-2xl font-black">${c.name}</div>
        <div class="text-zinc-400 text-sm">${c.grade} · ${c.region} · ${c.age}세</div>
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
    ${fromHand ? `
      ${check.ok || !myTurn ? '' : `<div id="summon-reason" class="mt-3 text-sm text-red-400">${check.reason}</div>`}
      <button id="summon-btn" ${check.ok && myTurn ? '' : 'disabled'} class="mt-4 w-full py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 disabled:opacity-40 text-black font-bold">소환하기</button>` : ''}
    ${unit ? (() => { const rc = canRecall(unit, S.me); return `
      ${rc.ok || !myTurn ? '' : `<div id="recall-reason" class="mt-3 text-sm text-red-400">${rc.reason}</div>`}
      <button id="recall-btn" ${rc.ok && myTurn ? '' : 'disabled'} class="mt-4 w-full py-3 rounded-2xl bg-sky-500 hover:bg-sky-400 disabled:opacity-40 text-black font-bold">회수 (마나 ${rc.cost})</button>
      <div class="text-[11px] text-zinc-500 mt-1 text-center">손패로 돌아가며 HP가 회복됩니다</div>`; })() : ''}`;
  fixImages($('detail-body'));
  if (unit && $('recall-btn')) $('recall-btn').onclick = () => { const r = recall('me', unit); if (r.ok) hideModal('detail'); };
  if (fromHand) $('summon-btn').onclick = () => { const r = summon('me', c); if (r.ok) hideModal('detail'); };
  showModal('detail');
}

function showModal(id) { $(id).classList.remove('hidden'); $(id).classList.add('flex'); }
function hideModal(id) { $(id).classList.add('hidden'); $(id).classList.remove('flex'); }

function renderStats() {
  const s = Stats.load();
  $('stats').textContent = `전적: ${s.wins}승 ${s.losses}패`;
}

// ===== 초기화 =====
document.querySelectorAll('[data-close]').forEach(b => b.onclick = () => hideModal(b.dataset.close));
$('end-turn').onclick = endTurn;
$('attack-all').onclick = attackAll;
for (const type of Object.keys(ACTIONS)) $(`act-${type}`).onclick = () => { if (S.turn === 'me' && !S.busy && !S.over) useAction('me', type); };
$('ai-hero').onclick = onHeroClick;
$('help-btn').onclick = () => showModal('help');
$('restart-btn').onclick = () => { renderStats(); startGame(); };
$('home-btn').onclick = () => { $('end-screen').classList.add('hidden'); $('game').classList.add('hidden'); $('start-screen').classList.remove('hidden'); renderStats(); };
renderStats();

(async () => {
  try {
    POOL = parseCSV(await (await fetch('data/cards.csv')).text());
    $('start-btn').disabled = false; $('start-btn').textContent = '게임 시작';
    $('start-btn').onclick = startGame;
  } catch (e) { $('start-btn').textContent = '카드 데이터를 불러오지 못했어요'; }
})();

// 테스트/디버그용
window.TCG = { get S() { return S; }, RULES, elementMultiplier, calcDamage, canSummon, buildDeck, summon, attack, recall, attackAll, endTurn, canRecall, recallCost, makeUnit, resolveAttack, useAction, canAction, startGame, get POOL() { return POOL; }, render, Stats };
