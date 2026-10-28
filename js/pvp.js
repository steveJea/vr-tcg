// ===== 비동기 PvP 화면 =====
// 서버: supabase/pvp.sql (pvp_status / pvp_set_deck / pvp_start / pvp_report / pvp_rankings). 전투 계산: js/pvp-core.js (양쪽 자동 AI)
// 리그: 무제한(open) · HR 이하(hr, 코스트 150) / 모드: 1v1 · 3v3(3덱 2선승) / 하루 10회 · 주간 시즌(월 00:00 KST)
import { LEAGUES, MODES, snapCard, deckCheck, runSeries, manualMatch, roundSeed } from './pvp-core.js';
const VIEW = () => window.TCG?.viewBattle;   // 스토리·탑과 같은 전투 화면 (js/game.js)
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
const ERR = { 'no attempts left': '오늘 횟수 끝', 'not enough gem': '🔮 부족', 'deck required': '덱 필요', 'card not owned': '없는 인재', 'duplicate card': '중복', 'grade not allowed': 'HR 이하만', 'cost over 150': '코스트 150 초과', 'card used in another deck': '다른 덱에 있음', 'login required': '로그인 필요' };
const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 40); };
function toast(t) { const el = document.createElement('div'); el.className = 'pvp-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 1800); }

// ---- 공통 창 (바깥 누르면 닫힘) ----
function modal(id, html, cls = '') {
  $(id)?.remove();
  const m = document.createElement('div'); m.id = id; m.className = `pvp-modal ${cls}`;
  m.innerHTML = `<div class="pvp-panel" role="dialog">${html}</div>`;
  m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) m.remove(); });
  document.body.appendChild(m); return m;
}
const thumb = (c, extra = '') => c ? `<div class="pvp-th g-${GS[c.grade] || 'N'}" title="${esc(c.name)}"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}" loading="lazy" onerror="this.style.visibility='hidden'"><i>${c.level ? 'Lv' + c.level : GS[c.grade] || ''}</i>${extra}</div>` : '';
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
  const m = modal('pvp-modal', `<div class="pvp-empty">…</div>`);
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
  const ready = decks.every(Boolean) && st.left > 0;
  const byUid = new Map(owned.map(o => [o.uid, o]));
  m.querySelector('.pvp-panel').innerHTML = `
    <button class="pvp-x" data-x aria-label="닫기">✕</button>
    <div class="pvp-h">⚔️ PvP <small>${dleft()}</small></div>
    <div class="pvp-tabs">${Object.entries(LEAGUES).map(([k, L]) => `<button data-league="${k}" class="${view.league === k ? 'on' : ''}">${L.label}</button>`).join('')}
      <span class="pvp-sep"></span>${Object.keys(MODES).map(k => `<button data-mode="${k}" class="${view.mode === k ? 'on' : ''}">${k}</button>`).join('')}</div>
    ${myRank()}
    <div class="pvp-decks">${decks.map((d, i) => `<button class="pvp-deck ${d ? '' : 'empty'}" data-edit="${i}">
      <span class="pvp-deck-no">${n > 1 ? i + 1 : '🛡'}</span><span class="pvp-deck-row">${d ? d.uids.map(u => thumb(byUid.get(u) && { ...card(byUid.get(u).id), level: byUid.get(u).level })).join('') : '<span class="pvp-plus">＋</span>'}</span>
      ${view.league === 'hr' && d ? `<small class="pvp-cost">${d.cost}/150</small>` : ''}</button>`).join('')}</div>
    <div class="pvp-bmode">${modeToggle()}</div>
    <div class="pvp-acts"><button class="pvp-rank" data-rank title="랭킹">🏅</button><button class="pvp-rank" data-shop title="PvP 상점">🛒</button>${st.left <= 0 && window.VRGem?.item?.('pvp_try') ? `<button class="pvp-gemtry" data-gemtry ${window.VRGem.item('pvp_try').left === 0 ? 'disabled' : ''} title="추가 도전 (하루 3회)">🎫+1 <small>🔮${window.VRGem.item('pvp_try').price}</small></button>` : ''}<button class="pvp-go" data-go ${ready ? '' : 'disabled'}>⚔️ 매칭</button></div>
    <div class="pvp-top"><div class="pvp-top-h">🏅 TOP 10</div><div class="pvp-rk">${rkRows(top)}</div></div>`;
  m.querySelectorAll('[data-league]').forEach(b => b.onclick = () => { view.league = b.dataset.league; save(); open(); });
  m.querySelectorAll('[data-mode]').forEach(b => b.onclick = () => { view.mode = b.dataset.mode; save(); open(); });
  m.querySelectorAll('[data-edit]').forEach(b => b.onclick = () => editDeck(+b.dataset.edit));
  m.querySelector('[data-rank]').onclick = rankings; bindWho(m);
  m.querySelector('[data-shop]').onclick = () => window.VRGear?.pvpShop?.();   // 장비 PR7
  m.querySelector('[data-tiers]').onclick = tierTable;
  if (st.pending) claimTier();
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
    <div class="pvp-h pvp-h2">🔥 연승</div>
    <div class="pvp-tt">${(st.streaks || []).map(x => `<div class="pvp-tt-row ${st.streak >= x.n ? 'got' : ''}"><span class="pvp-streak">🔥${x.n}</span><span class="pvp-rw">${rwHtml(x.reward)}</span></div>`).join('')}</div>`, 'pvp-sub');
}
/** 지난 시즌 티어 보상 자동 수령 (서버가 1회만 지급) */
async function claimTier() {
  const p = st.pending; st.pending = null;
  let r; try { r = await rpc('pvp_claim_tier', { p_league: view.league, p_mode: view.mode }); } catch (e) { return; }
  const t = tierBy(r.tier) || TIERS[0];
  window.VRPlayer?.wallet?.(true);
  modal('pvp-claim', `<div class="pvp-claim t-${t.k}">${emb(t, 'huge')}<div class="pvp-claim-t">${t.label}</div><small>지난 시즌 · 🏆 ${r.rating}</small><div class="pvp-rw big">${rwHtml(r.reward)}</div></div>
    <div class="pvp-acts"><button class="pvp-go" data-x>받기</button></div>`, 'pvp-sub');
}
/** VS 연출 (~1.5초 · 탭하면 넘김 · 연출 끄기면 생략) */
function vsScreen(s) {
  if (fxOff()) return Promise.resolve();
  const lead = d => d?.[0]?.[0]?.id, me = lead(s.me), op = lead(s.opp), ot = tierOf(s.opp_rating), mt = tierOf(s.rating);
  return new Promise(done => {
    const el = document.createElement('div'); el.className = 'pvp-vsx'; el.setAttribute('role', 'button'); el.setAttribute('aria-label', '탭하여 넘기기');
    el.innerHTML = `<div class="pvp-vsx-side me">${me ? `<img src="${IMG}${me}.webp" alt="">` : ''}<div class="pvp-vsx-tag">${emb(mt)}<b>${esc((document.querySelector('.acct-name')?.textContent || '나').replace(/님$/, ''))}</b><small>${s.rating}</small></div></div>
      <div class="pvp-vsx-side op">${op ? `<img src="${IMG}${op}.webp" alt="">` : ''}<div class="pvp-vsx-tag">${emb(ot)}<b>${esc(s.opp_name)}${s.bot ? ' 🤖' : ''}</b><small>${s.opp_rating}</small></div></div>
      <div class="pvp-vsx-vs">VS</div>`;
    let t = 0; const end = () => { clearTimeout(t); el.classList.add('out'); setTimeout(() => { el.remove(); done(); }, 180); };
    el.addEventListener('click', end, { once: true }); document.body.appendChild(el); t = setTimeout(end, 1500);
  });
}

// ---- 덱 편집 (PvP 전용 · 마이 덱에서 불러오기) ----
function editDeck(slot) {
  const cur = st.decks.find(d => d.slot === slot);
  let sel = cur ? [...cur.uids] : [];
  const L = LEAGUES[view.league];
  const usedElsewhere = new Set(st.decks.filter(d => d.slot !== slot).flatMap(d => d.uids.map(u => owned.find(o => o.uid === u)?.id)));
  const pool = [...new Map(owned.filter(o => !L.grades || L.grades.includes(card(o.id)?.grade)).sort((a, b) => b.power - a.power).map(o => [o.id, o])).values()];   // 같은 카드는 가장 센 1장
  const m = modal('pvp-edit', '', 'pvp-sub');
  const draw = () => {
    const cards = sel.map(u => card(owned.find(o => o.uid === u)?.id)).filter(Boolean), bad = deckCheck(cards, view.league), cost = cards.reduce((a, c) => a + (+c.cost || 0), 0);
    m.querySelector('.pvp-panel').innerHTML = `<button class="pvp-x" data-x>✕</button>
      <div class="pvp-h">${MODES[view.mode].decks > 1 ? `덱 ${slot + 1}` : '🛡 덱'} <small>${sel.length}/5${L.costCap ? ` · ${cost}/${L.costCap}` : ''}</small></div>
      ${myDecks.length ? `<div class="pvp-chips">${myDecks.map((d, i) => `<button data-load="${i}">🗂 ${esc(d.name)}</button>`).join('')}</div>` : ''}
      <div class="pvp-pick">${pool.map(o => { const c = card(o.id), on = sel.includes(o.uid), dis = usedElsewhere.has(o.id); return c ? `<button data-u="${o.uid}" class="${on ? 'on' : ''}" ${dis ? 'disabled' : ''}>${thumb({ ...c, level: o.level }, on ? `<b class="pvp-n">${sel.indexOf(o.uid) + 1}</b>` : '')}</button>` : ''; }).join('') || '<div class="pvp-empty">없음</div>'}</div>
      <div class="pvp-acts">${cur ? '<button data-del class="pvp-ghost">🗑</button>' : ''}<button data-ok class="pvp-go" ${bad ? 'disabled' : ''}>${bad ? esc(bad) : '저장'}</button></div>`;
    m.querySelectorAll('[data-u]').forEach(b => b.onclick = () => cardInfo(b.dataset.u));
    m.querySelectorAll('[data-load]').forEach(b => b.onclick = () => { const d = myDecks[+b.dataset.load]; const ok = new Set(pool.map(o => o.uid)); sel = d.uids.filter(u => ok.has(u)).slice(0, 5); if (sel.length < d.uids.length) toast('일부 제외'); drawAll(); });
    m.querySelector('[data-ok]').onclick = () => commit();
  };
  const commit = async () => { try { await rpc('pvp_set_deck', { p_league: view.league, p_mode: view.mode, p_slot: slot, p_uids: sel }); m.remove(); open(); } catch (e) { toast(errText(e)); } };
  const redraw = () => {
    const del = m.querySelector('[data-del]'); if (del) del.onclick = async () => { try { await rpc('pvp_set_deck', { p_league: view.league, p_mode: view.mode, p_slot: slot, p_uids: [] }); m.remove(); open(); } catch (e) { toast(errText(e)); } };
  };
  const draw0 = draw;
  const drawAll = () => { draw0(); redraw(); };
  // 카드 정보 (확대) → 선택 / 빼기 / 취소. 5장이 되면 저장 여부를 묻는다
  const cardInfo = uid => {
    const o = owned.find(x => x.uid === uid), c = o && card(o.id); if (!c) return;
    const on = sel.includes(uid), full = !on && sel.length >= 5, sc = snapCard(o, card) || c;
    const sk = window.TCG?.skillListHTML ? window.TCG.skillListHTML(c, o.level) : '';
    const z = modal('pvp-card', `<div class="pvp-ci g-${GS[c.grade] || 'N'}"><img src="${IMG}${c.id}.webp" alt="${esc(c.name)}"></div>
      <div class="pvp-ci-name">${esc(c.name)} <small>${GS[c.grade] || ''} · Lv${o.level || 1}${L.costCap ? ` · 💰${c.cost}` : ''}</small></div>
      <div class="pvp-ci-st"><span>⚔️ ${sc.ATK}</span><span>❤️ ${sc.HP}</span><span>🛡 ${sc.DEF}</span></div>
      ${sk ? `<div class="pvp-ci-sk">${sk}</div>` : ''}
      <div class="pvp-acts"><button class="pvp-ghost" data-x>취소</button><button class="pvp-go" data-pick ${full ? 'disabled' : ''}>${on ? '빼기' : full ? '5/5' : '선택'}</button></div>`, 'pvp-sub pvp-top');
    z.querySelector('[data-pick]').onclick = () => {
      sel = on ? sel.filter(x => x !== uid) : [...sel, uid]; z.remove(); drawAll();
      if (!on && sel.length === 5 && !deckCheck(sel.map(u => card(owned.find(x => x.uid === u)?.id)).filter(Boolean), view.league)) askSave();
    };
  };
  const askSave = () => {
    const q = modal('pvp-ask', `<div class="pvp-h">저장할까요?</div><div class="pvp-acts yn"><button class="pvp-ghost" data-x>N</button><button class="pvp-go" data-yes>Y</button></div>`, 'pvp-sub pvp-top');
    q.querySelector('[data-yes]').onclick = () => { q.remove(); commit(); };
  };
  drawAll();
}

// ---- 매칭 → 계산 → 보고 → 결과 ----
async function fight() {
  const go = document.querySelector('#pvp-modal [data-go]'); if (go) go.disabled = true;
  let s; try { s = await rpc('pvp_start', { p_league: view.league, p_mode: view.mode }); } catch (e) { toast(errText(e)); if (go) go.disabled = false; return; }
  await vsScreen(s);
  const toCards = d => d.map(o => snapCard(o, card)).filter(Boolean);
  const manual = battleMode() === 'manual';
  const res = manual ? await manualSeries(s, toCards) : runSeries(view.mode, s.me.map(toCards), s.opp.map(toCards), s.seed, true);
  // 결과는 재생 전에 먼저 1회 보고 (재생 중 이탈해도 결과 동일 · 중복 보고 없음). 수동은 행동 기록을 먼저 남김 (tools/pvp_verify.mjs 재생 검증)
  if (manual) { try { await rpc('pvp_log', { p_id: s.id, p_actions: res.acts }); } catch (e) { toast(errText(e)); } }
  let rep = null; try { rep = await rpc('pvp_report', { p_id: s.id, p_wins: res.wins, p_losses: res.losses }); } catch (e) { toast(errText(e)); }
  if (!manual) { if (VIEW()) await viewSeries(s, toCards, false); else await playback(s, res); }
  const delta = rep ? rep.delta : -s.dl;
  const m = modal('pvp-result', `<button class="pvp-x" data-x>✕</button>
    <div class="pvp-res ${res.win ? 'win' : 'lose'}">${res.win ? 'WIN' : 'LOSE'}</div>
    <div class="pvp-vs">${emb(tierOf(s.opp_rating))}<span>${esc(s.opp_name)}${s.bot ? ' 🤖' : ''}</span><small>🏆 ${s.opp_rating}</small></div>
    ${rep?.streak >= 2 ? `<div class="pvp-res-streak"><span class="pvp-streak big">🔥${rep.streak}</span>${rep.streak_reward ? `<span class="pvp-rw">${rwHtml(rep.streak_reward)}</span>` : ''}</div>` : ''}
    ${res.rounds.map((r, i) => `<div class="pvp-round ${r.win ? 'win' : 'lose'}"><div class="pvp-side">${snapThumbs(s.me[i])}</div><b>${r.win ? '○' : '✕'}</b><div class="pvp-side foe">${snapThumbs(s.opp[i])}</div></div>`).join('')}
    <div class="pvp-delta ${delta >= 0 ? 'up' : 'down'}">${emb(tierOf(rep?.rating ?? s.rating - s.dl))} ${(rep?.rating ?? s.rating - s.dl)} <b>${delta >= 0 ? '+' : ''}${delta}</b></div>
    <div class="pvp-acts"><button class="pvp-go" data-x>확인</button></div>`, 'pvp-sub');
  m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) open(); });
  if (rep?.streak_reward) window.VRPlayer?.wallet?.(true);
}

// ---- 수동: 판마다 내가 조작 (상대는 AI). 같은 seed·스냅샷 · 2선승 ----
async function manualSeries(s, toCards) { return viewSeries(s, toCards, true); }
/** 판마다 전투 화면. manual=false 면 AUTO 로 보여 주기만 (결과는 runSeries 와 같음) */
async function viewSeries(s, toCards, manual) {
  const M = MODES[view.mode], rounds = [], acts = []; let w = 0, l = 0;
  for (let i = 0; i < M.decks; i++) {
    const log = [], ttl = `${M.decks > 1 ? `${i + 1}판 · ` : ''}⚔️ PvP vs ${s.opp_name}${s.bot ? ' 🤖' : ''}`;
    let r, ses;
    if (VIEW()) { ses = manualMatch(toCards(s.me[i]), toCards(s.opp[i]), roundSeed(s.seed, i), log, { view: true, manual: true });
      if (!manual) ses = autoFeed(ses);
      r = await VIEW()({ session: ses, aiName: `${s.opp_name}${s.bot ? ' 🤖' : ''}`, manual, maxTurns: 40, title: ttl, bg: 'normal' }); }
    else { ses = manualMatch(toCards(s.me[i]), toCards(s.opp[i]), roundSeed(s.seed, i), log); r = await playManual({ session: ses, rec: log, title: `${s.opp_name}${s.bot ? ' 🤖' : ''}`, maxTurns: 40, round: M.decks > 1 ? `${i + 1}판` : '' }); }
    r.log = log; rounds.push(r); acts.push(ses.acts); r.win ? w++ : l++;
    if (w >= M.need || l >= M.need) break;
  }
  return { win: w >= M.need, wins: w, losses: l, rounds, acts };
}
/** AUTO 보기: 내 차례 입력을 항상 AUTO 로 (화면의 AUTO 버튼으로 수동 전환 불가 · 이미 보고한 결과와 같아야 함) */
const autoFeed = ses => ({ events: ses.events, acts: ses.acts, next: inp => { let x = ses.next(inp); while (!x.done && x.value.ask) x = ses.next({ k: 'auto' }); return x; } });
// ---- 전투 재생 (계산된 전투 기록 그대로 · SKIP = 결과로) ----
const STEP = 420, SPD_KEY = 'vrTcgSpd2';
const spd = () => localStorage.getItem(SPD_KEY) === '1' ? 2 : 1;
function playback(s, res) {
  return new Promise(done => {
    let stop = false, timer = 0;
    const m = modal('pvp-play', '', 'pvp-sub pvp-top');
    const end = () => { if (stop) return; stop = true; clearTimeout(timer); m.remove(); done(); };
    m.addEventListener('click', e => { if (e.target === m) end(); });
    const side = (ros, cls) => `<div class="pvp-pb-side ${cls}">${ros.map(r => `<div class="pvp-pb-u" data-uid="${r.uid}"><img src="${IMG}${r.id}.webp" alt=""><i><b></b></i></div>`).join('')}</div>`;
    const play = (ri) => {
      if (stop) return;
      if (ri >= res.rounds.length) return end();
      const R = res.rounds[ri], log = R.log || [];
      const n = res.rounds.length > 1 || view.mode === '3v3' ? `${ri + 1}판` : '';
      m.querySelector('.pvp-panel').innerHTML = `<div class="pvp-pb-top"><span>${esc(s.opp_name)}${s.bot ? ' 🤖' : ''}</span><small class="pvp-pb-t">${n}</small><button class="pvp-spd ${spd() > 1 ? 'on' : ''}" data-spd aria-label="2배속">X2</button><button class="pvp-skip" data-skip>SKIP ⏭</button></div>
        ${side(log.roster?.B || [], 'foe')}<div class="pvp-pb-fx"></div>${side(log.roster?.A || [], 'me')}`;
      m.querySelector('[data-skip]').onclick = end;
      m.querySelector('[data-spd]').onclick = e => { const on = spd() < 2; localStorage.setItem(SPD_KEY, on ? '1' : '0'); e.currentTarget.classList.toggle('on', on); };
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
const rkRow = (x, nm, pos) => `<div class="pvp-rk-row ${x.me ? 'me' : ''} ${pos ? 'tap' : ''}"${pos ? ` data-who="${pos}"` : ''}><b>${x.rank <= 3 ? ['🥇', '🥈', '🥉'][x.rank - 1] : x.rank}</b><span class="pvp-rk-nm">${emb(tierBy(x.tier) || tierOf(x.rating), 'sm')}<span class="${x.abyss ? 'pvp-abyss-name' : ''}">${esc(nm ?? x.name)}</span></span><small>${x.wins}W ${x.losses}L</small><em>${x.rating}</em></div>`;
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

const bind = () => { const b = $('main-pvp'); if (b) b.onclick = open; };
bind(); document.addEventListener('DOMContentLoaded', bind);
window.VRPvp = { open, tierOf };
