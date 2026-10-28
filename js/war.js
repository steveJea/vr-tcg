// ===== 조직 전쟁 「구역 전쟁」 화면 =====
// 서버: supabase/guild4.sql (war_status / war_enter / war_withdraw / war_set_slot / war_set_deck / war_start / war_finish / war_claim). 전투: js/war-core.js (양쪽 자동, 서버 seed)
// 그림: img/ui/guild/war_banner.webp · war_bg.webp · war_icon.webp · war_role_<def|atk|mid|boss|etc>.webp · war_ajit.webp · war_npc.webp (없으면 이모지). 카드는 IMG
import { runWar, warSession, warDeck, warCard, WAR_ROLES } from './war-core.js';
import { modeToggle, bindMode, battleMode } from './manual-ui.js';

const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const UI = 'img/ui/guild/';
const card = id => window.TCG?.cardById?.(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const n = v => Number(v || 0).toLocaleString('ko-KR');
const gi = (n, e, c = '') => `<img class="gi ${c}" src="img/ui/guild/${n}.webp" alt="${e}" draggable="false" onerror="this.replaceWith(this.alt)">`;
const RW = { loyalty: gi('cur_loyalty', '🩸'), gold: gi('cur_gold', '🪙'), gem: gi('cur_gem', '🔮'), tickets: gi('cur_ticket', '🎟️') };
const rwTxt = rw => Object.entries(rw || {}).filter(([k, v]) => RW[k] && v).map(([k, v]) => `<span>${RW[k]}${n(v)}</span>`).join('');
const ROLE_ORDER = ['def', 'atk', 'mid', 'boss', 'etc'];
const ERR = { 'not in guild': '조직에 들어가야 해요', 'not allowed': '권한이 없어요', 'signup closed': '신청 기간이 아니에요', 'need members': '조직원 10명 이상 필요해요', 'not entered': '먼저 참가 신청',
  'defense locked': '방어 덱은 시즌 중 못 바꿔요', 'same card': '1·2번 덱에 같은 인재는 안 돼요', 'card not owned': '덱 인재를 다시 골라 주세요', 'duplicate card': '같은 인재는 한 명만', 'deck size': '덱은 1~5장',
  'not battle time': '전투 시간은 09:00~23:00', 'no match': '오늘 경기가 없어요', 'match ended': '오늘 경기는 끝났어요', 'not in roster': '전쟁 명단에 없어요', 'ajit destroyed': '내 아지트가 무너져 공격할 수 없어요',
  'no attacks': '오늘 공격 5회를 다 썼어요', 'already destroyed': '이미 무너진 아지트', 'target busy': '다른 조직원이 공격 중', 'defense first': '방어조 5곳을 먼저 무너뜨리세요', 'no attack deck': '공격 덱을 먼저 정하세요',
  'deck dead': '이 공격 덱은 모두 쓰러졌어요', 'too fast': '잠시 후 다시', 'nothing to claim': '받을 보상이 없어요', 'login required': '로그인이 필요해요' };
const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
async function rpc(name, args) {
  const m = window.__WAR_MOCK; if (m) return m(name, args);
  const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) throw new Error('login required');
  const { data, error } = await sb.rpc(name, args); if (error) throw new Error(error.message); return data;
}
function toast(t) { const el = document.createElement('div'); el.className = 'gd-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2400); }
function pop(html, cls = '') {
  const m = document.createElement('div'); m.className = 'gd-pop wr-pop';
  m.innerHTML = `<div class="gd-pop-panel ${cls}"><button class="gd-x" data-x aria-label="닫기">${gi('ic_close', '✕')}</button>${html}</div>`;
  m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) m.remove(); });
  document.body.appendChild(m); return m;
}
const roleIc = r => `<span class="wr-ric"><img src="${UI}war_role_${r}.webp" alt="" onerror="this.remove()"><i>${WAR_ROLES[r].icon}</i></span>`;
const D = d => { const x = new Date(d + 'T00:00:00+09:00'); return `${x.getMonth() + 1}/${x.getDate()}`; };
const PH = { soon: '신청 전 (셋째 주 일~화 신청)', signup: '신청 기간', live: '전투 중', rest: '휴전', ended: '시즌 종료' };
// 아지트 HP % (카드 스냅샷 기준)
const hpPct = cards => { let a = 0, b = 0; for (const o of cards || []) { const c = warCard({ uid: 'x', ...o, hp: null }, card); if (!c) continue; b += c.HP; a += o.hp == null ? c.HP : Math.min(c.HP, +o.hp); } return b ? a / b * 100 : 0; };

let S = null, M = null, tab = 'enemy';
export async function open() {
  M?.remove(); M = pop('<div class="gd-loading">…</div>', 'wide wr');
  try { S = await rpc('war_status'); } catch (e) { toast(errText(e)); M.remove(); return; }
  paint();
}
async function reload() { try { S = await rpc('war_status'); } catch (e) { toast(errText(e)); } paint(); }
function paint() {
  if (!M?.isConnected) return;
  const s = S, mt = s.match, e = s.entry;
  const top = `<button class="gd-x" data-x aria-label="닫기">${gi('ic_close', '✕')}</button>
    <div class="wr-hero"><img class="rd-bg" src="${UI}war_banner.webp" alt="" onerror="this.remove()"><span class="wr-hfb">🏴</span>
      <div class="wr-hero-t"><b>구역 전쟁</b><small>${D(s.season)} ~ ${D(s.season_end)} · ${PH[s.phase]}${s.day ? ` · ${s.day}일차` : ''}</small></div>
      <button class="vh-q wr-q" type="button" aria-label="도움말" onclick="window.VRHelp&&VRHelp.open('war')">?</button><button class="wr-mydeck" data-decks>${gi('war_deck', '🃏')} 내 덱</button></div>
    ${s.claimable ? `<button class="rd-claim on" data-claim>${gi('ic_gift', '🎁')} 보상 받기 <i>${s.claimable}</i></button>` : ''}`;
  let body = '';
  if (!s.guild) body = '<div class="rd-empty">조직에 들어가야 참가할 수 있어요</div>';
  else if (!mt) body = signupView();
  else {
    const sc = (a, b) => `<div class="wr-vs"><div class="wr-vs-me"><b>우리</b><em>${n(a)}</em></div><span>VS</span><div class="wr-vs-op"><b>${esc(mt.opponent.name)}${mt.opponent.npc ? ' ' + gi('war_npc', '🤡') : ''}</b><em>${n(b)}</em></div></div>`;
    body = `${sc(mt.score_me, mt.score_opp)}
      ${mt.ended ? `<div class="wr-end ${mt.winner_me ? 'win' : mt.draw ? 'draw' : 'lose'}">${mt.winner_me ? (mt.boss_kill ? (gi('role_boss', '👑') + ' 보스 격파 승리!') : (gi('war_win', '🏆') + ' 승리')) : mt.draw ? '무승부' : '패배'}</div>`
        : `<div class="wr-me">${gi('role_officer', '⚔️')} 남은 공격 <b>${mt.me.attacks_left}/5</b>${mt.me.slot ? ` · 내 아지트 ${mt.me.alive ? gi('war_ajit', '🏠') : gi('fx_destroy', '💥')}` : ' · 명단 밖'}${mt.gate_open ? '' : ' · <em>방어조 먼저!</em>'}</div>`}
      <div class="wr-tabs">${[['enemy', (gi('war_tab_enemy', '🎯') + ' 적 구역')], ['mine', (gi('war_ajit', '🏠') + ' 우리 구역')], ['rank', (gi('war_win', '🏆') + ' 순위')]].map(([k, l]) => `<button data-tab="${k}" class="${tab === k ? 'on' : ''}">${l}</button>`).join('')}</div>
      ${tab === 'rank' ? rankView() : mapView(tab === 'enemy' ? mt.enemy : mt.mine, tab === 'enemy')}`;
  }
  M.querySelector('.gd-pop-panel').innerHTML = top + body;
  const q = sel => M.querySelectorAll(sel);
  q('[data-decks]').forEach(b => b.onclick = deckPop);
  q('[data-claim]').forEach(b => b.onclick = claim);
  q('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; paint(); });
  q('[data-aj]').forEach(b => b.onclick = () => ajitPop(+b.dataset.aj, b.dataset.foe === '1'));
  q('[data-enter]').forEach(b => b.onclick = async () => { try { S = await rpc('war_enter'); toast('참가 신청 완료'); } catch (er) { toast(errText(er)); } paint(); });
  q('[data-withdraw]').forEach(b => b.onclick = async () => { if (!confirm('참가를 취소할까요?')) return; try { S = await rpc('war_withdraw'); } catch (er) { toast(errText(er)); } paint(); });
  q('[data-slot]').forEach(b => b.onclick = () => slotPop(+b.dataset.slot));
}
function signupView() {
  const s = S, e = s.entry, boss = s.guild.role === 'boss', can = ['boss', 'officer'].includes(s.guild.role);
  if (!e) return `<div class="wr-sign"><div>${gi('war_icon', '🏴')} 이번 시즌 참가 신청 <small>(조직원 ${s.guild.members}/10명 이상)</small></div>
    ${s.phase === 'signup' ? (can ? '<button class="gd-big" data-enter>참가 신청</button>' : '<small>보스·간부가 신청할 수 있어요</small>') : (s.phase === 'soon' ? '<small>신청은 셋째 주 일~화 (수 09시 마감)</small>' : '<small>다음 시즌을 기다려 주세요</small>')}</div>${rankView()}`;
  const groups = ROLE_ORDER.map(r => `<div class="wr-grp"><div class="wr-grp-h">${roleIc(r)}${WAR_ROLES[r].label}</div><div class="wr-slots">${s.roster.filter(x => x.role === r).map(x =>
    `<button class="wr-slot ${x.user_id ? '' : 'empty'}" data-slot="${x.slot}" ${boss && s.phase === 'signup' ? '' : 'disabled'}><b>${x.user_id ? esc(x.name || '조직원') : (gi('war_npc', '🤡') + ' 불량배')}</b>${x.user_id ? (x.ready ? '<small>🛡️✔</small>' : '<small class="bad">덱 없음</small>') : ''}</button>`).join('')}</div></div>`).join('');
  return `<div class="wr-sign"><div>${gi('ic_check', '✅')} ${e.status === 'out' ? (gi('ic_cross', '❌') + ' 인원 부족으로 불참') : '참가 중'}${e.locked ? ' · 명단 잠김' : ''}</div>${boss && s.phase === 'signup' ? '<button class="wr-wd" data-withdraw>참가 취소</button>' : ''}</div>${groups}`;
}
const roleBuff = r => { const x = WAR_ROLES[r], t = []; if (x.atk > 1 && x.def > 1) t.push(`공방 +${Math.round((x.atk - 1) * 100)}%`); else { if (x.atk > 1) t.push(`공격 +${Math.round((x.atk - 1) * 100)}%`); if (x.def > 1) t.push(`방어 +${Math.round((x.def - 1) * 100)}%`); } return `${t.join(' ')} · ${n(S.numbers.points[r])}점`; };
function mapView(list, foe) {
  const gate = S.match.gate_open;
  return ROLE_ORDER.map(r => `<div class="wr-grp"><div class="wr-grp-h">${roleIc(r)}${WAR_ROLES[r].label}</div><div class="wr-ajs ${r}">${list.filter(a => a.role === r).map(a => {
    const lead = a.cards[0], p = a.destroyed ? 0 : hpPct(a.cards), lock = foe && r !== 'def' && !gate;
    return `<button class="wr-aj ${a.destroyed ? 'dead' : ''} ${lock ? 'lock' : ''} ${a.locked ? 'busy' : ''}" data-aj="${a.slot}" data-foe="${foe ? 1 : 0}">
      ${lead ? `<img src="${IMG}${lead.id}.webp" alt="" loading="lazy" onerror="this.remove()">` : ''}${a.npc ? `<span class="wr-npc">${gi('war_npc', '🤡')}</span>` : ''}
      <i class="wr-hpb"><b style="width:${p}%"></b></i><small>${esc(a.name)}</small>${a.decks > 1 ? `<em class="wr-dk">${a.deck}/${a.decks}</em>` : ''}${a.destroyed ? `<span class="wr-x">${gi('fx_destroy', '💥')}</span>` : lock ? `<span class="wr-x">${gi('ic_lock', '🔒')}</span>` : a.locked ? `<span class="wr-x">${gi('role_officer', '⚔️')}</span>` : ''}</button>`; }).join('')}</div></div>`).join('');
}
function rankView() {
  const st = S.standings || [];
  return `<div class="rd-h">시즌 순위 <small>승 ${S.numbers.standings.win} · 무 ${S.numbers.standings.draw} · 보스 격파 +${S.numbers.standings.boss_bonus}</small></div>
    <div class="rd-rk">${st.length ? st.map(x => `<div class="${x.me ? 'me' : ''}"><b>${[gi('rank_1', '🥇'), gi('rank_2', '🥈'), gi('rank_3', '🥉')][x.rank - 1] || x.rank}</b><span>${esc(x.name)}</span><small>${x.wins}승 ${x.draws}무 ${x.losses}패</small><em>${x.points}점</em></div>`).join('') : '<div class="rd-empty">아직 참가한 조직이 없어요</div>'}</div>
    <div class="rd-h">시즌 보상</div><table class="rd-tb">${S.numbers.season_rank.map(r => `<tr><th>${r.from === r.to ? `${r.from}위` : `${r.from}~${r.to}위`}</th><td>${rwTxt(r.reward)}</td></tr>`).join('')}
      <tr><th>참가 조직원</th><td>${rwTxt(S.numbers.season_member)} <small>(순위 보상에 더해서)</small></td></tr><tr><th>경기 승리</th><td>${rwTxt(S.numbers.match_win)} · 보스 격파 +${rwTxt(S.numbers.match_boss_kill)}</td></tr><tr><th>무승부</th><td>${rwTxt(S.numbers.match_draw)}</td></tr><tr><th>패배</th><td>${rwTxt(S.numbers.match_loss)}</td></tr></table>`;
}
function ajitPop(slot, foe) {
  const mt = S.match, a = (foe ? mt.enemy : mt.mine).find(x => x.slot === slot); if (!a) return;
  const can = foe && !mt.ended && !a.destroyed && S.phase === 'live' && mt.me.alive && mt.me.attacks_left > 0 && (a.role === 'def' || mt.gate_open);
  const atk = mt.me.atk || {}, has = k => !!S.decks?.['atk' + k];
  const m = pop(`<div class="rd-pt">${roleIc(a.role)} ${esc(a.name)} <small>${WAR_ROLES[a.role].label} · ${n(S.numbers.points[a.role])}점</small></div>
    <div class="wr-cards">${a.cards.map(o => { const c = warCard({ uid: 'x', ...o, hp: null }, card), p = !c ? 0 : o.hp == null ? 100 : Math.min(100, o.hp / c.HP * 100);
      return `<span class="rd-th ${p <= 0 ? 'dead' : ''}"><img src="${IMG}${o.id}.webp" alt="" onerror="this.remove()"><i class="wr-hpb"><b style="width:${p}%"></b></i></span>`; }).join('')}</div>
    ${a.decks > 1 ? `<small class="rd-note">방어 덱 ${a.deck}/${a.decks}</small>` : ''}
    ${foe ? `<div class="rd-mode">${modeToggle()}</div><div class="wr-pick">${[1, 2].map(k => `<button data-go="${k}" ${can && has(k) && atk[k]?.alive !== 0 ? '' : 'disabled'}>${gi('role_officer', '⚔️')} 공격 덱 ${k}<small>${!has(k) ? '없음' : atk[k] ? `${atk[k].alive}장 생존` : '처음'}</small></button>`).join('')}</div>` : ''}
    ${foe && !can && !a.destroyed ? `<small class="rd-note">${mt.ended ? '경기 끝' : S.phase !== 'live' ? '전투 시간 09:00~23:00' : !mt.me.alive ? '내 아지트가 무너졌어요' : !mt.me.attacks_left ? '오늘 공격 5회 끝' : '방어조 5곳을 먼저 무너뜨리세요'}</small>` : ''}`);
  bindMode(m); m.querySelectorAll('[data-go]').forEach(b => b.onclick = () => { m.remove(); attack(slot, +b.dataset.go); });
}
async function attack(slot, deck) {
  let st; try { st = await rpc('war_start', { p_slot: slot, p_deck: deck }); } catch (er) { toast(errText(er)); return reload(); }
  const A = warDeck(st.atk, card, st.atk_buff), B = warDeck(st.def, card, st.def_buff), log = [], t0 = Date.now();
  // 전투 화면 = 스토리·탑과 같은 화면 (js/game.js TCG.viewBattle). 배경 war_bg. 수동이면 행동 기록을 war_log 로 남김 (tools/war_verify.mjs 재생 검증)
  const V = window.TCG?.viewBattle, manual = battleMode() === 'manual' && !!V, aiName = `${S.match?.enemy?.find(x => x.slot === slot)?.name || '아지트'}`;
  let res;
  if (V) {
    const ses = warSession(A, B, st.seed, log, { view: true, manual: true });
    const feed = manual ? ses : { events: ses.events, next: inp => { let x = ses.next(inp); while (!x.done && x.value.ask) x = ses.next({ k: 'auto' }); return x; } };
    res = await V({ session: feed, aiName, manual, maxTurns: 40, bg: 'war', title: `🏴 구역 전쟁 · ${aiName}` });
    if (manual) { try { await rpc('war_log', { p_id: st.id, p_actions: ses.acts }); } catch (er) { toast(errText(er)); } }
  } else { res = runWar(A, B, st.seed, log); await playback(res, log, t0); }
  let fin = null;
  for (let i = 0; i < 3 && !fin; i++) { try { fin = await rpc('war_finish', { p_id: st.id, p_win: res.win, p_atk_hp: res.aHp, p_def_hp: res.bHp }); } catch (er) { if (/too fast/.test(er.message)) await new Promise(r => setTimeout(r, 1500)); else { toast(errText(er)); break; } } }
  if (fin) { S = fin; const r = fin.result || {};
    pop(`<div class="rd-res"><b class="${r.win ? '' : 'lose'}">${r.boss_kill ? (gi('role_boss', '👑') + ' 보스 격파!') : r.destroyed ? (gi('fx_destroy', '💥') + ' 아지트 파괴') : r.next_deck ? '🛡️ 1번 덱 격파' : r.win ? '승리' : '패배'}</b>${r.points ? `<div class="rd-clr">+${n(r.points)}점</div>` : ''}${r.next_deck ? '<small>2번 방어 덱이 나타났어요</small>' : ''}${r.expired ? '<small>시간이 지나 무효</small>' : ''}</div><button class="gd-big" data-x>확인</button>`, 'rd-r');
  } else await reload();
  paint();
}
async function claim(e) {
  e.currentTarget.disabled = true;
  try { S = await rpc('war_claim'); const g = S.got || {}; toast(`받음 ${rwTxt(g).replace(/<img[^>]*alt="([^"]*)"[^>]*>/g, '$1').replace(/<[^>]+>/g, ' ')}${g.rank ? ` · 시즌 ${g.rank}위` : ''}`); window.VRPlayer?.wallet?.(true); window.VRGem?.status?.(true); } catch (er) { toast(errText(er)); }
  paint();
}
// ---- 덱: 방어 1·2 (시즌 중 잠김) · 공격 1·2 ----
async function deckPop() {
  const m = pop('<div class="gd-loading">…</div>', 'wide');
  let list = window.__WAR_MOCK_DECKS;
  if (!list) { const sum = await window.VRStory?.summary?.(); if (!sum?.ok) { m.remove(); return toast('스토리 인재가 필요해요'); }
    const by = new Map(sum.owned.map(o => [o.uid, o])), uniq = u => { const seen = new Set(); return u.map(x => by.get(x)).filter(o => o && !seen.has(o.id) && seen.add(o.id)).slice(0, 5); };
    list = [{ key: 'top', name: '⚡ 전투력 상위', cards: uniq(sum.owned.slice().sort((a, b) => b.power - a.power).map(o => o.uid)) }, ...sum.decks.map((d, i) => ({ key: 'd' + i, name: d.name, cards: uniq(d.uids) })).filter(d => d.cards.length)]; }
  let pick = 'def1';
  const draw = () => {
    const dk = S.decks || {}, locked = S.entry?.locked && !['soon', 'signup', 'ended'].includes(S.phase);
    const th = sn => (sn || []).map(o => `<span class="rd-th"><img src="${IMG}${o.id}.webp" alt="" onerror="this.remove()"><small>Lv.${o.level}</small></span>`).join('') || '<small class="rd-empty">비어 있음</small>';
    m.querySelector('.gd-pop-panel').innerHTML = `<button class="gd-x" data-x aria-label="닫기">${gi('ic_close', '✕')}</button><div class="rd-pt">${gi('war_deck', '🃏')} 전쟁 덱</div>
      ${['def1', 'def2', 'atk1', 'atk2'].map(k => `<button class="rd-dk wr-dkrow ${pick === k ? 'on' : ''}" data-k="${k}"><b>${k.startsWith('def') ? (gi('war_role_def', '🛡️') + ' 방어') : (gi('war_role_atk', '⚔️') + ' 공격')} ${k.slice(-1)}${k === 'def2' ? '<small>목숨 +1</small>' : ''}</b><span class="rd-ths">${th(dk[k])}</span>${k.startsWith('def') && locked ? '<small>🔒</small>' : ''}</button>`).join('')}
      <div class="rd-h">${pick.startsWith('def') ? (gi('war_role_def', '🛡️') + ' 방어') : (gi('war_role_atk', '⚔️') + ' 공격')} ${pick.slice(-1)} 에 넣을 덱</div>
      ${list.map(d => `<button class="rd-dk" data-use="${d.key}" ${pick.startsWith('def') && locked ? 'disabled' : ''}><b>${esc(d.name)}</b><span class="rd-ths">${th(d.cards)}</span></button>`).join('')}
      <button class="rd-dk" data-use="" ${pick.startsWith('def') && locked ? 'disabled' : ''}><b>비우기</b></button>`;
    m.querySelectorAll('[data-k]').forEach(b => b.onclick = () => { pick = b.dataset.k; draw(); });
    m.querySelectorAll('[data-use]').forEach(b => b.onclick = async () => { const d = list.find(x => x.key === b.dataset.use);
      try { const r = await rpc('war_set_deck', { p_kind: pick, p_uids: d ? d.cards.map(o => o.uid) : [] }); S.decks = r.decks; toast('저장했어요'); } catch (er) { toast(errText(er)); } draw(); });
  };
  draw();
}
function slotPop(slot) {
  const x = S.roster.find(r => r.slot === slot);
  const m = pop(`<div class="rd-pt">${roleIc(x.role)} ${slot}번 · ${WAR_ROLES[x.role].label}</div>
    ${S.members.map(u => `<button class="rd-dk" data-u="${u.user_id}"><b>${esc(u.name)}</b><small>${S.roster.find(r => r.user_id === u.user_id) ? `${S.roster.find(r => r.user_id === u.user_id).slot}번` : ''} ${u.ready ? '🛡️✔' : '덱 없음'}</small></button>`).join('')}
    <button class="rd-dk" data-u=""><b>${gi('war_npc', '🤡')} 비우기 (불량배)</b></button>`);
  m.querySelectorAll('[data-u]').forEach(b => b.onclick = async () => { try { S = await rpc('war_set_slot', { p_slot: slot, p_user: b.dataset.u || null }); m.remove(); } catch (er) { toast(errText(er)); } paint(); });
}
// ---- 전투 재생 ----
function playback(res, log, t0) {
  return new Promise(done => {
    let stop = false, timer = 0, i = 0;
    const m = pop('', 'wide rd-pb');
    const end = () => { if (stop) return; stop = true; clearTimeout(timer); setTimeout(() => { m.remove(); done(); }, Math.max(0, 3200 - (Date.now() - t0))); };
    m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) end(); }, true);
    const side = (ros, cls) => `<div class="wr-pb-side ${cls}">${(ros || []).map(r => `<div class="rd-pb-u" data-uid="${r.uid}"><img src="${IMG}${r.id}.webp" alt=""><i><b></b></i></div>`).join('')}</div>`;
    m.querySelector('.gd-pop-panel').innerHTML = `<div class="rd-pb-top"><span>${gi('role_officer', '⚔️')} 아지트 공격</span><small class="rd-pb-t">T1</small><button class="rd-skip" data-skip>SKIP ${gi('ic_skip', '⏭')}</button></div>
      <div class="wr-pb"><img class="rd-bg" src="${UI}war_bg.webp" alt="" onerror="this.remove()">${side(log.roster?.B, 'foe')}<div class="rd-pb-fx"></div>${side(log.roster?.A, 'me')}</div>`;
    m.querySelector('[data-skip]').onclick = e => { e.stopPropagation(); i = log.length; end(); };
    const U = (sd, uid) => m.querySelector(`.wr-pb-side.${sd === 'A' ? 'me' : 'foe'} [data-uid="${uid}"]`);
    const tick = () => {
      if (stop) return;
      if (i >= log.length) { const fx = m.querySelector('.rd-pb-fx'); fx.textContent = res.win ? 'WIN' : 'LOSE'; return end(); }
      const f = log[i++]; m.querySelectorAll('.act').forEach(x => x.classList.remove('act'));
      if (f.k === 'turn') m.querySelector('.rd-pb-t').textContent = `T${f.t}`;
      if (f.u != null) U(f.side, f.u)?.classList.add('act');
      m.querySelector('.rd-pb-fx').textContent = f.k === 'skill' && f.s ? `${gi('fx_skill', '✨')} ${f.s}` : '';
      ['A', 'B'].forEach(k => (log.roster?.[k] || []).forEach(r => { const el = U(k, r.uid); if (!el) return; const hp = f[k]?.[r.uid] ?? 0; el.querySelector('b').style.width = `${Math.max(0, Math.min(100, hp / r.max * 100))}%`; el.classList.toggle('dead', hp <= 0); }));
      timer = setTimeout(tick, f.k === 'turn' ? 160 : 300);
    };
    tick();
  });
}
window.VRWar = { open, claimable: () => rpc('war_claimable').catch(() => 0) };
