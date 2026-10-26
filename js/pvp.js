// ===== 비동기 PvP 화면 =====
// 서버: supabase/pvp.sql (pvp_status / pvp_set_deck / pvp_start / pvp_report / pvp_rankings). 전투 계산: js/pvp-core.js (양쪽 자동 AI)
// 리그: 무제한(open) · HR 이하(hr, 코스트 150) / 모드: 1v1 · 3v3(3덱 2선승) / 하루 10회 · 주간 시즌(월 00:00 KST)
import { LEAGUES, MODES, snapCard, deckCheck, runSeries } from './pvp-core.js';
const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);
const GS = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR' };
const LS = 'vrTcgPvp.view';
let view = (() => { try { return { league: 'open', mode: '1v1', ...JSON.parse(localStorage.getItem(LS) || '{}') }; } catch { return { league: 'open', mode: '1v1' }; } })();
let st = null, top = null, owned = [], myDecks = [];
const card = id => window.TCG?.cardById?.(id);
async function rpc(name, args) {
  if (window.__PVP_MOCK) return window.__PVP_MOCK(name, args);
  const sb = window.VRCloud?.sb; if (!sb) throw new Error('offline');
  const { data, error } = await sb.rpc(name, args); if (error) throw new Error(error.message); return data;
}
const ERR = { 'no attempts left': '오늘 횟수 끝', 'deck required': '덱 필요', 'card not owned': '없는 카드', 'duplicate card': '중복', 'grade not allowed': 'HR 이하만', 'cost over 150': '코스트 150 초과', 'card used in another deck': '다른 덱에 있음', 'login required': '로그인 필요' };
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
    <div class="pvp-stat"><span title="레이팅">🏆 <b>${st.rating}</b></span><span title="승/패">${st.wins}W ${st.losses}L</span><span title="방어">🛡 ${st.def_wins}/${st.def_losses}</span><span title="오늘 남은 횟수">🎫 ${st.left}/${st.max}</span></div>
    <div class="pvp-decks">${decks.map((d, i) => `<button class="pvp-deck ${d ? '' : 'empty'}" data-edit="${i}">
      <span class="pvp-deck-no">${n > 1 ? i + 1 : '🛡'}</span><span class="pvp-deck-row">${d ? d.uids.map(u => thumb(byUid.get(u) && { ...card(byUid.get(u).id), level: byUid.get(u).level })).join('') : '<span class="pvp-plus">＋</span>'}</span>
      ${view.league === 'hr' && d ? `<small class="pvp-cost">${d.cost}/150</small>` : ''}</button>`).join('')}</div>
    <div class="pvp-acts"><button class="pvp-rank" data-rank title="랭킹">🏅</button><button class="pvp-go" data-go ${ready ? '' : 'disabled'}>⚔️ 매칭</button></div>
    <div class="pvp-top"><div class="pvp-top-h">🏅 TOP 10</div><div class="pvp-rk">${rkRows(top)}</div></div>`;
  m.querySelectorAll('[data-league]').forEach(b => b.onclick = () => { view.league = b.dataset.league; save(); open(); });
  m.querySelectorAll('[data-mode]').forEach(b => b.onclick = () => { view.mode = b.dataset.mode; save(); open(); });
  m.querySelectorAll('[data-edit]').forEach(b => b.onclick = () => editDeck(+b.dataset.edit));
  m.querySelector('[data-rank]').onclick = rankings;
  m.querySelector('[data-go]').onclick = fight;
}
const save = () => localStorage.setItem(LS, JSON.stringify(view));

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
    const q = modal('pvp-ask', `<div class="pvp-h">저장할까요?</div><div class="pvp-acts"><button class="pvp-ghost" data-x>아니오</button><button class="pvp-go" data-yes>예</button></div>`, 'pvp-sub pvp-top');
    q.querySelector('[data-yes]').onclick = () => { q.remove(); commit(); };
  };
  drawAll();
}

// ---- 매칭 → 계산 → 보고 → 결과 ----
async function fight() {
  const go = document.querySelector('#pvp-modal [data-go]'); if (go) go.disabled = true;
  let s; try { s = await rpc('pvp_start', { p_league: view.league, p_mode: view.mode }); } catch (e) { toast(errText(e)); if (go) go.disabled = false; return; }
  const toCards = d => d.map(o => snapCard(o, card)).filter(Boolean);
  const res = runSeries(view.mode, s.me.map(toCards), s.opp.map(toCards), s.seed, true);
  // 결과는 재생 전에 먼저 1회 보고 (재생 중 이탈해도 결과 동일 · 중복 보고 없음)
  let rep = null; try { rep = await rpc('pvp_report', { p_id: s.id, p_wins: res.wins, p_losses: res.losses }); } catch (e) { toast(errText(e)); }
  await playback(s, res);
  const delta = rep ? rep.delta : -s.dl;
  const m = modal('pvp-result', `<button class="pvp-x" data-x>✕</button>
    <div class="pvp-res ${res.win ? 'win' : 'lose'}">${res.win ? 'WIN' : 'LOSE'}</div>
    <div class="pvp-vs"><span>${esc(s.opp_name)}${s.bot ? ' 🤖' : ''}</span><small>🏆 ${s.opp_rating}</small></div>
    ${res.rounds.map((r, i) => `<div class="pvp-round ${r.win ? 'win' : 'lose'}"><div class="pvp-side">${snapThumbs(s.me[i])}</div><b>${r.win ? '○' : '✕'}</b><div class="pvp-side foe">${snapThumbs(s.opp[i])}</div></div>`).join('')}
    <div class="pvp-delta ${delta >= 0 ? 'up' : 'down'}">🏆 ${(rep?.rating ?? s.rating - s.dl)} <b>${delta >= 0 ? '+' : ''}${delta}</b></div>
    <div class="pvp-acts"><button class="pvp-go" data-x>확인</button></div>`, 'pvp-sub');
  m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) open(); });
}

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
const rkRow = (x, nm) => `<div class="pvp-rk-row ${x.me ? 'me' : ''}"><b>${x.rank <= 3 ? ['🥇', '🥈', '🥉'][x.rank - 1] : x.rank}</b><span>${esc(nm ?? x.name)}</span><small>${x.wins}W ${x.losses}L</small><em>${x.rating}</em></div>`;
const rkRows = r => ((r?.top || []).slice(0, 10).map(x => rkRow(x)).join('') || '<div class="pvp-empty">—</div>') + (r?.me && !(r.top || []).slice(0, 10).some(x => x.me) ? rkRow(r.me, '나') : '');
async function rankings() {
  const m = modal('pvp-ranking', `<div class="pvp-empty">…</div>`, 'pvp-sub');
  let r; try { r = await rpc('pvp_rankings', { p_league: view.league, p_mode: view.mode, p_season: null }); } catch (e) { m.querySelector('.pvp-panel').innerHTML = `<div class="pvp-empty">${esc(errText(e))}</div>`; return; }
  m.querySelector('.pvp-panel').innerHTML = `<button class="pvp-x" data-x>✕</button><div class="pvp-h">🏅 ${LEAGUES[view.league].label} · ${view.mode}</div>
    <div class="pvp-rk">${(r.top || []).map(x => `<div class="pvp-rk-row ${x.me ? 'me' : ''}"><b>${x.rank <= 3 ? ['🥇', '🥈', '🥉'][x.rank - 1] : x.rank}</b><span>${esc(x.name)}</span><small>${x.wins}W ${x.losses}L</small><em>${x.rating}</em></div>`).join('') || '<div class="pvp-empty">—</div>'}</div>
    ${r.me && !(r.top || []).some(x => x.me) ? `<div class="pvp-rk-row me"><b>${r.me.rank}</b><span>나</span><small>${r.me.wins}W ${r.me.losses}L</small><em>${r.me.rating}</em></div>` : ''}`;
}

const bind = () => { const b = $('main-pvp'); if (b) b.onclick = open; };
bind(); document.addEventListener('DOMContentLoaded', bind);
window.VRPvp = { open };
