// ===== 튜토리얼 가이드 (data/tutorials/<id>.json · 설명: data/tutorials/README.md) =====
// 화면을 어둡게 하고 대상 하나만 밝게(스포트라이트) + 말풍선. 대상만 누를 수 있음(정보 단계는 아무 데나 탭).
// 게임(js/game.js)이 TUT.emit('card_selected' | 'attack_done' | 'skill_used' | 'battle_end' | 'turn_start') 로 알려 주면 다음 단계로.
// 단계 옵션: silent(가리지 않고 이벤트만 대기) · unlock:[잠금들](이 단계에서 해제) · 이벤트 추가: summoned · swapped · awaken
// 잠금(locks): auto · speed(2배속) · skip(연출 생략) · attack_all(일괄 공격) · end_turn · giveup — 진행 중에만 적용.
const LOCKS = ['auto', 'speed', 'skip', 'attack_all', 'end_turn', 'giveup'];
const LOCK_SEL = { auto: '#auto-btn', speed: '#spd-btn', skip: '#fx-skip', attack_all: '#attack-all', end_turn: '#end-turn', giveup: '#story-giveup' };
const key = id => `vrTut:${window.VRCloud?.user?.id || 'guest'}:${id}`;
let T = null;
// face: 'card:<카드id>' → 카드 그림 (없으면 img/cards/<id>.webp) · 그 밖엔 이미지 경로 그대로
const faceSrc = f => { const m = /^card:(\d+)$/.exec(f); return m ? `https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/${m[1]}.webp` : f; };   // { id, def, i, locks:Set, el:{ov,ring,bub}, raf, cb }

/** 의미 대상 → DOM 요소. 'my_card:0' 'enemy_card:0' 'skill_btn[:n]' 'skill_use' 'attack_all' 'end_turn' 'auto_btn' 'speed_btn' 또는 CSS 선택자 */
function resolve(t) {
  if (!t) return null;
  const [k, n0] = String(t).split(':'), n = +(n0 || 0);
  const cards = side => [...document.querySelectorAll(`#${side}-field [data-uid], #${side}-boss [data-uid]`)].filter(e => e.offsetParent);
  switch (k) {
    case 'my_card': return cards('me')[n] || null;
    case 'enemy_card': return cards('ai')[n] || null;
    case 'skill_btn': return cards('me')[n]?.querySelector('.skill-btn') || null;
    case 'skill_use': return document.querySelector('#detail:not(.hidden) [data-skill]:not([disabled])');
    case 'reserve_btn': return document.getElementById('reserve-btn');
    case 'attack_all': return document.getElementById('attack-all');
    case 'end_turn': return document.getElementById('end-turn');
    case 'auto_btn': return document.getElementById('auto-btn');
    case 'speed_btn': return document.getElementById('spd-btn');
    default: try { return document.querySelector(t); } catch { return null; }
  }
}

function build() {
  const ov = document.createElement('div'); ov.className = 'tut-ov';
  ov.innerHTML = '<div class="tut-ring"></div><div class="tut-hand"></div><div class="tut-bub"><img class="tut-face" alt=""><div class="tut-txt"><b class="tut-who"></b><p></p><small class="tut-tap">탭하여 계속</small></div></div><button class="tut-skip" type="button">건너뛰기</button>';
  document.body.appendChild(ov);
  ov.querySelector('.tut-skip').onclick = e => { e.stopPropagation(); finish(true); };
  return { ov, ring: ov.querySelector('.tut-ring'), hand: ov.querySelector('.tut-hand'), bub: ov.querySelector('.tut-bub') };
}

function place() {
  if (!T) return;
  const st = T.def.steps[T.i], { ring, bub, hand, ov } = T.el;
  const tgt = st && resolve(st.target);
  ov.classList.toggle('dim', !!st);
  if (tgt) {
    const r = tgt.getBoundingClientRect(), pad = st.pad ?? 6;
    Object.assign(ring.style, { display: 'block', left: `${r.left - pad}px`, top: `${r.top - pad}px`, width: `${r.width + pad * 2}px`, height: `${r.height + pad * 2}px` });
    hand.style.display = 'block'; hand.style.left = `${r.left + r.width / 2}px`; hand.style.top = `${r.top + r.height * 0.6}px`;
    const below = r.top + r.height / 2 < innerHeight / 2;   // 대상이 위쪽이면 말풍선은 아래
    bub.style.top = below ? `${Math.min(innerHeight - 150, r.bottom + 18)}px` : ''; bub.style.bottom = below ? '' : `${Math.min(innerHeight - 150, innerHeight - r.top + 18)}px`;
  } else {
    ring.style.display = 'none'; hand.style.display = 'none';
    Object.assign(ring.style, { left: '50%', top: '50%', width: '0px', height: '0px' });
    bub.style.top = ''; bub.style.bottom = '22%';
  }
  T.raf = requestAnimationFrame(place);
}

function show() {
  const st = T.def.steps[T.i]; if (!st) return finish(false);
  const { bub, ov } = T.el;
  if (st.unlock) { for (const k of st.unlock) T.locks.delete(k); applyLocks(true); }   // unlock: 이 단계부터 잠금 해제 (예: 각성 난입 → AUTO·2배속)
  ov.style.display = st.silent ? 'none' : '';   // silent: 화면을 가리지 않고 이벤트만 기다림 (예: 적 턴 → turn_start, 각성 → awaken)
  bub.querySelector('p').textContent = st.text || '';
  bub.querySelector('.tut-who').textContent = st.speaker || '';
  const face = bub.querySelector('.tut-face'); face.style.display = st.face ? '' : 'none'; if (st.face) face.src = faceSrc(st.face);
  bub.querySelector('.tut-tap').style.display = !st.wait || st.wait === 'tap' ? '' : 'none';
  ov.classList.toggle('info', !st.wait || st.wait === 'tap');
  bub.classList.remove('pop'); void bub.offsetWidth; bub.classList.add('pop');
  T.waitTarget = 0;   // 대상이 아직 없으면(다음 렌더 대기) place 가 계속 찾음
}

function next() { if (!T) return; T.i++; if (T.i >= T.def.steps.length) finish(false); else show(); }

/** 정보 단계 탭 · 대상 아닌 곳 탭 막기 (capture 단계) */
function guard(e) {
  if (!T) return;
  const st = T.def.steps[T.i]; if (!st || st.silent) return;
  if (e.target.closest?.('.tut-skip')) return;
  const info = !st.wait || st.wait === 'tap';
  const hard = e.type === 'click';   // pointerdown 등은 전파만 막음 (preventDefault 하면 모바일에서 click 이 사라짐)
  if (info) { e.stopPropagation(); if (hard) { e.preventDefault(); next(); } return; }
  const tgt = resolve(st.target);
  // 상세 창(스킬 사용)은 대상이 그 안에 있으면 그 창 안 탭은 허용
  if (tgt && tgt.contains(e.target)) { if (e.type === 'click' && st.wait === 'tap_target') setTimeout(next, 0); return; }
  if (!tgt && !st.target) return;   // 대상 없는 행동 대기: 막지 않음
  e.stopPropagation(); if (hard) e.preventDefault();
}

function applyLocks(on) {
  for (const k of LOCKS) document.body.classList.toggle(`tut-lock-${k}`, !!(on && T?.locks.has(k)));
}

function finish(skipped) {
  if (!T) return;
  const t = T; T = null;
  cancelAnimationFrame(t.raf); t.el.ov.remove(); applyLocks(false);
  for (const ev of ['click', 'pointerdown', 'pointerup', 'mousedown']) document.removeEventListener(ev, guard, true);
  try { localStorage.setItem(key(t.id), skipped ? 'skip' : 'done'); } catch {}
  t.cb?.(skipped);
}

/** 시작. opt.force: 이미 본 것도 다시 · opt.onDone(skipped) */
async function start(id, opt = {}) {
  if (!id || T) return false;
  if (!opt.force && done(id)) return false;
  let def = opt.def;
  if (!def) { try { const r = await fetch(`data/tutorials/${id}.json`, { cache: 'no-cache' }); if (!r.ok) return false; def = await r.json(); } catch { return false; } }
  if (!Array.isArray(def.steps) || !def.steps.length) return false;
  // 내 차례·연출 끝날 때까지 기다렸다가 시작 (최대 20초)
  for (let k = 0; k < 100 && window.TCG?.S && (window.TCG.S.turn !== 'me' || window.TCG.S.busy) && !window.TCG.S.over; k++) await new Promise(r => setTimeout(r, 200));
  if (T) return false;
  const S = window.TCG?.S;
  if (def.prep?.fullMp && S?.me) { for (const u of S.me.field) u.mp = u.maxMp; window.TCG.render?.(); }   // 연습용: 첫 턴부터 기술 사용 가능
  T = { id, def, i: 0, locks: new Set(def.locks || []), el: build(), cb: opt.onDone };
  applyLocks(true);
  for (const ev of ['click', 'pointerdown', 'pointerup', 'mousedown']) document.addEventListener(ev, guard, true);
  if (def.noSkip) T.el.ov.querySelector('.tut-skip').style.display = 'none';   // noSkip: 건너뛰기 없음 (강제 영입)
  show(); place();
  return true;
}

/** 게임 → 튜토리얼: 기다리던 이벤트면 다음 단계 */
function emit(ev, detail = {}) {
  if (!T) return;
  const st = T.def.steps[T.i];
  if (ev === 'battle_end' && st?.wait !== 'battle_end') return finish(false);   // 가이드 도중 전투가 끝나면 조용히 마침
  if (!st || st.wait !== ev) return;
  if (st.match && Object.entries(st.match).some(([k, v]) => detail[k] !== v)) return;
  setTimeout(next, st.delay ?? 350);
}

const locked = k => !!T?.locks.has(k);
const done = id => { try { return !!localStorage.getItem(key(id)); } catch { return false; } };
/** 개발용 초기화: reset('ch0_battle1') 또는 reset() = 전부 */
function reset(id) {
  try { for (const k of Object.keys(localStorage)) if (k.startsWith('vrTut:') && (!id || k.endsWith(`:${id}`))) localStorage.removeItem(k); } catch {}
}
/** 개발용 데모: 스토리와 같은 전투 화면에 튜토리얼 붙여 시작 (라이브 스토리와 무관) — ?tut=<id> 또는 VRTutorial.demo(id) */
async function demo(id = 'ch0_battle1') {
  const r = await fetch(`data/tutorials/${id}.json`, { cache: 'no-cache' }).catch(() => null); const def = r?.ok ? await r.json() : null; if (!def?.demo) return false;
  const tryStart = () => {
    if (!window.TCG?.ready) return setTimeout(tryStart, 200);
    document.getElementById('intro')?.remove();
    window.TCG.startStory({ me: def.demo.me.map(id => window.TCG.cardById(id)).filter(Boolean), ai: def.demo.ai.map(id => window.TCG.cardById(id)).filter(Boolean), win: 'wipe', first: 'me', aiName: def.demo.aiName || '연습 상대', tutorial: id, tutorialForce: true, onEnd: () => {} });
  };
  tryStart(); return true;
}

window.VRTutorial = { start, emit, locked, done, reset, demo, get active() { return T ? { id: T.id, step: T.i, wait: T.def.steps[T.i]?.wait } : null; } };
try { const q = new URLSearchParams(location.search); if (q.get('tut_reset') != null) reset(q.get('tut_reset') || undefined); if (q.get('tut')) demo(q.get('tut')); } catch {}
