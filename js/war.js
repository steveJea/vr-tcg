// ===== 조직 전쟁 「구역 전쟁」 화면 =====
// 서버: security_phase4_raid_guildwar.sql + guildbattle-verify-v4. 승패·HP·점수는 서버 재생만.
// 그림: img/ui/guild/war_banner.webp · war_bg.webp · war_icon.webp · war_role_<def|atk|mid|boss|etc>.webp · war_ajit.webp · war_npc.webp (없으면 이모지). 카드는 IMG
import { startVerified,finishVerified,recoverVerified } from './guildbattle-session.js';
import { runWar, warSession, warDeck, warCard, WAR_ROLES } from './war-core.js';
import { WAR_DECKS, deckLabel, pairedDeck, deckLock, pickPool, draftProblem } from './war-deck-controls.js';
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
const ERR = { 'reward verification pending': '지급 보류', 'not in guild': '조직에 들어가야 해요', 'not allowed': '권한이 없어요', 'signup closed': '신청 기간이 아니에요', 'need members': '조직원 10명 이상 필요해요', 'not entered': '이번 시즌 참가 명단에 없어요 (조직 레벨 3부터 자동 참가)', 'roster locked': '시즌 중엔 아지트(14번)만 바꿀 수 있어요', 'battle hours': '전투 시간(09~23시)에는 배치를 바꿀 수 없어요',
  'defense locked': '방어 덱은 시즌 중 못 바꿔요', 'same card': '1·2번 덱에 같은 인재는 안 돼요', 'card not owned': '덱 인재를 다시 골라 주세요', 'duplicate card': '같은 인재는 한 명만', 'deck size': '덱은 1~5장',
  'not battle time': '전투 시간은 09:00~23:00', 'no match': '오늘 경기가 없어요', 'match ended': '오늘 경기는 끝났어요', 'not in roster': '전쟁 명단에 없어요', 'ajit destroyed': '내 아지트가 무너져 공격할 수 없어요',
  'no attacks': '오늘 공격 5회를 다 썼어요', 'already destroyed': '이미 무너진 아지트', 'target busy': '다른 조직원이 공격 중', 'defense first': '방어조 5곳을 먼저 무너뜨리세요', 'no attack deck': '공격 덱을 먼저 정하세요',
  'deck dead': '이 공격 덱은 모두 쓰러졌어요', 'bad slot': '없는 칸이에요', 'no battle': '전투 기록을 찾을 수 없어요', 'already finished': '이미 끝난 전투예요', 'not member': '우리 조직원이 아니에요 (탈퇴했을 수 있어요)', 'bad deck': '덱 종류가 잘못됐어요', 'not found': '전투 기록을 찾을 수 없어요',
  'already logged': '이미 기록된 전투예요', 'bad actions': '전투 기록이 올바르지 않아요', 'already reported': '이미 끝난 전투예요', 'too fast': '잠시 후 다시', 'nothing to claim': '받을 보상이 없어요', 'login required': '로그인이 필요해요' };
/** 신청 기간 안내: 시즌 첫날(season) 기준 signup_days_before 일 전 0시 ~ 첫날 open_hour 시 (서버 _war_phase 와 같은 계산, KST) */
const WD = ['일', '월', '화', '수', '목', '금', '토'];
function signupWindow(s) {
  const d0 = new Date(`${s.season}T00:00:00Z`); if (isNaN(d0)) return '';
  const before = +(s.numbers?.signup_days_before ?? 3), oh = +(s.numbers?.open_hour ?? 9);
  const a = new Date(d0.getTime() - before * 864e5), f = d => `${d.getUTCMonth() + 1}/${d.getUTCDate()}(${WD[d.getUTCDay()]})`;
  return `신청 기간: ${f(a)} 0시 ~ ${f(d0)} 오전 ${oh}시`;
}
/** 칸 배치가 잠긴 이유 (없으면 ''). 자동 참가(조직 Lv.3+) · 잠금 전 모든 칸 · 잠금 뒤 아지트(14)만, 전투 시간 제외 (war_auto.sql) */
const minLv = () => +(X.min_level ?? 3);
function slotLockReason(s, slot) {
  if (!s.entry) return X.guild_level != null && X.guild_level < minLv() ? `조직 레벨 ${minLv()}부터 자동 참가해요 (지금 Lv.${X.guild_level})` : '이번 시즌 참가 명단을 준비 중이에요';
  if (s.guild?.role !== 'boss') return '보스만 배치할 수 있어요';
  if (!s.entry.locked) return '';
  if (s.phase === 'live') return '전투 시간(09~23시)에는 배치를 바꿀 수 없어요';
  return slot === 14 ? '' : '시즌 중엔 아지트(14번)만 바꿀 수 있어요 · 다음 경기부터 적용';
}
const canSlot = (s, slot) => !slotLockReason(s, slot);
const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
async function rpc(name, args) {
  const m = window.__WAR_MOCK; if (m) return m(name, args);
  const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) throw new Error('login required');
  const { data, error } = await sb.rpc(name, args); if (error) throw new Error(error.message); return data;
}
function toast(t) { const el = document.createElement('div'); el.className = 'gd-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2400); }
// Every transient war window belongs to this page, never to a polling timer.
const overlays = new Set();
let pageVersion = 0, pageAccount = '', detailOwner = null;
const context = () => ({root:M,version:pageVersion,uid:pageAccount});
const samePage = c => c.root===M && c.version===pageVersion && c.uid===(window.VRCloud?.user?.id||'');
const visiblePage = c => samePage(c) && c.root?.isConnected && (!c.root.classList.contains('vr-in-page') || window.VRPages?.current==='war');
function closeChildren() {
 for(const m of [...overlays]) m.remove();
 if(detailOwner) {window.TCG?.closeDetail?.();window.TCG?.closeZoom?.();detailOwner=null;}
}
function pop(html, cls = '', owner = M) {
 const m=document.createElement('div');m.className='gd-pop wr-pop';
 m.setAttribute('role','dialog');m.setAttribute('aria-modal','true');
 m.innerHTML=`<div class="gd-pop-panel ${cls}"><button class="gd-x" data-x aria-label="닫기">${gi('ic_close','✕')}</button>${html}</div>`;
 document.body.appendChild(m);
 const remove=m.remove.bind(m);m.remove=()=>{overlays.delete(m);if(!owner)closeChildren();remove();};
 if(owner){overlays.add(m);m.dataset.warOverlay='';}
 m.addEventListener('click',e=>{if((e.target===m&&!m.classList.contains('vr-in-page'))||e.target.closest('[data-x]'))m.remove();});
 return m;
}
const snapshotOf = o => o.snapshot || o;
function inspectCard(o, role=null) {
 const c=context();if(!visiblePage(c))return;
 const snap=snapshotOf(o), r=S.numbers?.roles?.[role]||WAR_ROLES[role]||{};
 // No guessed EX/gear stats on an older SQL installation: show base catalog info.
 const full=o.snapshot||Object.hasOwn(o,'boost')||Object.hasOwn(o,'ex');
 const view=full?warCard({...snap,uid:'public-card',hp:null},card,{atk:['mid','boss'].includes(role)?r.atk:1,def:r.def||1}):card(o.id);
 if(!view)return;
 window.TCG?.showCardInfo?.(view,{power:true,level:full?(snap.level||1):1,hp:full?o.hp:undefined});detailOwner=c.root;
}
function bindCardInfo(root, list, attr='card', role=null) {
 root.querySelectorAll(`[data-${attr}]`).forEach(b=>b.onclick=e=>{e.stopPropagation();const o=list[+b.dataset[attr]];if(o)inspectCard(o,role);});
}
const roleIc = r => `<span class="wr-ric"><img src="${UI}war_role_${r}.webp" alt="" onerror="this.remove()"><i>${WAR_ROLES[r].icon}</i></span>`;
const D = d => { const x = new Date(d + 'T00:00:00+09:00'); return `${x.getMonth() + 1}/${x.getDate()}`; };
const PH = { soon: '시즌 준비 (배치 가능)', signup: '배치 기간', live: '전투 중', rest: '휴전', ended: '시즌 종료' };
// 아지트 HP % (카드 스냅샷 기준)
const hpPct = cards => { let a = 0, b = 0; for (const o of cards || []) { const c = warCard({ ...snapshotOf(o), uid: 'x', hp: null }, card); if (!c) continue; b += c.HP; a += o.hp == null ? c.HP : Math.min(c.HP, +o.hp); } return b ? a / b * 100 : 0; };

let S = null, M = null, tab = 'enemy', U = { signed: [], me_signed: false, cards: {} };
/** 리더 얼굴 (war_ui · guild4_ui.sql). 없으면 덱 첫 인재 */
const face = (uid, fb) => { const id = (uid && U.cards?.[uid]) || fb; return id ? `${IMG}${id}.webp` : ''; };
let X = {};   // war_meta: 조직 레벨 · 내 전쟁 덱 비었는지
async function readUi() {
 const [u,x]=await Promise.all([rpc('war_ui').catch(()=>null),rpc('war_meta').catch(()=>null)]);
 return {u,x};
}
function setUi({u,x}) {if(u?.ok)U=u;if(x?.ok)X=x;}
let recovering=null;
async function recoverPage(c) {
 if(!S||!visiblePage(c)||recovering===c.root)return;recovering=c.root;
 try{const r=await recoverVerified('war');if(r&&samePage(c)){await reload(c);if(visiblePage(c))showVerifiedResult(r);}}
 catch(e){if(visiblePage(c))toast(errText(e));}finally{if(recovering===c.root)recovering=null;}
}
export async function open() {
    if (window.VRUnlocks && !window.VRUnlocks.guard('war')) return;
 M?.remove();closeChildren();pageVersion++;pageAccount=window.VRCloud?.user?.id||'';S=null;
 M=pop('<div class="gd-loading">…</div>','wide wr',null);
 const c=context();window.VRSound?.scope?.(M,window.VR_BGM?.guildHome);
 window.VRPages?.host?.('war','🏴 구역 전쟁',M,closeChildren,()=>{paint();void recoverPage(c);});
 await reload(c);await recoverPage(c);
}
async function reload(c=context()) {
 if(!samePage(c))return;
 try{const [s,ui]=await Promise.all([rpc('war_status'),readUi()]);if(!samePage(c))return;S=s;setUi(ui);paint();}
 catch(e){if(visiblePage(c))toast(errText(e));}
}
function paint() {
  if (!S || !visiblePage(context())) return;
  const s = S, mt = s.match, e = s.entry;
  const top = `<button class="gd-x" data-x aria-label="닫기">${gi('ic_close', '✕')}</button>
    <div class="wr-hero"><img class="rd-bg" src="${UI}war_banner.webp" alt="" onerror="this.remove()"><span class="wr-hfb">🏴</span>
      <div class="wr-hero-t"><b>구역 전쟁</b><small>${D(s.season)} ~ ${D(s.season_end)} · ${PH[s.phase]}${s.day ? ` · ${s.day}일차` : ''}</small></div>
      <button class="vh-q wr-q" type="button" aria-label="도움말" onclick="window.VRHelp&&VRHelp.open('war')">?</button><button class="wr-mydeck" data-decks>${gi('war_deck', '🃏')} 내 덱${X.need_deck ? '<i class="gd-dot wr-dot"></i>' : ''}</button></div>
    ${s.guild && X.need_deck ? `<button class="wr-needdeck" data-decks><i class="gd-dot wr-dot"></i>${gi('war_deck', '🃏')} 전쟁 덱 편성하기</button>` : ''}
    ${s.guild && e?.locked && s.guild.role === 'boss' && s.phase !== 'live' && mt ? `<button class="wr-wd wr-ajit14" data-slot="14">${gi('role_boss', '👑')} 아지트(14번) 배치 바꾸기</button>` : ''}
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
  q('[data-decks]').forEach(b => b.onclick = () => deckPop());
  q('[data-claim]').forEach(b => b.onclick = claim);
  q('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; paint(); });
  q('[data-aj]').forEach(b => b.onclick = () => ajitPop(+b.dataset.aj, b.dataset.foe === '1'));
  q('[data-auto]').forEach(b => b.onclick = async () => { const c=context(); if (!await window.VRAsk('전투력 순으로 다시 배치할까요?\n아지트 → 방어조 → 공격조 → 중간 → 나머지')) return; if(!visiblePage(c))return; b.disabled = true; try { const next=await rpc('war_auto_assign');if(!samePage(c))return;S=next;if(visiblePage(c))toast('자동 배치 완료'); } catch (er) { if(visiblePage(c))toast(errText(er)); } const ui=await readUi();if(samePage(c)){setUi(ui);paint();} });
  q('[data-slot]').forEach(b => b.onclick = () => slotPop(+b.dataset.slot));
}
function signupView() {
  const s = S, e = s.entry, boss = s.guild.role === 'boss';
  if (!e) return `<div class="wr-sign"><div>${gi('war_icon', '🏴')} 조직원 ${s.guild.members}명</div></div><small class="rd-note wr-lock-why">${esc(slotLockReason(s))}</small>${rankView()}`;
  const slot = x => `<button class="wr-slot ${x.user_id ? '' : 'empty'}${x.slot === 14 ? ' ajit' : ''}" data-slot="${x.slot}" ${canSlot(s, x.slot) ? '' : 'disabled'}><span class="wr-face">${x.user_id && face(x.user_id) ? `<img src="${face(x.user_id)}" alt="" loading="lazy" onerror="this.remove()">` : `<i>${x.user_id ? '👤' : gi('war_npc', '🤡')}</i>`}${x.user_id && !x.ready ? '<em class="wr-nodeck">!</em>' : ''}</span><b>${x.user_id ? esc(x.name || '조직원') : '불량배'}</b></button>`;
  const groups = ROLE_ORDER.map(r => `<div class="wr-row r-${r}"><div class="wr-slots ${r}">${s.roster.filter(x => x.role === r).map(slot).join('')}</div></div>`).join('');
  const why = slotLockReason(s), why14 = why && slotLockReason(s, 14);
  const note = why14 || why;
  return `<div class="wr-sign"><div>${gi('ic_check', '✅')} 자동 참가 · 조직원 ${s.guild.members}명${e.locked ? ' · ' + gi('ic_lock', '🔒') : ''}</div>${boss && !e.locked ? '<button class="gd-big" data-auto>⚡ 자동 배치 (전투력 순)</button>' : ''}</div><small class="rd-note">빈 칸은 동네 불량배가 지켜요 · 안 넣은 조직원은 시즌 시작 때 전투력 순으로 들어가요</small>${note ? `<small class="rd-note wr-lock-why">🔒 ${esc(note)}</small>` : ''}${groups}`;
}
const roleBuff = r => { const x = WAR_ROLES[r], t = []; if (x.atk > 1 && x.def > 1) t.push(`공방 +${Math.round((x.atk - 1) * 100)}%`); else { if (x.atk > 1) t.push(`공격 +${Math.round((x.atk - 1) * 100)}%`); if (x.def > 1) t.push(`방어 +${Math.round((x.def - 1) * 100)}%`); } return `${t.join(' ')} · ${n(S.numbers.points[r])}점`; };
function mapView(list, foe) {
  const gate = S.match.gate_open;
  return ROLE_ORDER.map(r => `<div class="wr-row r-${r}"><div class="wr-ajs ${r}">${list.filter(a => a.role === r).map(a => {
    const lead = a.cards[0], p = a.destroyed ? 0 : hpPct(a.cards), lock = foe && r !== 'def' && !gate, src = a.npc && !a.user_id ? face(null, lead?.id) : face(a.user_id, lead?.id);
    return `<button class="wr-aj ${a.destroyed ? 'dead' : ''} ${lock ? 'lock' : ''} ${a.locked ? 'busy' : ''}" data-aj="${a.slot}" data-foe="${foe ? 1 : 0}">
      <span class="wr-face">${src ? `<img src="${src}" alt="" loading="lazy" onerror="this.remove()">` : ''}${a.npc ? `<span class="wr-npc">${gi('war_npc', '🤡')}</span>` : ''}${a.decks > 1 ? `<em class="wr-dk">${a.deck}/${a.decks}</em>` : ''}${a.destroyed ? `<span class="wr-x">${gi('fx_destroy', '💥')}</span>` : lock ? `<span class="wr-x">${gi('ic_lock', '🔒')}</span>` : a.locked ? `<span class="wr-x">${gi('role_officer', '⚔️')}</span>` : ''}</span>
      <i class="wr-hpb"><b style="width:${p}%"></b></i><small>${esc(a.name)}</small></button>`; }).join('')}</div></div>`).join('');
}
function rankView() {
  const st = S.standings || [];
  return `<div class="rd-h">시즌 순위 <small>승 ${S.numbers.standings.win} · 무 ${S.numbers.standings.draw} · 보스 격파 +${S.numbers.standings.boss_bonus}</small></div>
    <div class="rd-rk">${st.length ? st.map(x => `<div class="${x.me ? 'me' : ''}"><b>${[gi('rank_1', '🥇'), gi('rank_2', '🥈'), gi('rank_3', '🥉')][x.rank - 1] || x.rank}</b><span>${esc(x.name)}</span><small>${x.wins}승 ${x.draws}무 ${x.losses}패</small><em>${x.points}점</em></div>`).join('') : '<div class="rd-empty">아직 참가한 조직이 없어요</div>'}</div>
    <div class="rd-h">시즌 보상</div><table class="rd-tb">${S.numbers.season_rank.map(r => `<tr><th>${r.from === r.to ? `${r.from}위` : `${r.from}~${r.to}위`}</th><td>${rwTxt(r.reward)}</td></tr>`).join('')}
      <tr><th>참가 조직원</th><td>${rwTxt(S.numbers.season_member)} <small>(순위 보상에 더해서)</small></td></tr><tr><th>경기 승리</th><td>${rwTxt(S.numbers.match_win)} · 보스 격파 +${rwTxt(S.numbers.match_boss_kill)}</td></tr><tr><th>무승부</th><td>${rwTxt(S.numbers.match_draw)}</td></tr><tr><th>패배</th><td>${rwTxt(S.numbers.match_loss)}</td></tr></table>`;
}
function ajitPop(slot, foe) {
  if(!visiblePage(context()))return;
  const mt = S.match, a = (foe ? mt.enemy : mt.mine).find(x => x.slot === slot); if (!a) return;
  const can = foe && !mt.ended && !a.destroyed && S.phase === 'live' && mt.me.alive && mt.me.attacks_left > 0 && (a.role === 'def' || mt.gate_open);
  const atk = mt.me.atk || {}, has = k => !!S.decks?.['atk'+k]?.length || !!atk[k];
  const m = pop(`<div class="rd-pt">${roleIc(a.role)} ${esc(a.name)} <small>${WAR_ROLES[a.role].label} · ${n(S.numbers.points[a.role])}점</small></div>
    <div class="wr-cards">${a.cards.map(o => { const c = warCard({ ...snapshotOf(o), uid: 'x', hp: null }, card), p = !c ? 0 : o.hp == null ? 100 : Math.min(100, o.hp / c.HP * 100);
      return `<button type="button" class="rd-th ${p <= 0 ? 'dead' : ''}" data-card="${a.cards.indexOf(o)}" aria-label="${esc(card(o.id)?.name||o.id)} 상세"><img src="${cardThumb(o.id)}" alt="" onerror="this.remove()"><i class="wr-hpb"><b style="width:${p}%"></b></i></button>`; }).join('')}</div>
    ${a.decks > 1 ? `<small class="rd-note">방어 덱 ${a.deck}/${a.decks}</small>` : ''}
    ${foe ? `<div class="rd-mode">${modeToggle()}</div><div class="wr-pick">${[1,2].map(k=>!has(k)?`<button type="button" data-compose="atk${k}">＋ 공격 덱 ${k} 편성</button>`:`<button data-go="${k}" ${can&&atk[k]?.alive!==0?'':'disabled'}>${gi('role_officer','⚔️')} 공격 덱 ${k}<small>${atk[k]?`${atk[k].alive}장 생존`:'출전'}</small></button>`).join('')}</div>` : ''}
    ${foe && !can && !a.destroyed ? `<small class="rd-note">${mt.ended ? '경기 끝' : S.phase !== 'live' ? '전투 시간 09:00~23:00' : !mt.me.alive ? '내 아지트가 무너졌어요' : !mt.me.attacks_left ? '오늘 공격 5회 끝' : '방어조 5곳을 먼저 무너뜨리세요'}</small>` : ''}`);
  bindCardInfo(m,a.cards,'card',a.role);
  m.querySelectorAll('[data-compose]').forEach(b=>b.onclick=()=>{m.remove();const c=context(),mid=mt.id;deckPop(b.dataset.compose,()=>{if(visiblePage(c)&&S.match?.id===mid)ajitPop(slot,foe);});});
  bindMode(m); m.querySelectorAll('[data-go]').forEach(b => b.onclick = () => { m.remove(); attack(slot, +b.dataset.go); });
}
async function attack(slot, deck) {
  const c=context();if(!visiblePage(c))return;
  let st; try { st = await startVerified('war', { slot, deck }, window.TCG?.viewBattle ? 'actions' : 'auto'); } catch (er) { if(visiblePage(c))toast(errText(er)); return reload(c); }
  if(!visiblePage(c))return;
  const A = warDeck(st.atk, card, st.atk_buff), B = warDeck(st.def, card, st.def_buff), log = [], t0 = Date.now();
  // 전투 화면 = 스토리·탑과 같은 화면 (js/game.js TCG.viewBattle). 배경 war_bg. 수동이면 행동 의도를 서버에서 재생
  const V = window.TCG?.viewBattle, manual = battleMode() === 'manual' && !!V, aiName = `${S.match?.enemy?.find(x => x.slot === slot)?.name || '아지트'}`;
  let res, actions=null;
  if (V) {
    const ses = warSession(A, B, st.seed, log, { view: true, manual: true });
    // AUTO 도 실제 판 (AUTO 로 시작, 버튼으로 PLAY 전환 가능). 화면 결과를 신뢰하지 않고 행동 의도만 서버에 전송
    res = await V({ session: ses, aiName, manual: true, auto: !manual, maxTurns: 40, bg: 'war', music: window.VR_BGM?.guildBattle, title: `🏴 구역 전쟁 · ${aiName}` });
    actions=ses.acts;
  } else { res = runWar(A, B, st.seed, log); await playback(res, log, t0); }
  try {const r=await finishVerified('war',st,actions);await reload(c);if(visiblePage(c))showVerifiedResult(r);}catch(er){if(visiblePage(c))toast('결과 미정산 · '+errText(er));}
  paint();
}
function showVerifiedResult(r) {
    if(!visiblePage(context()))return;
    pop(`<div class="rd-res"><b class="${r.win ? '' : 'lose'}">${r.expired ? '무효' : r.boss_kill ? (gi('role_boss', '👑') + ' 보스 격파!') : r.destroyed ? (gi('fx_destroy', '💥') + ' 아지트 파괴') : r.next_deck ? '🛡️ 1번 덱 격파' : r.win ? '승리' : '패배'}</b>${r.points ? `<div class="rd-clr">+${n(r.points)}점</div>` : ''}${r.next_deck ? '<small>2번 방어 덱이 나타났어요</small>' : ''}</div><button class="gd-big" data-x>확인</button>`, 'rd-r');
}
async function claim(e) {
  const c=context();if(!visiblePage(c))return;
  e.currentTarget.disabled = true;
  try { const next = await rpc('war_claim');if(!samePage(c))return;S=next; const g = S.got || {}; toast(`받음 ${rwTxt(g).replace(/<img[^>]*alt="([^"]*)"[^>]*>/g, '$1').replace(/<[^>]+>/g, ' ')}${g.rank ? ` · 시즌 ${g.rank}위` : ''}`); window.VRPlayer?.wallet?.(true); window.VRGem?.status?.(true); } catch (er) { toast(errText(er)); }
  paint();
}
// ---- Four registered war slots → direct owned-card selection → explicit save. ----
async function deckPop(initial=null, resume=null) {
 const c=context();if(!visiblePage(c))return;
 // One deck window only, even after repeated taps while summary is loading.
 for(const x of [...overlays])if(x.dataset.warDeck!==undefined)x.remove();
 const m=pop('<div class="gd-loading">…</div>','wide wr-decks');m.dataset.warDeck='';
 let summary;
 try{summary=await window.VRStory?.summary?.();}catch(e){if(m.isConnected&&visiblePage(c))toast(errText(e));m.remove();return;}
 if(!m.isConnected||!visiblePage(c)){m.remove();return;}
 if(!summary?.ok){m.remove();toast('스토리 인재가 필요해요');return;}
 const owned=summary.owned||[], byUid=new Map(owned.map(o=>[o.uid,o]));
 let kind=WAR_DECKS.includes(initial)?initial:null, selected=[], busy=false, query='',cap='',sort='power';
 const finish=()=>{m.remove();if(visiblePage(c))resume?.();};
 const start=k=>{kind=k;selected=(S.decks?.[k]||[]).map(o=>o.uid).filter(u=>byUid.has(u));query='';cap='';draw();};
 const thumbs=(sn,k)=>(sn||[]).map((o,i)=>`<button type="button" class="rd-th" data-info-slot="${k}" data-info-index="${i}" aria-label="${esc(card(o.id)?.name||o.id)} 상세"><img src="${cardThumb(o.id)}" alt=""><small>Lv.${o.level||1}</small></button>`).join('');
 async function save(uids,k=kind) {
  if(busy||!visiblePage(c)||!m.isConnected)return;
  const lock=deckLock(S,k,c.uid);if(lock)return toast(lock);
  const problem=uids.length?draftProblem(uids,owned,S.decks?.[pairedDeck(k)]||[]):k.endsWith('1')?'기본 덱은 인재를 선택하세요':'';
  if(problem)return toast(problem);
  busy=true;draw();
  try{const r=await rpc('war_set_deck',{p_kind:k,p_uids:uids});if(!samePage(c))return;S.decks=r.decks;
   await reload(c);if(!m.isConnected||!visiblePage(c))return;
   toast(uids.length?'저장했어요':'덱을 해제했어요');if(resume){finish();return;}kind=null;
  }catch(e){if(m.isConnected&&visiblePage(c))toast(errText(e));}
  finally{busy=false;if(m.isConnected&&visiblePage(c))draw();}
 }
 function drawPool() {
  const grid=m.querySelector('.wr-owned');if(!grid)return;
  const paired=new Set((S.decks?.[pairedDeck(kind)]||[]).map(o=>String(o.id))), lock=deckLock(S,kind,c.uid);
  const list=pickPool(owned,selected,card,query,cap,sort);
  grid.innerHTML=list.map(o=>{const on=selected.includes(o.uid), blocked=paired.has(String(o.id));return `<article class="wr-owned-card ${on?'on':''}"><button type="button" data-pick="${esc(o.uid)}" aria-pressed="${on}" ${lock||blocked||busy?'disabled':''} title="${esc(blocked?deckLabel(pairedDeck(kind))+' 사용 중':o.name||card(o.id)?.name||o.id)}"><img src="${cardThumb(o.id)}" alt="" loading="lazy"><b>${esc(o.name||card(o.id)?.name||o.id)}</b><span>Lv.${o.level||1} · COST ${+card(o.id)?.cost||0}</span>${on?`<i>${selected.indexOf(o.uid)+1}</i>`:blocked?'<i>🔒</i>':''}</button><button type="button" class="wr-card-info" data-own-info="${esc(o.uid)}" aria-label="${esc(o.name||o.id)} 상세">ⓘ</button></article>`;}).join('')||'<div class="rd-empty">인재 없음</div>';
  grid.querySelectorAll('[data-pick]').forEach(b=>b.onclick=()=>{if(busy||deckLock(S,kind,c.uid))return;const uid=b.dataset.pick;if(selected.includes(uid))selected=selected.filter(u=>u!==uid);else if(selected.length<5)selected.push(uid);else return toast('최대 5명');drawPool();});
  grid.querySelectorAll('[data-own-info]').forEach(b=>b.onclick=e=>{e.stopPropagation();if(!visiblePage(c))return;const o=byUid.get(b.dataset.ownInfo),raw=window.VRStory?.save?.owned?.find(x=>x.uid===o?.uid);if(raw){const view=window.VRStory.api?.statsOf?.(raw);if(view){const geared=window.VRGearCore&&window.VRGear?.ready?window.VRGearCore.applyGear(view,window.VRGear.forCard(raw.id),'war'):view;window.TCG?.showCardInfo?.(geared,{power:true,level:raw.level});detailOwner=c.root;return;}}if(o)inspectCard(o);});
  const count=m.querySelector('[data-count]');if(count)count.textContent=`${selected.length}/5`;
  const ok=m.querySelector('[data-save]');if(ok)ok.disabled=busy||!!lock||!!draftProblem(selected,owned,S.decks?.[pairedDeck(kind)]||[]);
 }
 function draw() {
  if(!m.isConnected||!visiblePage(c))return;
  const panel=m.querySelector('.gd-pop-panel');
  if(!kind){
   panel.innerHTML=`<button class="gd-x" data-x aria-label="닫기">${gi('ic_close','✕')}</button><div class="rd-pt">${gi('war_deck','🃏')} 전쟁 덱</div><div class="wr-deck-slots">${WAR_DECKS.map(k=>{const sn=S.decks?.[k]||[],lock=deckLock(S,k,c.uid);return `<section class="wr-deck-slot"><button type="button" class="wr-deck-title" data-edit-kind="${k}" ${busy||lock?'disabled':''} title="${esc(lock||deckLabel(k)+' 편성')}"><b>${deckLabel(k)}</b><span>${lock?'🔒':sn.length?'편성 ›':'＋ 편성'}</span></button><div class="wr-deck-thumbs">${thumbs(sn,k)}</div>${k.endsWith('2')&&sn.length?`<button type="button" class="wr-deck-release" data-release="${k}" ${busy||lock?'disabled':''}>덱 해제</button>`:''}</section>`;}).join('')}</div>`;
   panel.querySelectorAll('[data-edit-kind]').forEach(b=>b.onclick=()=>start(b.dataset.editKind));
   panel.querySelectorAll('[data-info-slot]').forEach(b=>b.onclick=()=>inspectCard(S.decks?.[b.dataset.infoSlot]?.[+b.dataset.infoIndex]));
   panel.querySelectorAll('[data-release]').forEach(b=>b.onclick=async()=>{const k=b.dataset.release;if(busy)return;if(!await window.VRAsk(`${deckLabel(k)}을 해제할까요?`))return;if(m.isConnected&&visiblePage(c))await save([],k);});
  }else{
   const lock=deckLock(S,kind,c.uid);
   panel.innerHTML=`<button class="gd-x" data-x aria-label="닫기">${gi('ic_close','✕')}</button><div class="rd-pt">${deckLabel(kind)} <b data-count></b></div><div class="wr-deck-tools"><input data-search type="search" placeholder="이름 검색" aria-label="인재 이름 검색"><input data-cap type="number" min="0" step="1" placeholder="COST 이하" aria-label="최대 COST"><select data-sort aria-label="인재 정렬"><option value="power">전투력순</option><option value="cost">COST순</option><option value="level">레벨순</option><option value="name">이름순</option></select></div><div class="wr-deck-presets"><button type="button" data-top ${lock||busy?'disabled':''}>전투력 상위 5명</button><select data-preset aria-label="저장 덱 가져오기" ${lock||busy?'disabled':''}><option value="">저장 덱 가져오기</option>${(summary.decks||[]).map((d,i)=>`<option value="${i}">${esc(d.name)}</option>`).join('')}</select></div><div class="wr-owned"></div><div class="wr-deck-actions"><button type="button" data-reset ${lock||busy?'disabled':''}>선택 해제</button><button type="button" data-cancel ${busy?'disabled':''}>취소</button><button type="button" data-save>저장</button></div>`;
   const input=panel.querySelector('[data-search]');input.value=query;const apply=()=>{query=input.value;drawPool();};input.oninput=e=>{if(!e.isComposing)apply();};input.oncompositionend=apply;
   const max=panel.querySelector('[data-cap]');max.value=cap;max.oninput=()=>{cap=max.value;drawPool();};
   const order=panel.querySelector('[data-sort]');order.value=sort;order.onchange=()=>{sort=order.value;drawPool();};
   panel.querySelector('[data-top]').onclick=()=>{const paired=new Set((S.decks?.[pairedDeck(kind)]||[]).map(o=>String(o.id)));selected=pickPool(owned,[],card).filter(o=>!paired.has(String(o.id))).slice(0,5).map(o=>o.uid);drawPool();};
   panel.querySelector('[data-preset]').onchange=e=>{if(e.target.value==='')return;const next=(summary.decks[+e.target.value]?.uids||[]).filter(u=>byUid.has(u)).slice(0,5),problem=draftProblem(next,owned,S.decks?.[pairedDeck(kind)]||[]);if(problem){toast(problem);return;}selected=next;drawPool();};
   panel.querySelector('[data-reset]').onclick=()=>{selected=[];drawPool();};
   panel.querySelector('[data-cancel]').onclick=()=>{if(resume)finish();else{kind=null;draw();}};
   panel.querySelector('[data-save]').onclick=()=>save(selected.slice());drawPool();
  }
 }
 // Top-X is dismissal only: no delayed return navigation or hidden editor polling.
 if(kind)start(kind);else draw();
}
function slotPop(slot) {
  const c=context();if(!visiblePage(c))return;
  const x = S.roster.find(r => r.slot === slot);
  const m = pop(`<div class="rd-pt">${roleIc(x.role)} ${slot}번 · ${WAR_ROLES[x.role].label}</div>
    ${S.members.map(u => `<button class="rd-dk" data-u="${u.user_id}"><b>${esc(u.name)}</b><small>${S.roster.find(r => r.user_id === u.user_id) ? `${S.roster.find(r => r.user_id === u.user_id).slot}번` : ''} ${u.ready ? '🛡️✔' : '덱 없음 (자동 편성)'}</small></button>`).join('')}
    <button class="rd-dk" data-u=""><b>${gi('war_npc', '🤡')} 비우기 (불량배)</b></button>`);
  m.querySelectorAll('[data-u]').forEach(b => b.onclick = async () => {
    if(!visiblePage(c)||!m.isConnected)return;
    m.querySelectorAll('[data-u]').forEach(x => x.disabled = true);
    try { const next = await rpc('war_set_slot', { p_slot: slot, p_user: b.dataset.u || null });if(!samePage(c))return;S=next;m.remove();paint(); }
    catch (er) { if(!visiblePage(c)||!m.isConnected)return;toast(errText(er)); const m2 = String(er?.message || er);
      if (/signup closed|not allowed|not entered|roster locked|battle hours/.test(m2)) { m.remove(); await reload(); }   // 권한·기간이 바뀜 → 닫고 최신 상태로
      else m.querySelectorAll('[data-u]').forEach(x => x.disabled = false); }   // 그 밖(탈퇴한 조직원 등): 팝업 유지, 다른 사람 고르기
  });
}
// ---- 전투 재생 ----
function playback(res, log, t0) {
  return new Promise(done => {
    let stop = false, timer = 0, i = 0;
    const m = pop('', 'wide rd-pb');
    const end = () => { if (stop) return; stop = true; clearTimeout(timer); setTimeout(() => { m.remove(); done(); }, Math.max(0, 3200 - (Date.now() - t0))); };
    m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) end(); }, true);
    const side = (ros, cls) => `<div class="wr-pb-side ${cls}">${(ros || []).map(r => `<div class="rd-pb-u" data-uid="${r.uid}"><img src="${cardThumb(r.id)}" alt=""><i><b></b></i></div>`).join('')}</div>`;
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
window.VRWar = { open, claimable: () => rpc('war_claimable').catch(() => 0),
  dot: () => Promise.all([rpc('war_claimable').catch(() => 0), rpc('war_meta').then(r => !!r?.need_deck).catch(() => false)]).then(([c, d]) => !!c || d) };   // 조직 화면 빨간 점: 보상 or 전쟁 덱 편성하기
