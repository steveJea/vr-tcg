// 상태이상(마비·혼란·출혈·도발) 연출 — 걸리는 순간 큰 연출 + 걸려 있는 동안 은은한 지속 연출
// 이미지 에셋(img/effects/{paralyze,confuse,bleed}_{icon,fx}.webp)이 있으면 사용, 없으면 CSS 로 대체
const KIND = { para: 'paralyze', confuse: 'confuse', bleed: 'bleed', taunt: 'taunt' };
const LABEL = { para: '마비!', confuse: '혼란!', bleed: '출혈!', taunt: '도발!' };
const ASSET = {};   // 'paralyze_icon' → url | null(없음) | undefined(확인 중)
const url = n => `img/effects/${n}.webp`;
function probe(n) {
  if (n in ASSET) return ASSET[n];
  ASSET[n] = undefined;
  const im = new Image();
  im.onload = () => { ASSET[n] = url(n); };
  im.onerror = () => { ASSET[n] = null; };
  im.src = url(n);
  return undefined;
}
Object.values(KIND).forEach(k => { probe(k + '_icon'); probe(k + '_fx'); });
export const isStatusFxKind = k => k in KIND;
/** 상태 아이콘 이미지 URL (에셋이 있을 때만) */
export const statusIconUrl = k => (KIND[k] && ASSET[KIND[k] + '_icon']) || null;

let opt = { off: () => false, quick: () => false };
/** off: 연출 완전히 끔(테스트·소탕), quick: 스킵·빨리감기 → 짧고 약하게 */
export function initStatusFx(o) { opt = { ...opt, ...o }; }
const REDUCED = () => !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
const scale = () => (opt.quick() || REDUCED() ? 0.35 : 1);

function layer() {
  let l = document.getElementById('stfx-layer');
  if (!l) { l = document.createElement('div'); l.id = 'stfx-layer'; l.setAttribute('aria-hidden', 'true'); document.body.appendChild(l); }
  return l;
}
function spawn(cls, r, ms, extra) {
  const d = document.createElement('div');
  d.className = cls;
  if (r) { d.style.left = (r.left + r.width / 2) + 'px'; d.style.top = (r.top + r.height / 2) + 'px'; d.style.setProperty('--w', r.width + 'px'); d.style.setProperty('--h', r.height + 'px'); }
  const dur = Math.max(120, Math.round(ms * scale()));
  d.style.setProperty('--d', dur + 'ms');
  if (extra) extra(d);
  layer().appendChild(d);
  setTimeout(() => d.remove(), dur + 60);
  return d;
}
function screen(cls, ms) { if (!opt.quick()) spawn(`stfx-screen ${cls}`, null, ms); }
function sprite(d, name) { const u = ASSET[name]; if (u) { d.classList.add('has-img'); d.style.backgroundImage = `url("${u}")`; } }
function textPop(r, kind) {
  spawn(`stfx-text stfx-text-${kind}`, r, 900, d => { d.textContent = LABEL[kind]; });
}

/** 걸리는 순간 */
export function statusApplyFx(el, kind) {
  if (!el || !KIND[kind] || opt.off() || !el.isConnected) return;
  const r = el.getBoundingClientRect(); if (!r.width) return;
  const fx = KIND[kind] + '_fx';
  if (kind === 'para') {
    spawn('stfx-bolt', r, 520, d => sprite(d, fx));
    screen('stfx-flash-yellow', 260);
  } else if (kind === 'confuse') {
    spawn('stfx-swirl', r, 800, d => sprite(d, fx));
  } else if (kind === 'bleed') {
    spawn('stfx-slash', r, 600, d => sprite(d, fx));
    for (let i = 0; i < 7; i++) spawn('stfx-blood', r, 700, d => { const a = Math.random() * Math.PI * 2, s = 30 + Math.random() * 50; d.style.setProperty('--dx', Math.cos(a) * s + 'px'); d.style.setProperty('--dy', Math.sin(a) * s + 'px'); });
    bleedTickFx(el);
  } else if (kind === 'taunt') {
    spawn('stfx-aura-burst', r, 700, d => sprite(d, fx));
    spawn('stfx-shield-slam', r, 600, d => sprite(d, 'taunt_icon'));
    screen('stfx-edge-red', 450);
  }
  textPop(r, kind);
  el.classList.remove('stfx-pop'); void el.offsetWidth; el.classList.add('stfx-pop');
  setTimeout(() => el.classList.remove('stfx-pop'), Math.round(500 * scale()));
}
/** 출혈 피해 틱: 화면 가장자리 붉은 맥박 + 카드 아래 핏방울 */
export function bleedTickFx(el) {
  if (!el || opt.off() || !el.isConnected) return;
  screen('stfx-edge-red', 700);
  const r = el.getBoundingClientRect(); if (!r.width) return;
  for (let i = 0; i < 3; i++) spawn('stfx-drip', r, 900, d => { d.style.setProperty('--dx', ((i - 1) * r.width * 0.25) + 'px'); d.style.animationDelay = (i * 120 * scale()) + 'ms'; });
}
/** 마비로 행동 불가: 지지직 떨림 */
export function paraSkipFx(el) {
  if (!el || opt.off() || !el.isConnected) return;
  el.classList.remove('stfx-jitter'); void el.offsetWidth; el.classList.add('stfx-jitter');
  setTimeout(() => el.classList.remove('stfx-jitter'), Math.round(600 * scale()));
  const r = el.getBoundingClientRect(); if (r.width) spawn('stfx-spark', r, 400);
}
/** 혼란으로 아군 공격: 화면 소용돌이 */
export function confuseAllyFx(el) {
  if (opt.off()) return;
  screen('stfx-screen-swirl', 600);
  if (el?.isConnected) { const r = el.getBoundingClientRect(); if (r.width) spawn('stfx-swirl small', r, 500, d => sprite(d, 'confuse_fx')); }
}
/** 도발 유닛을 공격할 때: 공격자 → 도발 유닛으로 끌려가는 붉은 선 */
export function tauntPullFx(fromEl, toEl) {
  if (!fromEl || !toEl || opt.off() || !fromEl.isConnected || !toEl.isConnected) return;
  const a = fromEl.getBoundingClientRect(), b = toEl.getBoundingClientRect(); if (!a.width || !b.width) return;
  const x1 = a.left + a.width / 2, y1 = a.top + a.height / 2, x2 = b.left + b.width / 2, y2 = b.top + b.height / 2;
  const len = Math.hypot(x2 - x1, y2 - y1), ang = Math.atan2(y2 - y1, x2 - x1);
  spawn('stfx-pull', null, 450, d => { d.style.left = x1 + 'px'; d.style.top = y1 + 'px'; d.style.width = len + 'px'; d.style.transform = `rotate(${ang}rad)`; });
}
/** 렌더 시 유닛 지속 연출 클래스 */
export function statusClasses(u) {
  const s = u.st || {};
  return `${s.para ? 'st-para' : ''} ${s.confuse ? 'st-confuse' : ''} ${s.bleed ? 'st-bleed' : ''} ${s.taunt ? 'st-taunt' : ''}`;
}
/** 지속 연출용 장식 레이어 HTML (카드 .relative 안에 넣음) */
export function statusDecor(u) {
  const s = u.st || {};
  let h = '';
  if (s.para) h += '<span class="stfx-p-spark"></span><span class="stfx-p-spark b"></span>';
  if (s.confuse) h += '<span class="stfx-stars"><i>★</i><i>✦</i><i>★</i></span>';
  if (s.bleed) h += '<span class="stfx-b-drip"></span><span class="stfx-b-drip b"></span>';
  if (s.taunt) h += `<span class="stfx-t-emblem${ASSET.taunt_icon ? ' has-img' : ''}"${ASSET.taunt_icon ? ` style="background-image:url('${ASSET.taunt_icon}')"` : ''}></span>`;
  return h ? `<div class="stfx-decor" aria-hidden="true">${h}</div>` : '';
}
