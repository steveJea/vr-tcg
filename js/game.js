import { RULES, ELEMENTS, elementMultiplier, calcDamage, canSummon, buildDeck, parseCSV, aiSummonOrder, aiPickTarget } from './rules.js';

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
  p.maxMana = Math.min(RULES.MANA_MAX, p.maxMana + RULES.MANA_PER_TURN);
  p.mana = p.maxMana;
  if (p.deck.length) p.hand.push(p.deck.shift()); else log(`${p.name}: 덱이 비어 드로우를 건너뜁니다.`, 'text-zinc-500');
  p.field.forEach(u => u.canAttack = true);
  render();
  if (who === 'ai') aiTurn();
}

function opp(who) { return who === 'me' ? S.ai : S.me; }

function summon(who, card) {
  const p = S[who], check = canSummon(card, p, opp(who));
  if (!check.ok) return check;
  p.mana -= card.cost;
  p.hand.splice(p.hand.indexOf(card), 1);
  p.field.push({ uid: uidSeq++, card, hp: card.HP, canAttack: false });
  log(`${p.name}: ${card.name} 소환 (코스트 ${card.cost})`);
  render();
  return { ok: true };
}

function attack(who, unit, target) {
  const o = opp(who), p = S[who];
  if (!unit.canAttack || S.over) return;
  unit.canAttack = false;
  if (!target) {
    const dmg = calcDamage(unit.card, null);
    o.hp = Math.max(0, o.hp - dmg);
    log(`${unit.card.name} → ${o.name} 영웅 ${fmt(dmg)} 피해`, who === 'me' ? 'text-emerald-300' : 'text-red-300');
  } else {
    const d1 = calcDamage(unit.card, target.card), d2 = calcDamage(target.card, unit.card);
    const m = elementMultiplier(unit.card.class, target.card.class);
    target.hp -= d1; unit.hp -= d2;
    log(`${unit.card.name} → ${target.card.name} ${fmt(d1)} 피해${m !== 1 ? ` (속성 ×${m})` : ''}, 반격 ${fmt(d2)}`, who === 'me' ? 'text-emerald-300' : 'text-red-300');
    if (target.hp <= 0) { o.field = o.field.filter(u => u !== target); log(`${target.card.name} 파괴!`, 'text-zinc-400'); }
    if (unit.hp <= 0) { p.field = p.field.filter(u => u !== unit); log(`${unit.card.name} 파괴!`, 'text-zinc-400'); }
  }
  selected = null;
  render();
  checkEnd();
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
  for (const c of aiSummonOrder(ai.hand)) {
    if (canSummon(c, ai, me).ok) { summon('ai', c); await sleep(AI_DELAY()); }
  }
  // 2) 공격: 유리한 교환(내가 죽이고 살아남음, 또는 더 비싼 카드 처치) 우선, 없으면 영웅 공격
  for (const u of [...ai.field]) {
    if (S.over) break;
    if (!ai.field.includes(u) || !u.canAttack) continue;
    const best = aiPickTarget(u, me.field);
    attack('ai', u, best);
    await sleep(AI_DELAY());
  }
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
      w.innerHTML = cardHTML(u.card, { hp: u.hp, size: 'sm', dim: who === 'me' && !u.canAttack && myTurn }) +
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
    showDetail(u.card, { hp: u.hp });
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

function showDetail(c, { fromHand = false, hp } = {}) {
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
      <button id="summon-btn" ${check.ok && myTurn ? '' : 'disabled'} class="mt-4 w-full py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 disabled:opacity-40 text-black font-bold">소환하기</button>` : ''}`;
  fixImages($('detail-body'));
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
window.TCG = { get S() { return S; }, RULES, elementMultiplier, calcDamage, canSummon, buildDeck, summon, attack, endTurn, startGame, get POOL() { return POOL; }, render, Stats };
