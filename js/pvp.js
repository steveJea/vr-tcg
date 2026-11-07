// ===== 비동기 PvP 화면 =====
// 서버: security_phase3_pvp.sql + pvp-verify-v3 (공식 승패·보상은 서버 엔진 재생만). 화면: js/pvp-core.js
// 리그: 무제한(open) · HR 이하(hr, 코스트 150) / 모드: 1v1 · 3v3(3덱 2선승) / 하루 10회 · 주간 시즌(월 00:00 KST)
import { LEAGUES, MODES, snapCard, deckCheck, runSeries, manualMatch, roundSeed, GUARD_GRADES, BOSS_MEMBERS } from './pvp-core.js';
const VIEW = () => window.TCG?.viewBattle;   // 스토리·탑과 같은 전투 화면 (js/game.js)
import { PVP_ENGINE_VERSION } from './pvp-engine-version.js';
import { modeToggle, bindMode, battleMode, playManual } from './manual-ui.js';
const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);
const GS = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR', 'LEGENDARY RARE': 'LR' };
const LS = 'vrTcgPvp.view';
let view = (() => { try { return { league: 'open', mode: '1v1', ...JSON.parse(localStorage.getItem(LS) || '{}') }; } catch { return { league: 'open', mode: '1v1' }; } })();
let st = null, top = null, owned = [], myDecks = [];
const card = id => window.TCG?.cardById?.(id);
async function rpc(name, args) {
  if (window.__PVP_MOCK) return window.__PVP_MOCK(name, args);
  const sb = window.VRCloud?.sb; if (!sb) throw new Error('offline');
  const { data, error } = await sb.rpc(name, args); if (error) throw new Error(error.message); return data;
}
// Ranked results only cross the authenticated verifier. No client win/loss RPC.
async function verifyRpc(body) {
  if (window.__PVP_MOCK) return window.__PVP_MOCK('pvp-verify-v3', body);
  const sb = window.VRCloud?.sb; if (!sb) throw new Error('offline');
  let last;
  for (let i = 0; i < 2; i++) {
    try {
      const { data, error } = await sb.functions.invoke('pvp-verify-v3', { body });
      if (error) { let detail; try { detail = await error.context?.json(); } catch {} throw new Error(detail?.error || error.message); }
      if (!data?.ok && body.op !== 'start') throw new Error(data?.error || 'server settlement failed');
      return data;
    } catch (e) { last = e; }
  }
  throw last;
}
async function finishVerified(body) {
  try { return await verifyRpc(body); }
  catch (e) {
    // Another tab/expiry may have closed this session, or a response was lost.
    // Re-read the server receipt; never reinterpret the local outcome.
    try { const s = await verifyRpc({ op: 'status', id: body.id }); if (s.status === 'settled' && s.result) return s.result; } catch {}
    throw e;
  }
}
const pendingKey = () => 'vrTcgPvp.pendingV3:' + (window.VRCloud?.user?.id || 'mock');
function pendingStore(key, value) {
  try {
    if (value === undefined) return JSON.parse(localStorage.getItem(key) || 'null');
    if (value === null) localStorage.removeItem(key); else localStorage.setItem(key, JSON.stringify(value));
  } catch {} return value;
}
const pendingResult = value => pendingStore(pendingKey(), value);
function pendingStart(value) {
  const key = pendingKey() + ':start';
  const cached = pendingStore(key, value);
  if (cached && cached.version !== PVP_ENGINE_VERSION) { pendingStore(key, null); return null; }
  return cached;
}
async function retryResult() {
  const p = pendingResult(); if (!p) return;
  try { const rep = await finishVerified(p.body); pendingResult(null); showResult(p.session, rep); }
  catch (e) { toast('결과 미정산 · ' + errText(e)); }
}
const ERR = { 'PvP verifier unavailable': 'PvP 검증 서버 준비 중', 'rate limited': '잠시 후 다시 도전해 주세요', 'server settlement failed': '서버 정산 실패 · 다시 저장해 주세요', 'reward verification pending': '지급 보류', 'guard grade': '리더(수비대장)는 HR 이하', 'boss members': '멤버 1장 이상', 'no attempts left': '오늘 횟수 끝', 'not enough gem': '🔮 부족', 'deck required': '덱 필요', 'card not owned': '없는 인재', 'duplicate card': '중복', 'grade not allowed': 'HR 이하만', 'cost over 150': '코스트 150 초과', 'card used in another deck': '다른 덱에 있음', 'login required': '로그인 필요' };
const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 40); };
function toast(t) { const el = document.createElement('div'); el.className = 'pvp-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 1800); }

// ---- 공통 창 (바깥 누르면 닫힘) ----
// 페이지 시스템: PvP 로비 = 페이지 'pvp', 덱 편집·랭킹·시즌 보상 = 하위 페이지. 카드·상대 정보·확인·결과·재생은 작은 창 그대로
const PAGES = { 'pvp-modal': ['pvp', '⚔️ PvP'], 'pvp-edit': ['pvp-edit', '🛡️ PvP 덱'], 'pvp-ranking': ['pvp-ranking', '🏅 랭킹'], 'pvp-tiers': ['pvp-tiers', '🏆 시즌 보상'] };
let editBack = null;   // 덱 편집(보스리그) 단계 뒤로: 확인 → 멤버 → 리더
const inPvp = () => /^pvp/.test(window.VRPages?.current || '');
function modal(id, html, cls = '') {
  const old = $(id);
  if (id === 'pvp-modal' && old?.classList.contains('vr-in-page') && window.VRPages?.current === 'pvp') {   // 로비 새로 그리기 = 같은 페이지 재사용 (기록·전환 그대로)
    old.className = `pvp-modal vr-in-page ${cls}`; old.innerHTML = `<div class="pvp-panel" role="dialog">${html}</div>`; return old; }
  old?.remove();
  const m = document.createElement('div'); m.id = id; m.className = `pvp-modal ${cls}`;
  m.innerHTML = `<div class="pvp-panel" role="dialog">${html}</div>`;
  m.addEventListener('click', e => { if ((e.target === m && !m.classList.contains('vr-in-page')) || e.target.closest('[data-x]')) m.remove(); });
  document.body.appendChild(m);
  const pg = PAGES[id]; if (pg && window.VRPages && (id === 'pvp-modal' || inPvp())) window.VRPages.host(pg[0], pg[1], m, null, null, id === 'pvp-edit' ? () => !!editBack?.() : null);   // 실패하면 예전 팝업
  return m;
}
const thumb = (c, extra = '') => c ? `<div class="pvp-th g-${GS[c.grade] || 'N'}" title="${esc(c.name)}"><img src="${cardThumb(c.id)}" alt="${esc(c.name)}" loading="lazy" onerror="this.style.visibility='hidden'"><i>${c.level ? 'Lv' + c.level : GS[c.grade] || ''}</i>${window.VRStory?.skBadge?.(c.id, 'sm') || ''}${extra}</div>` : '';   // ✦ 기술 배지 (탭하면 기술 보기)
const snapThumbs = list => (list || []).map(o => { const c = card(o.id); return thumb(c && { ...c, level: o.level }); }).join('');
// ---- 티어 (서버 pvp_tier_table 과 같은 경계) · 엠블럼은 그림순이 그림 전까지 CSS+이모지 (img/ui/tier/<key>.webp 가 생기면 자동 사용) ----
export const TIERS = [
  { k: 'bronze', label: '브론즈', min: 0, ic: '🥉' }, { k: 'silver', label: '실버', min: 950, ic: '🥈' }, { k: 'gold', label: '골드', min: 1050, ic: '🥇' },
  { k: 'platinum', label: '플래티넘', min: 1150, ic: '💠' }, { k: 'diamond', label: '다이아', min: 1250, ic: '💎' }, { k: 'abyss', label: '심연', min: 1400, ic: '🌌' }];
export const tierOf = r => [...TIERS].reverse().find(t => (r ?? 1000) >= t.min) || TIERS[0];
const tierBy = k => TIERS.find(t => t.k === k) || null;
const emb = (t, cls = '') => `<span class="pvp-emb t-${t.k} ${cls}" title="${t.label}"><i>${t.ic}</i><img src="img/ui/tier/${t.k}.webp" alt="" onerror="this.remove()"></span>`;
const CUR = { gold: '🪙', soul: '🔥', shard: '💠', blood: '🩸', tickets: '🎟️', gem: '🔮' };
const rwHtml = rw => Object.entries(rw || {}).filter(([k]) => CUR[k]).map(([k, v]) => `<span>${CUR[k]}${v}</span>`).join('') + (rw?.title === 'abyss' ? '<span class="pvp-ttl">🌌 칭호</span>' : '');
const fxOff = () => localStorage.getItem('vrTcgSkipFx') === '1' || !!window.TCG_FAST;
const dleft = () => { const e = st?.season_end ? new Date(st.season_end) : null; if (!e) return ''; const d = Math.max(0, Math.ceil((e - Date.now()) / 864e5)); return `D-${d}`; };

// ---- 메인 ----
export async function open() {
  if (!window.VRCloud?.user && !window.__PVP_MOCK) return modal('pvp-modal', `<button class="pvp-x" data-x>✕</button><div class="pvp-h">⚔️ PvP</div><div class="pvp-empty">🔒 로그인</div>`);
  const again = $('pvp-modal')?.classList.contains('vr-in-page') && window.VRPages?.current === 'pvp';
  const m = modal('pvp-modal', `<div class="pvp-empty">…</div>`); if (!again) window.VRSound?.scope?.(m, window.VR_BGM?.pvpLobby);
  try {
    const S = window.VRStory; const s = S?.summary ? await S.summary() : null;
    owned = s?.ok ? s.owned : []; myDecks = s?.ok ? (s.decks || []).filter(d => d.uids.length) : [];
    [st, top] = await Promise.all([rpc('pvp_status', { p_league: view.league, p_mode: view.mode }), rpc('pvp_rankings', { p_league: view.league, p_mode: view.mode, p_season: null }).catch(() => null)]);
  } catch (e) { m.querySelector('.pvp-panel').innerHTML = `<button class="pvp-x" data-x>✕</button><div class="pvp-empty">${esc(errText(e))}</div>`; return; }
  paint();
}
function paint() {
  const m = $('pvp-modal'); if (!m) return;
  const n = MODES[view.mode].decks, decks = Array.from({ length: n }, (_, i) => st.decks.find(d => d.slot === i));
  const ready = !st.reward_held && ((decks.every(Boolean) && st.left > 0) || !!pendingStart());
  const byUid = new Map(owned.map(o => [o.uid, o]));
  m.querySelector('.pvp-panel').innerHTML = `
    <button class="pvp-x" data-x aria-label="닫기">✕</button>
    <div class="pvp-h">⚔️ PvP <small>${dleft()}</small></div>
    ${st.ladder === 'verified-v3' ? `<div class="pvp-empty">서버 검증 래더${st.legacy_rating != null ? ` · 이전 기록 ${st.legacy_rating} 보존` : ''}</div>` : ''}
    ${pendingResult() ? '<div class="pvp-acts"><button class="pvp-go" data-retry-result>결과 다시 저장</button></div>' : ''}
    <div class="pvp-tabs">${Object.entries(LEAGUES).map(([k, L]) => `<button data-league="${k}" class="${view.league === k ? 'on' : ''}">${L.label}</button>`).join('')}
      <span class="pvp-sep"></span>${Object.keys(MODES).map(k => `<button data-mode="${k}" class="${view.mode === k ? 'on' : ''}">${MODES[k].label ? `👑 ${MODES[k].label}` : k}</button>`).join('')}</div>
    ${myRank()}
    <div class="pvp-decks">${decks.map((d, i) => `<button class="pvp-deck ${d ? '' : 'empty'}" data-edit="${i}">
      <span class="pvp-deck-no">${n > 1 ? i + 1 : '🛡'}</span><span class="pvp-deck-row">${d ? d.uids.map(u => thumb(byUid.get(u) && { ...card(byUid.get(u).id), level: byUid.get(u).level })).join('') : '<span class="pvp-plus">＋</span>'}</span>
      ${view.league === 'hr' && d ? `<small class="pvp-cost">${d.cost}/150</small>` : ''}</button>`).join('')}</div>
    <div class="pvp-bmode">${modeToggle()}</div>
    <div class="pvp-acts"><button class="pvp-rank" data-rank title="랭킹">🏅</button><button class="pvp-rank" data-shop title="PvP 상점">🛒</button>${st.left <= 0 && window.VRGem?.item?.('pvp_try') ? `<button class="pvp-gemtry" data-gemtry ${window.VRGem.item('pvp_try').left === 0 ? 'disabled' : ''} title="추가 도전 (하루 3회)">🎫+1 <small>🔮${window.VRGem.item('pvp_try').price}</small></button>` : ''}<button class="pvp-go" data-go ${ready ? '' : 'disabled'}>${pendingStart() ? '매칭 다시 확인' : '⚔️ 매칭'}</button></div>
    <div class="pvp-top"><div class="pvp-top-h">🏅 TOP 10</div><div class="pvp-rk">${rkRows(top)}</div></div>`;
  m.querySelectorAll('[data-league]').forEach(b => b.onclick = () => { view.league = b.dataset.league; save(); open(); });
  m.querySelectorAll('[data-mode]').forEach(b => b.onclick = () => { view.mode = b.dataset.mode; save(); open(); });
  m.querySelectorAll('[data-edit]').forEach(b => b.onclick = () => editDeck(+b.dataset.edit));
  m.querySelector('[data-rank]').onclick = rankings; bindWho(m);
  m.querySelector('[data-shop]').onclick = () => window.VRGear?.pvpShop?.();   // 장비 PR7
  m.querySelector('[data-tiers]').onclick = tierTable;
  if (st.pending || st.pending_rank) claimTier();
  const retry = m.querySelector('[data-retry-result]'); if (retry) retry.onclick = retryResult;
  m.querySelector('[data-go]').onclick = fight; bindMode(m);
  const gt = m.querySelector('[data-gemtry]'); if (gt) gt.onclick = async () => { gt.disabled = true; if (await window.VRGem.buy('pvp_try', view.league, view.mode)) open(); else gt.disabled = false; };
  if (st.left <= 0 && window.VRGem && !window.VRGem.now) window.VRGem.status().then(g => { if (g && $('pvp-modal')) paint(); });
}
const save = () => localStorage.setItem(LS, JSON.stringify(view));
/** 내 랭크 카드: 엠블럼 · 레이팅 · 다음 티어까지 바 · 승패 · D-day · 연승 */
function myRank() {
  const t = tierOf(st.rating), i = TIERS.indexOf(t), nx = TIERS[i + 1];
  const pct = nx ? Math.max(0, Math.min(100, (st.rating - t.min) / (nx.min - t.min) * 100)) : 100;
  return `<button class="pvp-me t-${t.k} ${st.abyss ? 'has-abyss' : ''}" data-tiers aria-label="티어 보상">
    ${emb(t, 'big')}
    <span class="pvp-me-main"><span class="pvp-me-top"><b class="pvp-me-tier">${t.label}</b><b class="pvp-me-rt">${st.rating}</b>${st.streak >= 2 ? `<span class="pvp-streak">🔥${st.streak}</span>` : ''}</span>
      <span class="pvp-bar"><i style="width:${pct.toFixed(1)}%"></i></span>
      <span class="pvp-me-sub"><span>${st.wins}W ${st.losses}L</span><span>🛡${st.def_wins}/${st.def_losses}</span><span>🎫${st.left}/${st.max}</span><span>${nx ? `${nx.ic} ${nx.min - st.rating}` : 'MAX'}</span><span class="pvp-dd">${dleft()}</span></span></span></button>`;
}
/** 티어·연승 보상표 (바깥 누르면 닫힘) */
function tierTable() {
  const cur = tierOf(st.rating).k, tiers = st.tiers || TIERS.map(t => ({ tier: t.k, min: t.min, reward: {} }));
  modal('pvp-tiers', `<button class="pvp-x" data-x>✕</button><div class="pvp-h">🏆 시즌 보상 <small>${dleft()}</small></div>
    <div class="pvp-tt">${[...tiers].reverse().map(x => { const t = tierBy(x.tier) || TIERS[0]; return `<div class="pvp-tt-row t-${t.k} ${t.k === cur ? 'on' : ''}">${emb(t)}<b>${t.label}</b><small>${x.min}+</small><span class="pvp-rw">${rwHtml(x.reward)}</span></div>`; }).join('')}</div>
    <div class="pvp-empty">이번 시즌 검증 완료 ${st.games_verified || 0}경기 · 티어 보상 3경기 / 순위 보상 1경기 이상<br>포기·미완료는 보상 참여 횟수에서 제외돼요.</div>
    <div class="pvp-h pvp-h2">🔥 연승</div>
    <div class="pvp-tt">${(st.streaks || []).map(x => `<div class="pvp-tt-row ${st.streak >= x.n ? 'got' : ''}"><span class="pvp-streak">🔥${x.n}</span><span class="pvp-rw">${rwHtml(x.reward)}</span></div>`).join('')}</div>`, 'pvp-sub');
}
/** 지난 시즌 티어 보상 자동 수령 (서버가 1회만 지급) */
async function claimTier() {
  const tier = st.pending, rank = st.pending_rank; st.pending = null; st.pending_rank = null;
  const rewards = [];
  for (const [name, args] of [
    ...(tier ? [['pvp_claim_tier', { p_league: view.league, p_mode: view.mode }]] : []),
    ...(rank ? [['pvp_claim_reward', { p_league: view.league, p_mode: view.mode, p_season: rank.season }]] : [])
  ]) {
    try { rewards.push(await rpc(name, args)); } catch (e) { toast(errText(e)); }
  }
  if (!rewards.length) return;
  window.VRPlayer?.wallet?.(true);
  modal('pvp-claim', rewards.map(r => `<div class="pvp-claim"><div class="pvp-claim-t">${r.tier ? (tierBy(r.tier) || TIERS[0]).label : `🏅 ${r.rank}위`}</div><small>지난 시즌</small><div class="pvp-rw big">${rwHtml(r.reward)}</div></div>`).join('') +
    '<div class="pvp-acts"><button class="pvp-go" data-x>확인</button></div>', 'pvp-sub');
}
/** VS 연출 (~1.5초 · 탭하면 넘김 · 연출 끄기면 생략) */
function vsScreen(s) {
  if (fxOff()) return Promise.resolve();
  const lead = d => d?.[0]?.[0]?.id, me = lead(s.me), op = lead(s.opp), ot = tierOf(s.opp_rating), mt = tierOf(s.rating);
  return new Promise(done => {
    const el = document.createElement('div'); el.className = 'pvp-vsx'; el.setAttribute('role', 'button'); el.setAttribute('aria-label', '탭하여 넘기기');
    el.innerHTML = `<div class="pvp-vsx-side me">${me ? `<img src="${IMG}${me}.webp" alt="">` : ''}<div class="pvp-vsx-tag">${emb(mt)}<b>${esc((document.querySelector('.acct-name')?.textContent || '나').replace(/님$/, ''))}</b><small>${s.rating ?? ''}</small></div></div>
      <div class="pvp-vsx-side op">${op ? `<img src="${IMG}${op}.webp" alt="">` : ''}<div class="pvp-vsx-tag">${emb(ot)}<b>${esc(s.opp_name)}${s.bot ? ' 🤖' : ''}</b><small>${s.opp_rating ?? ''}</small></div></div>
      <div class="pvp-vsx-vs">VS</div>`;
    let t = 0; const end = () => { clearTimeout(t); el.classList.add('out'); setTimeout(() => { el.remove(); done(); }, 180); };
    el.addEventListener('click', end, { once: true }); document.body.appendChild(el); t = setTimeout(end, 1500);
  });
}

// ---- 덱 편집 (PvP 전용 · 마이 덱에서 불러오기) ----
// 인재 정렬 (스토리·거래소와 같은 칩: 같은 버튼 다시 누르면 ▼▲ 전환, localStorage 기억)
const PSORTS = { grade: '등급', level: '레벨', power: '전투력', cost: '코스트', name: '이름', new: '획득' }, PSORT_KEY = 'vr-pvp-card-sort';
const GRADE_ORD = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE'];
let psort = (() => { try { const v = JSON.parse(localStorage.getItem(PSORT_KEY)); if (v && PSORTS[v.k]) return { k: v.k, desc: v.desc !== false }; } catch {} return { k: 'power', desc: true }; })();
const setPSort = k => { psort = psort.k === k ? { k, desc: !psort.desc } : { k, desc: true }; try { localStorage.setItem(PSORT_KEY, JSON.stringify(psort)); } catch {} };
export function sortPool(list, cardOf = card, all = owned, s = psort) {
  const idx = new Map(all.map((o, i) => [o.uid, i])), gr = o => GRADE_ORD.indexOf(cardOf(o.id)?.grade), lv = o => o.level | 0, pw = o => +o.power || 0, ct = o => +cardOf(o.id)?.cost || 0, nw = o => idx.get(o.uid) ?? -1;
  const nm = o => cardOf(o.id)?.name || '', d = s.desc ? -1 : 1;
  const key = { grade: [gr, lv, pw], level: [lv, gr, pw], power: [pw, gr, lv], cost: [ct, pw, lv], new: [nw], name: [] }[s.k] || [pw];
  return list.slice().sort((a, b) => { if (s.k === 'name') { const v = nm(a).localeCompare(nm(b), 'ko'); if (v) return v * d; } for (const f of key) { const v = f(a) - f(b); if (v) return v * d; } return 0; });
}
export function filterPool(list, query = '', maxCost = '', cardOf = card) {
  const name = query.trim().normalize('NFKC').toLocaleLowerCase('ko');
  const cap = maxCost === '' ? Infinity : Number(maxCost);
  return list.filter(o => { const c = cardOf(o.id); return c && (+c.cost || 0) <= cap && (!name || (c.name || '').normalize('NFKC').toLocaleLowerCase('ko').includes(name)); });
}
const sortChips = () => `<div class="pvp-chips pvp-sort">${Object.entries(PSORTS).map(([k, l]) => `<button data-srt="${k}" class="${psort.k === k ? 'on' : ''}" aria-pressed="${psort.k === k}">${l}${psort.k === k ? (psort.desc ? ' ▼' : ' ▲') : ''}</button>`).join('')}</div>`;
function editDeck(slot, keep) {
  const cur = st.decks.find(d => d.slot === slot);
  let sel = keep ? keep.sel.filter(u => owned.some(o => o.uid === u)) : cur ? [...cur.uids] : [];
  if (keep && sel.length < keep.sel.length) toast('합성 등으로 빠진 인재가 있어요');
  const L = LEAGUES[view.league];
  let query = keep?.query || '', maxCost = keep?.maxCost ?? '';
  const usedElsewhere = new Set(st.decks.filter(d => d.slot !== slot).flatMap(d => d.uids.map(u => owned.find(o => o.uid === u)?.id)));
  const pool = [...new Map(owned.filter(o => !L.grades || L.grades.includes(card(o.id)?.grade)).sort((a, b) => b.power - a.power).map(o => [o.id, o])).values()];   // 같은 카드는 가장 센 1장
  const m = modal('pvp-edit', '', 'pvp-sub');
  // 보스리그: ① 리더(수비대장 1장 · HR 이하) → ② 멤버(1~5장) → ③ 확인 (sel[0] = 리더)
  const BOSS = !!MODES[view.mode].boss, gradeOf = u => card(owned.find(o => o.uid === u)?.id)?.grade;
  const isGuard = u => GUARD_GRADES.includes(gradeOf(u));
  let step = BOSS ? (keep?.step && (keep.step === 'leader' || (sel.length && isGuard(sel[0]))) ? keep.step : sel.length && isGuard(sel[0]) ? (sel.length > 1 ? 'confirm' : 'members') : 'leader') : null;
  if (BOSS && !(sel.length && isGuard(sel[0]))) { sel = []; step = 'leader'; }
  const oOf = u => owned.find(o => o.uid === u);
  const fire = u => window.VRStory?.canMergeUid?.(u) ? '<b class="pvp-fire" title="합성 가능">🔥</b>' : '';
  const pickBtn = (o, on, badge) => { const c = card(o.id); return c ? `<button data-u="${o.uid}" class="g-${GS[c.grade] || 'N'} ${on ? 'on' : ''}" ${usedElsewhere.has(o.id) ? 'disabled' : ''}>${thumb({ ...c, level: o.level }, (on ? badge : '') + fire(o.uid))}<span class="pvp-card-cost">💰 ${+c.cost || 0}</span><span class="pvp-card-name">${esc(c.name)}</span></button>` : ''; };
  // 맨 윗줄 (화면 위 고정): 현재 덱 칸 · 전투력 합 · HR 코스트 · 자동 채우기 · 덱 설정 완료
  const topRow = bad => {
    const cards = sel.map(oOf).filter(Boolean), pw = cards.reduce((a, o) => a + (+o.power || 0), 0), cost = cards.reduce((a, o) => a + (+card(o.id)?.cost || 0), 0);
    const slotTh = (u, lab) => { const o = u && oOf(u), c = o && card(o.id); return c ? `<button class="pvp-slot g-${GS[c.grade] || 'N'}" data-rm="${u}" title="빼기">${thumb({ ...c, level: o.level })}${lab ? `<b class="pvp-n">${lab}</b>` : ''}</button>` : `<span class="pvp-slot empty">${lab || '＋'}</span>`; };
    const slots = BOSS ? [slotTh(sel[0], '👑'), ...Array.from({ length: BOSS_MEMBERS[1] }, (_, i) => slotTh(sel[i + 1]))] : Array.from({ length: 5 }, (_, i) => slotTh(sel[i]));
    return `<div class="pvp-deckbar"><div class="pvp-slots">${slots.join('')}</div>
      <div class="pvp-dstat"><span class="pvp-pw">⚡ ${pw.toLocaleString('ko-KR')}</span>${L.costCap ? `<span class="pvp-cst ${cost > L.costCap ? 'over' : ''}">💰 ${cost}/${L.costCap}</span>` : ''}
        <button class="pvp-ghost" data-auto title="전투력 순 자동 채우기">⚡ 자동 채우기</button><button data-ok class="pvp-go" ${bad ? 'disabled' : ''}>${bad ? esc(bad) : '덱 설정 완료'}</button></div></div>`;
  };
  // 전투력 순 자동 채우기: 지금 고른 것 유지 · 리그 등급/코스트 · 보스는 리더(HR 이하) 먼저 + 멤버 최대 5장
  const autoFill = () => {
    const byPw = pool.filter(o => !usedElsewhere.has(o.id)).sort((a, b) => (+b.power || 0) - (+a.power || 0));
    const costOf = u => +card(oOf(u)?.id)?.cost || 0, max = BOSS ? 1 + BOSS_MEMBERS[1] : 5;
    let cost = sel.reduce((a, u) => a + costOf(u), 0);
    const ok = o => !sel.includes(o.uid) && !sel.some(u => oOf(u)?.id === o.id) && (!L.costCap || cost + costOf(o.uid) <= L.costCap);
    if (BOSS && !sel.length) { const g = byPw.find(o => GUARD_GRADES.includes(card(o.id)?.grade) && ok(o)); if (!g) return toast('HR 이하 리더 없음'); sel = [g.uid]; cost += costOf(g.uid); }
    for (const o of byPw) { if (sel.length >= max) break; if (ok(o)) { sel.push(o.uid); cost += costOf(o.uid); } }
    if (BOSS) step = sel.length > 1 ? 'confirm' : 'members';
    drawAll();
  };
  // 인재 육성: PvP 창 잠깐 숨김 → 보유 인재 상세 (레벨업·합성·장비) → 돌아오면 최신 정보로 다시 열기
  const train = async uid => {
    const S = window.VRStory; if (!S?.trainCard) return toast('인재 화면 없음');
    const hid = [...document.querySelectorAll('.pvp-modal')]; hid.forEach(e => e.style.display = 'none');
    const back = async () => { hid.forEach(e => e.remove()); await open(); if ($('pvp-modal')) editDeck(slot, { sel, step, query, maxCost }); };
    const ran = await S.trainCard(uid, back, 'PvP 덱으로');
    if (!ran) hid.forEach(e => e.style.display = '');
  };
  // 꾹 누르기 = 바로 인재 육성 · 짧게 = 카드 정보(덱 배치 / 인재 육성)
  const bindPick = () => m.querySelectorAll('.pvp-pick [data-u]').forEach(b => {
    let t = 0, long = false;
    const clear = () => { clearTimeout(t); t = 0; };
    b.onpointerdown = () => { long = false; clear(); t = setTimeout(() => { long = true; train(b.dataset.u); }, 550); };
    b.onpointerup = b.onpointerleave = b.onpointercancel = clear;
    b.oncontextmenu = e => e.preventDefault();
    b.onclick = e => { if (long) { e.preventDefault(); long = false; return; } cardInfo(b.dataset.u); };
  });
  const bindTop = () => {
    m.querySelectorAll('[data-rm]').forEach(b => b.onclick = () => { const u = b.dataset.rm; if (BOSS && u === sel[0]) { sel = []; step = 'leader'; } else sel = sel.filter(x => x !== u); if (BOSS && step === 'confirm' && sel.length < 2) step = 'members'; drawAll(); });
    m.querySelector('[data-auto]')?.addEventListener('click', autoFill);
    m.querySelector('[data-ok]')?.addEventListener('click', () => commit());
  };
  const poolTools = () => `<div class="pvp-filters"><input type="search" data-name value="${esc(query)}" placeholder="이름 검색" aria-label="이름 검색"><label>코스트 ≤ <input type="number" min="0" step="1" inputmode="numeric" data-cost value="${esc(maxCost)}" placeholder="전체" aria-label="최대 코스트"></label></div>${sortChips()}`;
  const filtered = list => sortPool(filterPool(list, query, maxCost));
  const bindFilters = () => {
    for (const key of ['name', 'cost']) {
      const input = m.querySelector(`[data-${key}]`); if (!input) continue;
      const apply = () => {
        const start = input.selectionStart, end = input.selectionEnd;
        const scroll = m.querySelector('.pvp-panel').scrollTop;
        if (key === 'name') query = input.value; else maxCost = input.value === '' ? '' : String(Math.max(0, Math.floor(+input.value || 0)));
        drawAll();
        const next = m.querySelector(`[data-${key}]`); next.focus({ preventScroll: true });
        if (key === 'name') next.setSelectionRange(start, end);
        m.querySelector('.pvp-panel').scrollTop = scroll;
      };
      input.oninput = e => { if (!e.isComposing) apply(); };
      input.oncompositionend = apply;   // Keep Korean IME composition intact while typing.
    }
  };
  const draw = () => BOSS ? drawBoss() : drawNormal();
  const drawBoss = () => {
    const cards = sel.map(u => card(owned.find(o => o.uid === u)?.id)).filter(Boolean), bad = deckCheck(cards, view.league, view.mode), cost = cards.reduce((a, c) => a + (+c.cost || 0), 0);
    const lead = sel[0], mem = sel.slice(1);
    const th = u => { const o = oOf(u), c = o && card(o.id); return c ? thumb({ ...c, level: o.level }) : ''; };
    const stepBar = `<div class="pvp-steps">${[['leader', '① 리더'], ['members', '② 멤버'], ['confirm', '③ 확인']].map(([k, l]) => `<button data-step="${k}" class="${step === k ? 'on' : ''}" ${k !== 'leader' && !lead ? 'disabled' : k === 'confirm' && !mem.length ? 'disabled' : ''}>${l}</button>`).join('')}</div>`;
    const head = `<button class="pvp-x" data-x>✕</button><div class="pvp-h">👑 보스리그 덱 <small>리더 ${lead ? 1 : 0}/1 · 멤버 ${mem.length}/${BOSS_MEMBERS[1]}${L.costCap ? ` · ${cost}/${L.costCap}` : ''}</small></div>${stepBar}`;
    let body = '', acts = '';
    if (step === 'confirm') {
      body = `<div class="pvp-boss-tip">리더는 진영 칸의 수비대장이 돼요 (쓰러지지 않음 · 내 턴 3번 뒤 필드의 HR 이하 카드와 교체 가능)</div>
        <div class="pvp-sec">👑 리더</div><div class="pvp-pick pvp-lead">${th(lead)}</div><button class="pvp-ghost" data-step="leader">리더 바꾸기</button>
        <div class="pvp-sec">멤버 ${mem.length}</div><div class="pvp-pick">${mem.map(th).join('')}</div><button class="pvp-ghost" data-step="members">멤버 바꾸기</button>`;
      acts = `${cur ? '<button data-del class="pvp-ghost">🗑</button>' : ''}<button class="pvp-ghost" data-step="members">← 멤버</button>`;
    } else {
      const list = step === 'leader' ? pool.filter(o => GUARD_GRADES.includes(card(o.id)?.grade)) : pool.filter(o => o.uid !== lead);
      body = `<div class="pvp-boss-tip">${step === 'leader' ? '① 리더(수비대장) 1장을 고르세요 · HR 이하만' : `② 멤버를 고르세요 · ${BOSS_MEMBERS[0]}~${BOSS_MEMBERS[1]}장`}</div>
        ${myDecks.length && step === 'members' ? `<div class="pvp-chips">${myDecks.map((d, i) => `<button data-load="${i}">🗂 ${esc(d.name)}</button>`).join('')}</div>` : ''}
        ${poolTools()}<div class="pvp-pick">${filtered(list).map(o => pickBtn(o, step === 'leader' ? o.uid === lead : mem.includes(o.uid), `<b class="pvp-n">${step === 'leader' ? '👑' : mem.indexOf(o.uid) + 1}</b>`)).join('') || '<div class="pvp-empty">고를 수 있는 카드가 없어요</div>'}</div>`;
      acts = step === 'leader' ? `<button class="pvp-go" data-step="members" ${lead ? '' : 'disabled'}>다음: 멤버</button>` : `<button class="pvp-ghost" data-step="leader">← 리더</button><button class="pvp-go" data-step="confirm" ${mem.length ? '' : 'disabled'}>다음: 확인</button>`;
    }
    m.querySelector('.pvp-panel').innerHTML = `${head}${topRow(bad)}${body}<small class="pvp-gear-note" style="display:block;opacity:.7;font-size:11px;margin:6px 0">🛡️ 장비는 덱을 저장할 때 들어가요 — 장비를 바꿨다면 덱을 다시 저장해야 반영돼요 (PvP 장비 50%)</small><div class="pvp-acts">${acts}</div>`;
    m.querySelectorAll('[data-step]').forEach(b => b.onclick = () => { step = b.dataset.step; drawAll(); });
    bindPick(); bindTop();
    m.querySelectorAll('[data-load]').forEach(b => b.onclick = () => { const d = myDecks[+b.dataset.load]; const ok = new Set(pool.map(o => o.uid)); const ms = d.uids.filter(u => ok.has(u) && u !== lead).slice(0, BOSS_MEMBERS[1]); sel = [lead, ...ms]; if (ms.length < d.uids.length) toast('일부 제외'); drawAll(); });
    m.querySelectorAll('[data-srt]').forEach(b => b.onclick = () => { const sc = m.querySelector('.pvp-pick')?.scrollTop || 0; setPSort(b.dataset.srt); drawAll(); const g = m.querySelector('.pvp-pick'); if (g) g.scrollTop = sc; });
  };
  const drawNormal = () => {
    const cards = sel.map(u => card(owned.find(o => o.uid === u)?.id)).filter(Boolean), bad = deckCheck(cards, view.league, view.mode), cost = cards.reduce((a, c) => a + (+c.cost || 0), 0);
    m.querySelector('.pvp-panel').innerHTML = `<button class="pvp-x" data-x>✕</button>
      <div class="pvp-h">${MODES[view.mode].decks > 1 ? `덱 ${slot + 1}` : '🛡 덱'} <small>${sel.length}/5${L.costCap ? ` · ${cost}/${L.costCap}` : ''}</small></div>${MODES[view.mode].boss ? '<div class="pvp-boss-tip">👑 보스리그: 첫 번째로 고른 카드가 수비대장(HR 이하, 진영 칸 · 쓰러지지 않음). 상대 진영 HP를 0으로 만들면 승리</div>' : ''}
      ${topRow(bad)}${myDecks.length ? `<div class="pvp-chips">${myDecks.map((d, i) => `<button data-load="${i}">🗂 ${esc(d.name)}</button>`).join('')}</div>` : ''}
      ${poolTools()}<div class="pvp-pick">${filtered(pool).map(o => pickBtn(o, sel.includes(o.uid), `<b class="pvp-n">${sel.indexOf(o.uid) + 1}</b>`)).join('') || '<div class="pvp-empty">없음</div>'}</div>
      <div class="pvp-acts">${cur ? '<button data-del class="pvp-ghost">🗑</button>' : ''}</div>`;
    bindPick(); bindTop();
    m.querySelectorAll('[data-load]').forEach(b => b.onclick = () => { const d = myDecks[+b.dataset.load]; const ok = new Set(pool.map(o => o.uid)); sel = d.uids.filter(u => ok.has(u)).slice(0, 5); if (sel.length < d.uids.length) toast('일부 제외'); drawAll(); });
    m.querySelectorAll('[data-srt]').forEach(b => b.onclick = () => { const sc = m.querySelector('.pvp-pick')?.scrollTop || 0; setPSort(b.dataset.srt); drawAll(); const g = m.querySelector('.pvp-pick'); if (g) g.scrollTop = sc; });
  };
  const commit = async () => { try { await rpc('pvp_set_deck', { p_league: view.league, p_mode: view.mode, p_slot: slot, p_uids: sel }); m.remove(); open(); } catch (e) { toast(errText(e)); } };
  const redraw = () => {
    const del = m.querySelector('[data-del]'); if (del) del.onclick = async () => { try { await rpc('pvp_set_deck', { p_league: view.league, p_mode: view.mode, p_slot: slot, p_uids: [] }); m.remove(); open(); } catch (e) { toast(errText(e)); } };
  };
  const draw0 = draw;
  const drawAll = () => { draw0(); bindFilters(); redraw(); };
  // 카드 정보 (확대) → 선택 / 빼기 / 취소. 5장이 되면 저장 여부를 묻는다
  const cardInfo = uid => {
    const o = owned.find(x => x.uid === uid), c = o && card(o.id); if (!c) return;
    const on = BOSS ? (step === 'leader' ? sel[0] === uid : sel.slice(1).includes(uid)) : sel.includes(uid), full = !on && (BOSS ? step === 'members' && sel.length - 1 >= BOSS_MEMBERS[1] : sel.length >= 5), sc = snapCard(o, card) || c;
    const sk = window.TCG?.skillListHTML ? window.TCG.skillListHTML(c, o.level) : '';
    const z = modal('pvp-card', `<div class="pvp-ci g-${GS[c.grade] || 'N'}"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}"></div>
      <div class="pvp-ci-name">${esc(c.name)} <small>${GS[c.grade] || ''} · Lv${o.level || 1}${L.costCap ? ` · 💰${c.cost}` : ''}</small></div>
      <div class="pvp-ci-st"><span>⚔️ ${sc.ATK}</span><span>❤️ ${sc.HP}</span><span>🛡 ${sc.DEF}</span></div>
      ${sk ? `<div class="pvp-ci-sk">${sk}</div>` : ''}
      <div class="pvp-acts"><button class="pvp-ghost" data-x>취소</button><button class="pvp-ghost pvp-train" data-train>🌱 인재 육성</button><button class="pvp-go" data-pick ${full ? 'disabled' : ''}>${on ? (BOSS && step === 'leader' ? '리더 ✔' : '빼기') : full ? (BOSS ? `${BOSS_MEMBERS[1]}/${BOSS_MEMBERS[1]}` : '5/5') : BOSS && step === 'leader' ? '👑 리더로 배치' : '덱 배치'}</button></div>`, 'pvp-sub pvp-top');
    z.querySelector('[data-train]').onclick = () => { z.remove(); train(uid); };
    z.querySelector('[data-pick]').onclick = () => {
      if (BOSS) {
        if (step === 'leader') { if (!on) { sel = [uid, ...sel.slice(1).filter(x => x !== uid)]; step = 'members'; } z.remove(); drawAll(); return; }
        sel = on ? sel.filter(x => x !== uid) : [...sel, uid]; z.remove();
        if (!on && sel.length - 1 >= BOSS_MEMBERS[1]) step = 'confirm';   // 멤버 5장 = 확인 화면으로
        drawAll(); return;
      }
      sel = on ? sel.filter(x => x !== uid) : [...sel, uid]; z.remove(); drawAll();
      if (!on && sel.length === 5 && !deckCheck(sel.map(u => card(owned.find(x => x.uid === u)?.id)).filter(Boolean), view.league, view.mode)) askSave();
    };
  };
  const askSave = () => {
    const q = modal('pvp-ask', `<div class="pvp-h">저장할까요?</div><div class="pvp-acts yn"><button class="pvp-ghost" data-x>N</button><button class="pvp-go" data-yes>Y</button></div>`, 'pvp-sub pvp-top');
    q.querySelector('[data-yes]').onclick = () => { q.remove(); commit(); };
  };
  editBack = () => { if (!BOSS || step === 'leader' || !m.isConnected) return false; step = step === 'confirm' ? 'members' : 'leader'; drawAll(); return true; };
  drawAll();
}

// ---- 매칭 → 계산 → 보고 → 결과 ----
async function fight() {
  // Do not overwrite an unacknowledged receipt with another attempt. Refresh/reopen can retry it.
  if (pendingResult()) { await retryResult(); return; }
  const go = document.querySelector('#pvp-modal [data-go]'); if (go) go.disabled = true;
  const manual = battleMode() === 'manual';
  const waitingStart = pendingStart();
  if (waitingStart && waitingStart.version !== PVP_ENGINE_VERSION) pendingStart(null); // A stale start must not pin refreshes to an old engine forever.
  const body = pendingStart() || { op: 'start', league: view.league, mode: view.mode, request: crypto.randomUUID(), control: (manual || !!VIEW()) ? 'actions' : 'auto', version: PVP_ENGINE_VERSION };
  pendingStart(body);
  let s; try { s = await verifyRpc(body); pendingStart(null); } catch (e) { toast(errText(e)); if (go) go.disabled = false; return; }
  if (s.status === 'settled' && s.result) { showResult(s, s.result); return; }
  if (s.expires_at && Date.parse(s.expires_at) <= Date.now()) {
    try { showResult(s, await verifyRpc({ op: 'forfeit', id: s.id })); } catch (e) { toast(errText(e)); await open(); } return;
  }
  const live = s.control === 'actions';
  await vsScreen(s);
  const toCards = d => d.map(o => snapCard(o, card)).filter(Boolean);
  let res;
  try { res = live ? await viewSeries(s, toCards, manual) : runSeries(s.mode, s.me.map(toCards), s.opp.map(toCards), s.seed, true); }
  catch (e) { toast('전투 중단 · 서버에서 패배 처리돼요'); try { await verifyRpc({ op: 'forfeit', id: s.id }); } catch {} await open(); return; }
  if (!live) await playback(s, res);
  const finish = { op: 'finish', id: s.id, actions: live ? res.acts : null };
  pendingResult({ body: finish, session: s });
  try { const rep = await finishVerified(finish); pendingResult(null); showResult(s, rep); }
  catch (e) {
    // Never pretend that a local win/rating/reward is an official settlement.
    const m = modal('pvp-result', `<div class="pvp-h">결과 미정산</div><div class="pvp-empty">${esc(errText(e))}<br>같은 전투를 다시 저장하면 중복 지급 없이 확인돼요.</div><div class="pvp-acts"><button class="pvp-go" data-retry>다시 저장</button><button data-x>나중에</button></div>`, 'pvp-sub');
    m.querySelector('[data-retry]').onclick = retryResult;
    m.querySelector('[data-x]').onclick = open;
  }
}
function showResult(s, rep) {
  const delta = rep.delta, boss = !!MODES[s.mode || view.mode]?.boss;
  const m = modal('pvp-result', `<button class="pvp-x" data-x>✕</button>
    <div class="pvp-res ${rep.win ? 'win' : 'lose'}">${rep.win ? 'WIN' : 'LOSE'}</div>
    <div class="pvp-vs">${emb(tierOf(s.opp_rating))}<span>${esc(s.opp_name)}${s.bot ? ' 🤖' : ''}</span><small>🏆 ${s.opp_rating}</small></div>
    ${rep.streak >= 2 ? `<div class="pvp-res-streak"><span class="pvp-streak big">🔥${rep.streak}</span>${rep.streak_reward ? `<span class="pvp-rw">${rwHtml(rep.streak_reward)}</span>` : ''}</div>` : ''}
    ${rep.forfeit ? '<div class="pvp-empty">기한 만료/중단 · 보상 없는 패배</div>' : ''}
    ${rep.rounds.map((r, i) => boss ? `<div class="pvp-round pvp-round-boss ${r.win ? 'win' : 'lose'}"><div class="pvp-result-side"><strong>상대${r.win ? ' · 진영 파괴' : ''}</strong><div class="pvp-side foe">${snapThumbs(s.opp[i])}</div></div><div class="pvp-result-side"><strong>나${r.win ? '' : ' · 패배'}</strong><div class="pvp-side">${snapThumbs(s.me[i])}</div></div></div>` : `<div class="pvp-round ${r.win ? 'win' : 'lose'}"><div class="pvp-side">${snapThumbs(s.me[i])}</div><b>${r.win ? '○' : '✕'}</b><div class="pvp-side foe">${snapThumbs(s.opp[i])}</div></div>`).join('')}
    <div class="pvp-delta ${delta >= 0 ? 'up' : 'down'}">${emb(tierOf(rep.rating))} ${rep.rating} <b>${delta >= 0 ? '+' : ''}${delta}</b></div>
    <div class="pvp-acts"><button class="pvp-go" data-x>확인</button></div>`, 'pvp-sub');
  m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) open(); });
  if (rep.streak_reward) window.VRPlayer?.wallet?.(true);
}

// ---- 수동: 판마다 내가 조작 (상대는 AI). 같은 seed·스냅샷 · 2선승 ----
async function manualSeries(s, toCards) { return viewSeries(s, toCards, true); }
/** 판마다 전투 화면. manual=false 면 AUTO 로 보여 주기만 (결과는 runSeries 와 같음) */
async function viewSeries(s, toCards, manual) {
  const M = MODES[s.mode || view.mode], rounds = [], acts = []; let w = 0, l = 0;
  for (let i = 0; i < M.decks; i++) {
    const log = [], ttl = `${M.decks > 1 ? `${i + 1}판 · ` : ''}${s.tag || '⚔️ PvP'} vs ${s.opp_name}${s.bot ? ' 🤖' : ''}`;
    let r, ses;
    if (VIEW()) { ses = manualMatch(toCards(s.me[i]), toCards(s.opp[i]), roundSeed(s.seed, i), log, { view: true, manual: true, boss: !!M.boss });
      r = await VIEW()({ session: ses, aiName: `${s.opp_name}${s.bot ? ' 🤖' : ''}`, manual: true, auto: !manual, maxTurns: 40, music: window.VR_BGM?.pvpBattle, title: ttl, bg: 'normal', bgKey: 'pvp' }); }
    else { ses = manualMatch(toCards(s.me[i]), toCards(s.opp[i]), roundSeed(s.seed, i), log, { boss: !!M.boss }); r = await playManual({ session: ses, rec: log, title: `${s.opp_name}${s.bot ? ' 🤖' : ''}`, maxTurns: 40, round: M.decks > 1 ? `${i + 1}판` : '' }); }
    r.log = log; rounds.push(r); acts.push(ses.acts); r.win ? w++ : l++;
    if (w >= M.need || l >= M.need) break;
  }
  return { win: w >= M.need, wins: w, losses: l, rounds, acts };
}
// ---- 전투 재생 (계산된 전투 기록 그대로 · SKIP = 결과로) ----
const STEP = 336;   // 재생 한 칸 (2026-11-03: 420 → 336, 일반 전투와 같이 약 20% 빠르게)
const spd = () => 1;   // 2배속 없음 (2026-10-30)
function playback(s, res) {
  return new Promise(done => {
    let stop = false, timer = 0;
    const m = modal('pvp-play', '', 'pvp-sub pvp-top');
    const end = () => { if (stop) return; stop = true; clearTimeout(timer); m.remove(); done(); };
    m.addEventListener('click', e => { if (e.target === m) end(); });
    const side = (ros, cls) => `<div class="pvp-pb-side ${cls}">${ros.map(r => `<div class="pvp-pb-u" data-uid="${r.uid}"><img src="${cardThumb(r.id)}" alt=""><i><b></b></i></div>`).join('')}</div>`;
    const play = (ri) => {
      if (stop) return;
      if (ri >= res.rounds.length) return end();
      const R = res.rounds[ri], log = R.log || [];
      const n = res.rounds.length > 1 || (s.mode || view.mode) === '3v3' ? `${ri + 1}판` : '';
      m.querySelector('.pvp-panel').innerHTML = `<div class="pvp-pb-top"><span>${esc(s.opp_name)}${s.bot ? ' 🤖' : ''}</span><small class="pvp-pb-t">${n}</small><button class="pvp-skip" data-skip>SKIP ⏭</button></div>
        ${side(log.roster?.B || [], 'foe')}<div class="pvp-pb-fx"></div>${side(log.roster?.A || [], 'me')}`;
      m.querySelector('[data-skip]').onclick = end;
      const U = (sd, uid) => m.querySelector(`.pvp-pb-side.${sd === 'A' ? 'me' : 'foe'} [data-uid="${uid}"]`);
      const maxOf = {}; ['A', 'B'].forEach(k => (log.roster?.[k] || []).forEach(r => maxOf[k + r.uid] = r.max));
      const paintHp = f => ['A', 'B'].forEach(k => (log.roster?.[k] || []).forEach(r => { const el = U(k, r.uid); if (!el) return; const hp = f[k][r.uid] ?? 0; el.querySelector('b').style.width = `${Math.max(0, Math.min(100, hp / r.max * 100))}%`; el.classList.toggle('dead', hp <= 0); }));
      let i = 0;
      const tick = () => {
        if (stop) return;
        if (i >= log.length) { const fx = m.querySelector('.pvp-pb-fx'); fx.textContent = R.win ? 'WIN' : 'LOSE'; fx.className = `pvp-pb-fx big ${R.win ? 'win' : 'lose'}`; timer = setTimeout(() => play(ri + 1), 1100 / spd()); return; }
        const f = log[i++]; m.querySelectorAll('.act,.hit').forEach(x => x.classList.remove('act', 'hit'));
        if (f.k === 'turn') { m.querySelector('.pvp-pb-t').textContent = `${n ? n + ' · ' : ''}T${f.t}`; }
        if (f.u != null) { U(f.side, f.u)?.classList.add('act'); if (f.to != null) U(f.side === 'A' ? 'B' : 'A', f.to)?.classList.add('hit'); }
        const fx = m.querySelector('.pvp-pb-fx'); fx.className = 'pvp-pb-fx'; fx.textContent = f.k === 'skill' && f.s ? `✨ ${f.s}` : '';
        paintHp(f); timer = setTimeout(tick, (f.k === 'turn' ? STEP / 2 : STEP) / spd());
      };
      tick();
    };
    play(0);
  });
}

// ---- 랭킹 ----
const rkRow = (x, nm, pos) => { const label = nm ?? x.name; const ttl = x.title_name ? `<i class="cosmo-ttl t-${esc(x.title || '')}">${esc(x.title_name)}</i>` : ''; return `<div class="pvp-rk-row ${x.me ? 'me' : ''} ${pos ? 'tap' : ''}"${pos ? ` data-who="${pos}"` : ''}><b>${x.rank <= 3 ? ['🥇', '🥈', '🥉'][x.rank - 1] : x.rank}</b><span class="pvp-rk-nm">${emb(tierBy(x.tier) || tierOf(x.rating), 'sm')}<span class="cosmo-tx"><span class="${x.abyss || x.title === 'abyss' ? 'pvp-abyss-name' : ''}">${esc(label)}</span>${ttl}</span></span><small>${x.wins}W ${x.losses}L</small><em>${x.rating}</em></div>`; };
const rkRows = r => ((r?.top || []).slice(0, 10).map((x, i) => rkRow(x, undefined, i + 1)).join('') || '<div class="pvp-empty">—</div>') + (r?.me && !(r.top || []).slice(0, 10).some(x => x.me) ? rkRow(r.me, '나') : '');
async function rankings() {
  const m = modal('pvp-ranking', `<div class="pvp-empty">…</div>`, 'pvp-sub');
  let r; try { r = await rpc('pvp_rankings', { p_league: view.league, p_mode: view.mode, p_season: null }); } catch (e) { m.querySelector('.pvp-panel').innerHTML = `<div class="pvp-empty">${esc(errText(e))}</div>`; return; }
  m.querySelector('.pvp-panel').innerHTML = `<button class="pvp-x" data-x>✕</button><div class="pvp-h">🏅 ${LEAGUES[view.league].label} · ${view.mode}</div>
    <div class="pvp-rk">${(r.top || []).map((x, i) => rkRow(x, undefined, i + 1)).join('') || '<div class="pvp-empty">—</div>'}</div>
    ${r.me && !(r.top || []).some(x => x.me) ? `<div class="pvp-rk-row me"><b>${r.me.rank}</b><span>나</span><small>${r.me.wins}W ${r.me.losses}L</small><em>${r.me.rating}</em></div>` : ''}`;
  bindWho(m);
}
// ---- 랭커 정보 팝업 (계정 레벨 · 리더 · PvP 덱 · 소속 조직) — 서버 pvp_user_info 는 공개 필드만 줌 ----
const bindWho = m => m.querySelectorAll('[data-who]').forEach(b => b.onclick = () => who(+b.dataset.who));
async function who(pos) {
  const m = modal('pvp-who', `<div class="pvp-empty">…</div>`, 'pvp-sub');
  let r; try { r = await rpc('pvp_user_info', { p_league: view.league, p_mode: view.mode, p_rank: pos }); } catch (e) { m.querySelector('.pvp-panel').innerHTML = `<button class="pvp-x" data-x>✕</button><div class="pvp-empty">${esc(errText(e))}</div>`; return; }
  const lc = r.leader && card(r.leader);
  const face = `<div class="pvp-who-face">${r.leader ? `<img src="${IMG}${esc(r.leader)}.webp" alt="${esc(lc?.name || '')}" onerror="this.style.visibility='hidden'">` : '<i>👤</i>'}</div>`;
  const guild = r.guild ? `<span class="pvp-who-g"><img src="img/ui/guild/e${String(r.guild.emblem || 1).padStart(2, '0')}.webp" alt="" onerror="this.remove()">${esc(r.guild.name)}</span>` : '<span class="pvp-who-g none">소속 조직 없음</span>';
  const decks = (r.decks || []).map(d => `<div class="pvp-who-deck">${d.cards.map(c => thumb(card(c.id) && { ...card(c.id), level: c.level })).join('')}</div>`).join('') || '<div class="pvp-empty">덱 없음</div>';
  m.querySelector('.pvp-panel').innerHTML = `<button class="pvp-x" data-x>✕</button>
    <div class="pvp-who-top">${face}<div class="pvp-who-m"><b>${esc(r.name)}</b><small>Lv.${r.level} · ${pos}위</small>${guild}</div></div>
    <div class="pvp-who-h">🛡 PvP 덱 · ${LEAGUES[view.league].label} ${view.mode}</div>${decks}`;
}

// ---- 👥 친구 대전 (supabase/friend_battle.sql) — PvP 와 같은 비동기 방식: 친구의 무제한 리그 방어 덱 · 레이팅/보상 없음 ----
const FB_ERR = { 'not friends': '친구가 아니에요', 'friend deck missing': '친구가 PvP 무제한 방어 덱을 등록하지 않았어요', 'deck required': '내 PvP 무제한 덱을 먼저 등록해 주세요', 'no attempts left': '오늘 친구 대전 횟수(20회)를 다 썼어요' };
export async function friendFight(friend, mode = '1v1') {
  let s; try { s = await rpc('friend_battle_start', { p_friend: friend, p_mode: mode }); }
  catch (e) { const m = String(e?.message || e), k = Object.keys(FB_ERR).find(x => m.includes(x)); toast(k ? FB_ERR[k] : errText(e)); return null; }
  s.tag = '👥 친구 대전';
  await vsScreen(s);
  const toCards = d => d.map(o => snapCard(o, card)).filter(Boolean);
  const manual = battleMode() === 'manual', live = manual || !!VIEW();
  const res = live ? await viewSeries(s, toCards, manual) : runSeries(s.mode, s.me.map(toCards), s.opp.map(toCards), s.seed, true);
  let rep = null; try { rep = await rpc('friend_battle_report', { p_id: s.id, p_wins: res.wins, p_losses: res.losses, p_actions: live ? res.acts : null }); } catch (e) { toast(errText(e)); }
  if (!live) await playback(s, res);
  try { window.dispatchEvent(new CustomEvent('vr:daily', { detail: { k: 'battle', mode: 'friend', win: !!res.win } })); } catch {}
  modal('pvp-result', `<button class="pvp-x" data-x>✕</button>
    <div class="pvp-res ${res.win ? 'win' : 'lose'}">${res.win ? 'WIN' : 'LOSE'}</div>
    <div class="pvp-vs"><span>👥 ${esc(s.opp_name)}</span><small>${s.mode}</small></div>
    ${res.rounds.map((r, i) => `<div class="pvp-round ${r.win ? 'win' : 'lose'}"><div class="pvp-side">${snapThumbs(s.me[i])}</div><b>${r.win ? '○' : '✕'}</b><div class="pvp-side foe">${snapThumbs(s.opp[i])}</div></div>`).join('')}
    ${rep?.record ? `<div class="pvp-delta up">상대 전적 ${rep.record.w}승 ${rep.record.l}패</div>` : ''}
    <div class="pvp-acts"><button class="pvp-go" data-x>확인</button></div>`, 'pvp-sub');
  return rep;
}

const bind = () => { const b = $('main-pvp'); if (b) b.onclick = open; };
bind(); document.addEventListener('DOMContentLoaded', bind);
window.VRPvp = { open, tierOf, friendFight };
