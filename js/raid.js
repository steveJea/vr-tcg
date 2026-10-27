// ===== 조직 토벌 「균열 토벌」 화면 =====
// 서버: supabase/guild3.sql (raid_status / raid_set_difficulty / raid_start / raid_finish / raid_sweep / raid_claim). 전투: js/raid-core.js (자동 전투, 서버 seed)
// 그림: img/ui/guild/raid_banner.webp · raid_bg.webp · raid_icon.webp · raid_diff_<normal|hard|abyss>.webp (없으면 이모지). 보스는 카드 그림(IMG)
import { snapCard } from './pvp-core.js';
import { runRaid, RAID_DIFF, RAID_BOSSES, RAID_TURNS } from './raid-core.js';

const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const UI = 'img/ui/guild/';
const DECK_KEY = 'vrRaidDeck';
const card = id => window.TCG?.cardById?.(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const n = v => Number(v || 0).toLocaleString('ko-KR');
const big = v => { v = Number(v || 0); return v >= 1e8 ? `${(v / 1e8).toFixed(1)}억` : v >= 1e4 ? `${(v / 1e4).toFixed(v >= 1e6 ? 0 : 1)}만` : n(v); };
const RW = { loyalty: '🩸', gold: '🪙', gem: '🔮', tickets: '🎟️' };
const rwTxt = rw => Object.entries(rw || {}).filter(([k, v]) => RW[k] && v).map(([k, v]) => `<span>${RW[k]}${n(v)}</span>`).join('');
const DIFF_IC = { normal: '🟢', hard: '🟠', abyss: '🟣' };
const ATTR = { CHARGE: '돌격', DEFENSE: '방어', CRUSH: '분쇄', SUPPORT: '지원', DISTURB: '교란', FASCINATION: '매혹' };
const ERR = { 'not in guild': '조직에 들어가야 해요', 'no attempts': '오늘 토벌 횟수를 다 썼어요', 'fight first': '오늘 한 번 직접 싸워야 소탕할 수 있어요', 'raid ended': '이번 주 토벌이 끝났어요 (일 22시 정산)',
  'card not owned': '덱 카드를 다시 골라 주세요', 'duplicate card': '같은 카드는 한 장만', 'deck size': '덱은 1~5장', 'too fast': '잠시 후 다시', 'battle expired': '시간이 지나 무효가 됐어요',
  'guild level': '조직 레벨이 부족해요', 'raid started': '이번 주 토벌이 이미 시작됐어요', 'not allowed': '보스·간부만 바꿀 수 있어요', 'nothing to claim': '받을 보상이 없어요', 'login required': '로그인이 필요해요' };
const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
async function rpc(name, args) {
  const m = window.__RAID_MOCK; if (m) return m(name, args);
  const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) throw new Error('login required');
  const { data, error } = await sb.rpc(name, args); if (error) throw new Error(error.message); return data;
}
function toast(t) { const el = document.createElement('div'); el.className = 'gd-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2400); }
function pop(html, cls = '') {
  const m = document.createElement('div'); m.className = 'gd-pop rd-pop';
  m.innerHTML = `<div class="gd-pop-panel ${cls}"><button class="gd-x" data-x aria-label="닫기">✕</button>${html}</div>`;
  m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) m.remove(); });
  document.body.appendChild(m); return m;
}
const bossImg = (b, cls = '') => { const meta = RAID_BOSSES.find(x => x.name === b?.name); return b?.id ? `<img class="${cls}" src="${IMG}${b.id}.webp" alt="" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'rd-bfb',textContent:'${meta?.icon || '👹'}'}))">` : `<span class="rd-bfb">${meta?.icon || '👹'}</span>`; };
const diffIc = d => `<span class="rd-diff"><img src="${UI}raid_diff_${d}.webp" alt="" onerror="this.remove()"><i>${DIFF_IC[d]}</i>${RAID_DIFF[d].label}</span>`;

// ---- 덱: 고른 스토리 덱 · 없으면 전투력 상위 5장 (같은 카드 1장) ----
let sum = null;
async function decks() {
  if (window.__RAID_MOCK_DECKS) return window.__RAID_MOCK_DECKS;
  sum = await window.VRStory?.summary?.(); if (!sum?.ok) return [];
  const byUid = new Map(sum.owned.map(o => [o.uid, o]));
  const uniq = uids => { const seen = new Set(); return uids.map(u => byUid.get(u)).filter(o => o && !seen.has(o.id) && seen.add(o.id)).slice(0, 5); };
  const top = uniq(sum.owned.slice().sort((a, b) => b.power - a.power).map(o => o.uid));
  return [{ key: 'top', name: '⚡ 전투력 상위', cards: top }, ...sum.decks.map((d, i) => ({ key: 'd' + i, name: d.name, cards: uniq(d.uids) })).filter(d => d.cards.length)];
}
const pickDeck = list => list.find(d => d.key === localStorage.getItem(DECK_KEY)) || list[0];
const thumbs = cards => cards.map(o => `<span class="rd-th"><img src="${IMG}${o.id}.webp" alt="" loading="lazy" onerror="this.remove()"><small>Lv.${o.level}</small></span>`).join('');

let S = null, M = null, DL = [];
export async function open() {
  M?.remove();
  M = pop('<div class="gd-loading">…</div>', 'wide rd');
  try { [S, DL] = await Promise.all([rpc('raid_status'), decks()]); } catch (e) { toast(errText(e)); M.remove(); return; }
  paint();
}
function paint() {
  if (!M?.isConnected) return;
  const s = S, b = s.boss, pct = Math.max(0, Math.min(100, s.hp_left / s.hp_max * 100)), dk = pickDeck(DL);
  const left = Math.max(0, Math.ceil((new Date(s.ends_at) - Date.now()) / 36e5));
  M.querySelector('.gd-pop-panel').innerHTML = `<button class="gd-x" data-x aria-label="닫기">✕</button>
    <div class="rd-hero"><img class="rd-bg" src="${UI}raid_banner.webp" alt="" onerror="this.remove()">${bossImg(b, 'rd-boss')}
      <div class="rd-hero-t"><small>${s.stage}단계</small><b>${esc(b.name)}</b><span class="rd-weak">약점 ${ATTR[b.weak] || b.weak}</span></div>
      <button class="rd-dbtn" data-diff ${s.can_set_diff ? '' : 'disabled'}>${diffIc(s.difficulty)}</button>
      <span class="rd-time">${s.ended ? '정산 중' : left > 24 ? `${Math.floor(left / 24)}일 남음` : `${left}시간 남음`}</span></div>
    <div class="rd-hp"><i style="width:${pct}%"></i><span>${big(s.hp_left)} / ${big(s.hp_max)}</span></div>
    <div class="rd-next">다음: ${esc(s.next_boss.name)} · 이번 주 누적 ${big(s.total_damage)}</div>
    <button class="rd-deck" data-deck>${dk ? `<b>${esc(dk.name)}</b><span class="rd-ths">${thumbs(dk.cards)}</span>` : '<b>덱 없음</b>'}<em>바꾸기 ›</em></button>
    <div class="rd-acts"><button class="gd-big rd-go" data-go ${s.attempts_left && !s.ended && dk ? '' : 'disabled'}>⚔️ 토벌 <small>${s.attempts_left}/3</small></button>
      <button class="rd-sw" data-sweep ${s.can_sweep && s.attempts_left && !s.ended ? '' : 'disabled'}>⏩ 소탕<small>${s.can_sweep ? big(s.sweep_damage) : '직접 1회 후'}</small></button></div>
    <button class="rd-claim ${s.claimable ? 'on' : ''}" data-claim ${s.claimable ? '' : 'disabled'}>🎁 보상 받기${s.claimable ? ` <i>${s.claimable}</i>` : ''}</button>
    <div class="rd-h">처치 단계 <button class="rd-info" data-info>보상표 ⓘ</button></div>
    <div class="rd-stages">${s.stages.map(x => `<span class="${x.cleared ? (x.claimed ? 'done' : 'ready') : 'cur'}">${bossImg(x.boss)}<b>${x.stage}</b>${x.cleared ? (x.claimed ? '✔' : '🎁') : ''}</span>`).join('')}</div>
    <div class="rd-h">이번 주 피해 순위</div>
    <div class="rd-rk">${s.ranking.length ? s.ranking.map((x, i) => `<div class="${x.me ? 'me' : ''}"><b>${['🥇', '🥈', '🥉'][i] || i + 1}</b><span>${esc(x.name)}</span><small>${x.attempts}회</small><em>${big(x.damage)}</em></div>`).join('') : '<div class="rd-empty">아직 아무도 토벌하지 않았어요</div>'}</div>`;
  const q = sel => M.querySelector(sel);
  q('[data-go]').onclick = fight;
  q('[data-sweep]').onclick = sweep;
  q('[data-claim]').onclick = claim;
  q('[data-deck]').onclick = deckPop;
  q('[data-info]').onclick = infoPop;
  q('[data-diff]').onclick = diffPop;
}
function deckPop() {
  const m = pop(`<div class="rd-pt">덱 고르기</div>${DL.map(d => `<button class="rd-dk ${pickDeck(DL)?.key === d.key ? 'on' : ''}" data-k="${d.key}"><b>${esc(d.name)}</b><span class="rd-ths">${thumbs(d.cards)}</span></button>`).join('') || '<div class="rd-empty">스토리 카드가 필요해요</div>'}`);
  m.querySelectorAll('[data-k]').forEach(b => b.onclick = () => { localStorage.setItem(DECK_KEY, b.dataset.k); m.remove(); paint(); });
}
function infoPop() {
  const s = S, mult = s.diff_mult[s.difficulty];
  pop(`<div class="rd-pt">보상표 <small>${diffIc(s.difficulty)}</small></div>
    <table class="rd-tb"><tr><th>주간 순위</th><td>${s.rank_rewards.map(r => `<div><b>${r.from === r.to ? `${r.from}위` : `${r.from}~${r.to}위`}</b> ${rwTxt(r.reward)}</div>`).join('')}</td></tr>
    <tr><th>조직원 전원</th><td>${rwTxt(s.member_reward)} <small>(순위 보상에 더해서)</small></td></tr>
    <tr><th>단계 처치<br><small>전원 · ×${mult}</small></th><td><div>매 단계 ${rwTxt({ loyalty: Math.round(20 * mult), gold: Math.round(2000 * mult), gem: Math.round(30 * mult) })}</div><div>3·6·9…단계 🔮+${Math.round(150 * mult)}</div><div>5·10…단계 🎟️1</div></td></tr>
    <tr><th>1회 토벌</th><td>🩸5 · 🪙200~2,000</td></tr></table>
    <small class="rd-note">하루 3회 · 일 22:00 정산 · 순위/참여 보상은 정산 24시간 전 가입자만</small>`);
}
function diffPop() {
  const s = S;
  const m = pop(`<div class="rd-pt">난이도</div>${Object.keys(RAID_DIFF).map(d => { const lock = s.guild_level < s.diff_level[d];
    return `<button class="rd-dk ${s.difficulty === d ? 'on' : ''}" data-d="${d}" ${lock ? 'disabled' : ''}>${diffIc(d)}<span>보상 ×${s.diff_mult[d]}</span>${lock ? `<small>🔒 조직 Lv.${s.diff_level[d]}</small>` : ''}</button>`; }).join('')}<small class="rd-note">이번 주 첫 토벌 전까지만 바꿀 수 있어요</small>`);
  m.querySelectorAll('[data-d]').forEach(b => b.onclick = async () => { try { S = await rpc('raid_set_difficulty', { p_diff: b.dataset.d }); m.remove(); paint(); } catch (e) { toast(errText(e)); } });
}
async function claim(e) {
  e.currentTarget.disabled = true;
  try { S = await rpc('raid_claim'); const g = S.got || {}; toast(`받음 ${rwTxt(g).replace(/<[^>]+>/g, ' ')}${g.rank ? ` · ${g.rank}위` : ''}`); window.VRPlayer?.wallet?.(true); window.VRGem?.status?.(true); window.dispatchEvent(new Event('vr:guild')); }
  catch (er) { toast(errText(er)); }
  paint();
}
async function sweep(e) {
  e.currentTarget.disabled = true;
  try { S = await rpc('raid_sweep'); result(S.result); } catch (er) { toast(errText(er)); }
  paint();
}
async function fight(e) {
  const dk = pickDeck(DL); if (!dk) return;
  e.currentTarget.disabled = true;
  let st; try { st = await rpc('raid_start', { p_uids: dk.cards.map(o => o.uid) }); } catch (er) { toast(errText(er)); paint(); return; }
  const deck = st.deck.map(o => snapCard(o, card)).filter(Boolean), log = [], t0 = Date.now();
  const res = runRaid(deck, st.stage, st.difficulty, st.seed, card, log);
  await playback(st, res, log, t0);
  let fin = null;
  for (let i = 0; i < 3 && !fin; i++) { try { fin = await rpc('raid_finish', { p_id: st.id, p_damage: res.damage }); } catch (er) { if (/too fast/.test(er.message)) await new Promise(r => setTimeout(r, 1500)); else { toast(errText(er)); break; } } }
  if (fin) { S = fin; result(fin.result); } else { try { S = await rpc('raid_status'); } catch {} }
  paint();
}
function result(r) {
  if (!r) return;
  window.VRPlayer?.wallet?.(true);
  pop(`<div class="rd-res"><small>입힌 피해</small><b>${n(r.damage)}</b>${r.cleared ? `<div class="rd-clr">💥 ${r.cleared}단계 처치!</div>` : ''}<div class="rd-got">${rwTxt(r.got)}</div></div><button class="gd-big" data-x>확인</button>`, 'rd-r');
}
// ---- 전투 재생 (계산된 기록 그대로 · SKIP) ----
function playback(st, res, log, t0) {
  return new Promise(done => {
    let stop = false, timer = 0, i = 0;
    const m = pop('', 'wide rd-pb');
    const end = () => { if (stop) return; stop = true; clearTimeout(timer); const wait = Math.max(0, 3200 - (Date.now() - t0)); setTimeout(() => { m.remove(); done(); }, wait); };
    m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) end(); }, true);
    const ros = log.roster?.A || [];
    m.querySelector('.gd-pop-panel').innerHTML = `<div class="rd-pb-top"><span>${esc(st.boss.name)} · ${st.stage}단계</span><small class="rd-pb-t">T1/${RAID_TURNS}</small><button class="rd-skip" data-skip>SKIP ⏭</button></div>
      <div class="rd-pb-boss"><img class="rd-bg" src="${UI}raid_bg.webp" alt="" onerror="this.remove()">${bossImg(st.boss, 'rd-boss')}<div class="rd-pb-fx"></div></div>
      <div class="rd-pb-dmg">0</div>
      <div class="rd-pb-me">${ros.map(r => `<div class="rd-pb-u" data-uid="${r.uid}"><img src="${IMG}${r.id}.webp" alt=""><i><b></b></i></div>`).join('')}</div>`;
    m.querySelector('[data-skip]').onclick = e => { e.stopPropagation(); i = log.length; m.querySelector('.rd-pb-dmg').textContent = n(res.damage); end(); };
    const U = uid => m.querySelector(`.rd-pb-u[data-uid="${uid}"]`);
    const tick = () => {
      if (stop) return;
      if (i >= log.length) { m.querySelector('.rd-pb-dmg').textContent = n(res.damage); return end(); }
      const f = log[i++]; m.querySelectorAll('.act').forEach(x => x.classList.remove('act'));
      if (f.k === 'turn') m.querySelector('.rd-pb-t').textContent = `T${f.t}/${RAID_TURNS}`;
      if (f.side === 'A' && f.u != null) U(f.u)?.classList.add('act');
      const fx = m.querySelector('.rd-pb-fx');
      if (f.d) { fx.textContent = `-${n(f.d)}`; fx.className = 'rd-pb-fx hit'; void fx.offsetWidth; fx.className = 'rd-pb-fx hit go'; }
      if (f.s && f.side === 'A') fx.textContent = `✨ ${f.s}${f.d ? ` -${n(f.d)}` : ''}`;
      m.querySelector('.rd-pb-dmg').textContent = n(f.dmg);
      ros.forEach(r => { const el = U(r.uid); if (!el) return; const hp = f.A?.[r.uid] ?? 0; el.querySelector('b').style.width = `${Math.max(0, Math.min(100, hp / r.max * 100))}%`; el.classList.toggle('dead', hp <= 0); });
      timer = setTimeout(tick, f.k === 'turn' ? 160 : 300);
    };
    tick();
  });
}
window.VRRaid = { open, claimable: () => rpc('raid_claimable').catch(() => 0) };
