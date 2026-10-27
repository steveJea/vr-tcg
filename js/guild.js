// ===== [조직] (길드) 1단계 — 서버: supabase/guild.sql =====
// 진입: 메인 [조직] 타일 · 마이페이지 조직 카드. 팝업은 모두 바깥을 누르면 닫힘
// 엠블럼: img/ui/guild/e01..e12.webp 가 있으면 자동 사용, 없으면 이모지
// 역할: 보스 👑 · 간부 ⚔️ · 조직원. 개인 재화 충성 🩸 (세력에 기여한 만큼 + , 조직 상점에서 사용)
// 2단계 (guild2.sql): 집결(출석) · 의뢰(일일/주간). 그림: img/ui/guild/rally_banner.webp · img/ui/guild/quest_<이벤트>.webp (없으면 이모지)
(() => {
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const EMB = ['💀', '🌹', '🐦‍⬛', '🦷', '⛓️', '👁️', '🗡️', '🐍', '🕷️', '🔥', '🌙', '🃏'];
  const ROLE = { boss: ['👑', '보스'], officer: ['⚔️', '간부'], member: ['', '조직원'] };
  const MODE = { open: ['🔓', '공개'], approval: ['✋', '승인제'], closed: ['🔒', '초대만'] };
  const SHOP = { ticket: ['🎟️', '소환권'], stamina30: ['🔋', '행동력 30'], gold5k: ['🪙', '골드 5,000'], shard5: ['💠', '조각 ×5'], soul3: ['🔥', '혼 ×3'], frame: ['🖼️', '엠블럼 프레임'] };
  const LOY = '🩸';
  const ERR = { 'level required': '계정 Lv.15부터 창설할 수 있어요', 'not enough gold': '🪙 골드가 부족해요', 'not enough gem': '🔮 심연석이 부족해요', 'bad name': '이름은 한글·영문·숫자 2~8자 (금칙어 불가)',
    'name taken': '이미 있는 이름이에요', 'already in guild': '이미 조직에 있어요', cooldown: '아직 가입할 수 없어요', 'guild full': '정원이 가득 찼어요', closed: '초대로만 가입할 수 있어요',
    'too many requests': '신청은 3곳까지', 'no permission': '권한이 없어요', 'officer slots full': '간부 자리가 가득 찼어요', 'boss must transfer': '보스를 넘긴 뒤에 나갈 수 있어요',
    'kick limit': '오늘은 더 추방할 수 없어요', 'not enough loyalty': `${LOY} 충성이 부족해요`, 'limit reached': '구매 한도에 도달했어요', 'guild level required': '조직 레벨이 부족해요',
    'no such player': '그런 닉네임이 없어요', 'rename cooldown': '이름은 30일에 한 번', 'boss active': '보스가 활동 중이에요', 'not heir': '승계 순서가 아니에요', 'too long': '글자 수가 너무 많아요', 'bad word': '쓸 수 없는 말이 있어요', expired: '만료된 요청이에요' };
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? (k === 'cooldown' ? `⏳ ${m.replace(/.*cooldown until/, '')} 이후 가입 가능` : ERR[k]) : m.slice(0, 60); };
  async function rpc(name, args) {
    const m = window.__GUILD_MOCK; if (m) return m(name, args);
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) throw new Error('login required');
    const { data, error } = await sb.rpc(name, args); if (error) throw new Error(error.message); return data;
  }
  function toast(t) { const el = document.createElement('div'); el.className = 'gd-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2400); }
  const emb = (i, cls = '') => `<span class="gd-emb ${cls}"><i>${EMB[(i || 1) - 1] || '💀'}</i><img src="img/ui/guild/e${String(i || 1).padStart(2, '0')}.webp" alt="" onerror="this.remove()"></span>`;
  let st = null, ov = null;
  async function status() { try { st = await rpc('guild_status'); } catch (e) { st = null; if (!/login/.test(e.message)) console.warn('[guild]', e.message); } return st; }
  /** 공통 팝업 (바깥·✕ 누르면 닫힘). 반환 엘리먼트 */
  function pop(html, cls = '') {
    const m = document.createElement('div'); m.className = 'gd-pop';
    m.innerHTML = `<div class="gd-pop-panel ${cls}"><button class="gd-x" data-x aria-label="닫기">✕</button>${html}</div>`;
    m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-x]')) m.remove(); });
    document.body.appendChild(m); return m;
  }
  async function act(name, args, okMsg) { try { const r = await rpc(name, args); if (okMsg) toast(okMsg); await refresh(); return r || true; } catch (e) { toast(errText(e)); return null; } }
  async function refresh() { await status(); if (ov) paint(); window.dispatchEvent(new Event('vr:guild')); }
  function close() { ov?.remove(); ov = null; }
  async function open() {
    close();
    ov = document.createElement('div'); ov.className = 'gd-ov'; ov.innerHTML = '<div class="gd-page"><div class="gd-loading">…</div></div>';
    ov.addEventListener('click', e => { if (e.target === ov || e.target.closest('[data-close]')) close(); });
    document.body.appendChild(ov);
    await status(); paint();
  }
  const card = g => `<button class="gd-card" data-gid="${g.id}">${emb(g.emblem)}<span class="gd-card-m"><b>${esc(g.name)}</b><small>${esc(g.intro || '')}</small></span><span class="gd-card-r"><b>Lv.${g.level}</b><small>👥 ${g.members}/${g.max_members} ${MODE[g.join_mode]?.[0] || ''}</small></span></button>`;
  function paint() {
    const p = ov?.querySelector('.gd-page'); if (!p) return;
    if (!st) { p.innerHTML = `<button class="gd-x" data-close>✕</button><div class="gd-empty">로그인이 필요해요</div>`; return; }
    if (!st.guild) return paintNone(p);
    paintHome(p);
  }
  // ---- 조직 없음: 초대 · 신청 · 찾기 · 창설 ----
  function paintNone(p) {
    p.innerHTML = `<button class="gd-x" data-close aria-label="닫기">✕</button>
      <div class="gd-hero none"><div class="gd-hero-t">조직</div><small>심연의 도시, 피로 맺은 가족</small></div>
      ${st.invites.length ? `<div class="gd-h">📨 초대</div>${st.invites.map(x => `<div class="gd-req">${card(x.guild)}<span class="gd-req-a"><button class="gd-ok" data-acc="${x.id}">수락</button><button data-rej="${x.id}">거절</button></span></div>`).join('')}` : ''}
      ${st.applies.length ? `<div class="gd-h">⏳ 신청 중</div>${st.applies.map(x => `<div class="gd-req">${card(x.guild)}<span class="gd-req-a"><button data-rej="${x.id}">취소</button></span></div>`).join('')}` : ''}
      <div class="gd-search"><input id="gd-q" maxlength="8" placeholder="🔎 조직 이름"><button id="gd-qgo">찾기</button></div>
      <div class="gd-list" id="gd-list">${st.list.map(card).join('') || '<div class="gd-empty">아직 조직이 없어요. 첫 조직을 세워 보세요</div>'}</div>
      ${st.cooldown ? `<div class="gd-cd">⏳ ${new Date(st.cooldown).toLocaleString('ko-KR', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })} 이후 가입 가능</div>` : ''}
      <button class="gd-create" id="gd-create" ${st.my_level < st.min_level ? 'disabled' : ''}>🩸 조직 창설<small>${st.my_level < st.min_level ? `계정 Lv.${st.min_level}부터` : `🪙${n(st.cost.gold)} 또는 🔮${n(st.cost.gem)}`}</small></button>`;
    p.querySelectorAll('[data-acc]').forEach(b => b.onclick = () => act('guild_respond', { p_req: +b.dataset.acc, p_accept: true }, '🩸 조직에 들어왔어요'));
    p.querySelectorAll('[data-rej]').forEach(b => b.onclick = () => act('guild_respond', { p_req: +b.dataset.rej, p_accept: false }));
    const bindCards = root => root.querySelectorAll('[data-gid]').forEach(b => b.onclick = () => guildPop([...st.list, ...st.invites.map(x => x.guild), ...st.applies.map(x => x.guild), ...(st._found || [])].find(g => g.id === +b.dataset.gid)));
    bindCards(p);
    const go = async () => { try { st._found = await rpc('guild_search', { p_q: p.querySelector('#gd-q').value }); const l = p.querySelector('#gd-list'); l.innerHTML = st._found.map(card).join('') || '<div class="gd-empty">찾는 조직이 없어요</div>'; bindCards(l); } catch (e) { toast(errText(e)); } };
    p.querySelector('#gd-qgo').onclick = go; p.querySelector('#gd-q').onkeydown = e => { if (e.key === 'Enter') go(); };
    p.querySelector('#gd-create').onclick = createPop;
  }
  function guildPop(g) {
    if (!g) return;
    const m = pop(`<div class="gd-gp">${emb(g.emblem, 'huge')}<div class="gd-gp-n">${esc(g.name)}</div><div class="gd-gp-s">Lv.${g.level} · 👥 ${g.members}/${g.max_members} · ${MODE[g.join_mode].join(' ')}</div>
      <div class="gd-gp-i">${esc(g.intro || '')}</div><div class="gd-gp-b">👑 ${esc(g.boss_name || '')}</div>
      ${g.join_mode === 'closed' ? '' : `<button class="gd-big" data-join>${g.join_mode === 'open' ? '🩸 가입' : '✋ 가입 신청'}</button>`}</div>`);
    const j = m.querySelector('[data-join]'); if (j) j.onclick = async () => { j.disabled = true; const r = await act('guild_apply', { p_gid: g.id }); if (r) { toast(r.joined ? '🩸 조직에 들어왔어요' : '✋ 신청했어요'); m.remove(); } else j.disabled = false; };
  }
  function createPop() {
    let e = 1, mode = 'open';
    const m = pop(`<div class="gd-h big">🩸 조직 창설</div>
      <div class="gd-embs">${EMB.map((_, i) => `<button data-e="${i + 1}" class="${i === 0 ? 'on' : ''}">${emb(i + 1)}</button>`).join('')}</div>
      <input id="gd-cn" maxlength="8" placeholder="조직 이름 (2~8자)"><input id="gd-ci" maxlength="60" placeholder="한 줄 소개 (선택)">
      <div class="gd-modes">${Object.entries(MODE).map(([k, [ic, l]]) => `<button data-m="${k}" class="${k === mode ? 'on' : ''}">${ic}<small>${l}</small></button>`).join('')}</div>
      <div class="gd-pay"><button data-pay="gold">🪙 <b>${n(st.cost.gold)}</b></button><button data-pay="gem">🔮 <b>${n(st.cost.gem)}</b></button></div>`, 'wide');
    m.querySelectorAll('[data-e]').forEach(b => b.onclick = () => { e = +b.dataset.e; m.querySelectorAll('[data-e]').forEach(x => x.classList.toggle('on', x === b)); });
    m.querySelectorAll('[data-m]').forEach(b => b.onclick = () => { mode = b.dataset.m; m.querySelectorAll('[data-m]').forEach(x => x.classList.toggle('on', x === b)); });
    m.querySelectorAll('[data-pay]').forEach(b => b.onclick = async () => {
      const name = m.querySelector('#gd-cn').value.trim(); if (!/^[가-힣A-Za-z0-9]{2,8}$/.test(name)) return toast(ERR['bad name']);
      if (!confirm(`${b.dataset.pay === 'gold' ? `🪙 ${n(st.cost.gold)}` : `🔮 ${n(st.cost.gem)}`} 을 써서 [${name}] 을 세울까요?`)) return;
      b.disabled = true;
      const r = await act('guild_create', { p_name: name, p_emblem: e, p_intro: m.querySelector('#gd-ci').value, p_join: mode, p_pay: b.dataset.pay }, `🩸 [${name}] 창설!`);
      if (r) { m.remove(); window.VRPlayer?.wallet?.(true); window.VRGem?.status?.(true); } else b.disabled = false;
    });
  }
  // ---- 조직 홈 ----
  function paintHome(p) {
    const g = st.guild, me = st.me, staff = me.role !== 'member';
    const pct = g.exp_next ? Math.min(100, (g.exp - g.exp_cur) / (g.exp_next - g.exp_cur) * 100) : 100;
    p.innerHTML = `<button class="gd-x" data-close aria-label="닫기">✕</button>
      <div class="gd-hero">${emb(g.emblem, 'huge')}<div class="gd-hero-m"><div class="gd-hero-n">${esc(g.name)}</div><div class="gd-hero-s"><b>Lv.${g.level}</b> · 👥 ${g.members}/${g.max_members} · ${MODE[g.join_mode][0]}</div>
        <div class="gd-bar" title="세력 ${n(g.exp)}${g.exp_next ? ` / ${n(g.exp_next)}` : ''}"><i style="width:${pct.toFixed(1)}%"></i></div><small class="gd-exp">세력 ${n(g.exp)}${g.exp_next ? ` / ${n(g.exp_next)}` : ' · MAX'}</small></div></div>
      ${g.notice ? `<div class="gd-notice">📢 ${esc(g.notice)}</div>` : ''}
      <div class="gd-me"><span>${ROLE[me.role][0]} ${ROLE[me.role][1]}</span><span class="gd-loy">${LOY} <b>${n(st.loyalty)}</b></span><small>오늘 세력 📖${me.today?.story || 0}/100 · ⚔️${me.today?.pvp || 0}/100</small></div>
      <div class="gd-tiles">
        <button data-t="shop"><span>🛒</span>상점</button>
        ${staff ? `<button data-t="req"><span>📨</span>신청${st.requests.length ? `<i class="gd-badge">${st.requests.length}</i>` : ''}</button><button data-t="set"><span>⚙️</span>설정</button>` : ''}
        <button data-t="log"><span>📜</span>기록</button>
        <button data-t="rally"><span>🕯️</span>집결<i class="gd-dot" data-dot="rally" hidden></i></button><button data-t="quest"><span>📜</span>의뢰<i class="gd-dot" data-dot="quest" hidden></i></button>
        <button data-t="raid"><span class="gd-tic"><img src="img/ui/guild/raid_icon.webp" alt="" onerror="this.remove()"><i>🐉</i></span>토벌<i class="gd-dot" data-dot="raid" hidden></i></button>
        <button data-t="war"><span class="gd-tic"><img src="img/ui/guild/war_icon.webp" alt="" onerror="this.remove()"><i>🏴</i></span>전쟁<i class="gd-dot" data-dot="war" hidden></i></button></div>
      <div class="gd-h">👥 조직원</div>
      <div class="gd-mem">${st.members.map(x => `<button class="gd-m r-${x.role}" data-u="${x.user_id}">${x.card ? `<img src="${IMG}${x.card}.webp" alt="" loading="lazy" onerror="this.remove()">` : '<span class="gd-m-no">👤</span>'}
        ${x.role !== 'member' ? `<i class="gd-m-role">${ROLE[x.role][0]}</i>` : ''}<span class="gd-m-n">${esc(x.name)}</span><small>${LOY}${n(x.loyalty_total)}</small></button>`).join('')}</div>
      <div class="gd-foot">${me.can_claim ? '<button data-claim>👑 보스 승계</button>' : ''}<button data-leave>${me.role === 'boss' && g.members <= 1 ? '조직 해산' : '조직 나가기'}</button></div>`;
    p.querySelector('[data-t="shop"]').onclick = shopPop;
    p.querySelector('[data-t="rally"]').onclick = rallyPop;
    p.querySelector('[data-t="quest"]').onclick = questPop;
    p.querySelector('[data-t="raid"]').onclick = () => window.VRRaid?.open();
    p.querySelector('[data-t="war"]').onclick = () => window.VRWar?.open();
    window.VRWar?.claimable().then(c => { const el = p.querySelector('[data-dot="war"]'); if (el) el.hidden = !c; });
    window.VRRaid?.claimable().then(c => { const el = p.querySelector('[data-dot="raid"]'); if (el) el.hidden = !c; });
    rpc('guild_dots').then(d => { if (!d) return; for (const k of ['rally', 'quest']) { const el = p.querySelector(`[data-dot="${k}"]`); if (el) el.hidden = !d[k]; } }).catch(() => {});
    p.querySelector('[data-t="log"]').onclick = logPop;
    p.querySelector('[data-t="req"]')?.addEventListener('click', reqPop);
    p.querySelector('[data-t="set"]')?.addEventListener('click', setPop);
    p.querySelectorAll('[data-u]').forEach(b => b.onclick = () => memberPop(st.members.find(x => x.user_id === b.dataset.u)));
    p.querySelector('[data-claim]')?.addEventListener('click', () => act('guild_claim_boss', {}, '👑 보스가 되었어요'));
    p.querySelector('[data-leave]').onclick = () => { if (confirm(me.role === 'boss' ? '조직을 해산할까요?' : '조직을 나갈까요? 24시간 동안 다른 조직에 들어갈 수 없어요')) act('guild_leave', {}, '조직을 떠났어요'); };
  }
  function memberPop(x) {
    if (!x) return;
    const me = st.me;
    const canKick = (me.role === 'boss' && x.role !== 'boss') || (me.role === 'officer' && x.role === 'member');
    const boss = me.role === 'boss' && x.role !== 'boss';
    const m = pop(`<div class="gd-mp">${x.card ? `<img class="gd-mp-img" src="${IMG}${x.card}.webp" alt="" onerror="this.remove()">` : '<div class="gd-mp-no">👤</div>'}
      <div class="gd-mp-n">${ROLE[x.role][0]} ${esc(x.name)}</div><div class="gd-mp-s">${ROLE[x.role][1]} · ${new Date(x.joined_at).toLocaleDateString('ko-KR')} 가입</div><div class="gd-mp-d">…</div>
      <div class="gd-mp-a">${boss ? `<button data-role="${x.role === 'officer' ? 'member' : 'officer'}">${x.role === 'officer' ? '간부 해제' : '⚔️ 간부 임명'}</button><button data-tr>👑 보스 넘기기</button>` : ''}${canKick ? '<button class="bad" data-kick>추방</button>' : ''}</div></div>`);
    const ago = t => { const h = (Date.now() - new Date(t)) / 36e5; return h < 1 ? '방금' : h < 24 ? `${Math.floor(h)}시간 전` : `${Math.floor(h / 24)}일 전`; };
    rpc('guild_member_info', { p_user: x.user_id }).then(d => { const el = m.querySelector('.gd-mp-d'); if (!el || !d) return;
      el.innerHTML = `<div class="gd-mp-g"><span><small>레벨</small><b>Lv.${d.level}</b></span><span><small>충성 누적</small><b>${LOY}${n(d.loyalty_total)}</b></span><span><small>이번 주</small><b>${LOY}${n(d.loyalty_week)}</b></span>
        <span><small>PvP</small><b>${d.pvp ? `${esc(d.pvp.tier)} ${n(d.pvp.rating)}` : '-'}</b></span><span><small>접속</small><b>${ago(d.seen_at)}</b></span></div>
        ${d.top?.length ? `<div class="gd-mp-top">${d.top.map(c => `<span><img src="${IMG}${c.id}.webp" alt="" loading="lazy" onerror="this.remove()"><small>Lv.${c.level}</small></span>`).join('')}</div>` : ''}`; }).catch(() => { const el = m.querySelector('.gd-mp-d'); if (el) el.remove(); });
    m.querySelector('[data-role]')?.addEventListener('click', async e => { if (await act('guild_set_role', { p_user: x.user_id, p_role: e.currentTarget.dataset.role }, '역할을 바꿨어요')) m.remove(); });
    m.querySelector('[data-tr]')?.addEventListener('click', async () => { if (confirm(`${x.name} 에게 보스를 넘길까요?`) && await act('guild_transfer', { p_user: x.user_id }, '👑 보스를 넘겼어요')) m.remove(); });
    m.querySelector('[data-kick]')?.addEventListener('click', async () => { if (confirm(`${x.name} 을(를) 추방할까요? 72시간 동안 다시 들어올 수 없어요`) && await act('guild_kick', { p_user: x.user_id }, '추방했어요')) m.remove(); });
  }
  function shopPop() {
    const draw = m => { m.querySelector('.gd-shop').innerHTML = st.shop.map(s => { const [ic, l] = SHOP[s.item] || ['🎁', s.item]; const lock = st.guild.level < s.min_level, done = s.left === 0 || s.owned;
      return `<button class="gd-si" data-buy="${s.item}" ${lock || done ? 'disabled' : ''}><span class="gd-si-ic">${ic}</span><b>${l}</b><span class="gd-si-p">${LOY}${n(s.price)}</span>${lock ? `<small class="gd-si-l">🔒 Lv.${s.min_level}</small>` : s.left != null ? `<small class="gd-si-l">${s.owned ? '보유' : s.left}</small>` : ''}</button>`; }).join('');
      m.querySelector('.gd-loy b').textContent = n(st.loyalty);
      m.querySelectorAll('[data-buy]').forEach(b => b.onclick = async () => { b.disabled = true; const r = await act('guild_shop_buy', { p_item: b.dataset.buy }, `${SHOP[b.dataset.buy]?.[0] || ''} 구매 완료`); if (r?.wallet) window.VRPlayer?.setWallet?.(r.wallet); if (m.isConnected) draw(m); }); };
    const m = pop(`<div class="gd-h big">🛒 조직 상점 <span class="gd-loy">${LOY} <b></b></span></div><div class="gd-shop"></div><small class="gd-hint">충성은 스토리·PvP로 조직 세력을 올리면 쌓여요</small>`, 'wide');
    draw(m);
  }
  function reqPop() {
    const m = pop(`<div class="gd-h big">📨 가입 신청</div><div class="gd-reqs">${st.requests.map(r => `<div class="gd-rq"><b>${esc(r.name)}</b><small>Lv.${r.level}</small><button class="gd-ok" data-a="${r.id}">승인</button><button data-r="${r.id}">거절</button></div>`).join('') || '<div class="gd-empty">신청이 없어요</div>'}</div>
      <div class="gd-h">➕ 초대</div><div class="gd-search"><input id="gd-inv" maxlength="20" placeholder="닉네임"><button id="gd-invgo">초대</button></div>`);
    m.querySelectorAll('[data-a]').forEach(b => b.onclick = async () => { if (await act('guild_respond', { p_req: +b.dataset.a, p_accept: true }, '🩸 새 조직원')) b.closest('.gd-rq').remove(); });
    m.querySelectorAll('[data-r]').forEach(b => b.onclick = async () => { if (await act('guild_respond', { p_req: +b.dataset.r, p_accept: false })) b.closest('.gd-rq').remove(); });
    m.querySelector('#gd-invgo').onclick = () => { const v = m.querySelector('#gd-inv').value.trim(); if (v) act('guild_invite', { p_nick: v }, '📨 초대를 보냈어요'); };
  }
  function setPop() {
    const g = st.guild, boss = st.me.role === 'boss'; let e = g.emblem, mode = g.join_mode;
    const m = pop(`<div class="gd-h big">⚙️ 조직 설정</div>
      <label class="gd-l">📢 공지</label><textarea id="gd-sn" maxlength="100" rows="2">${esc(g.notice || '')}</textarea>
      ${boss ? `<label class="gd-l">소개</label><input id="gd-si" maxlength="60" value="${esc(g.intro || '')}">
      <div class="gd-embs">${EMB.map((_, i) => `<button data-e="${i + 1}" class="${i + 1 === e ? 'on' : ''}">${emb(i + 1)}</button>`).join('')}</div>
      <div class="gd-modes">${Object.entries(MODE).map(([k, [ic, l]]) => `<button data-m="${k}" class="${k === mode ? 'on' : ''}">${ic}<small>${l}</small></button>`).join('')}</div>` : ''}
      <button class="gd-big" data-save>저장</button>
      ${boss ? `<div class="gd-rename"><input id="gd-rn" maxlength="8" placeholder="새 이름"><button data-rn>이름 변경 🔮500</button></div>` : ''}`, 'wide');
    m.querySelectorAll('[data-e]').forEach(b => b.onclick = () => { e = +b.dataset.e; m.querySelectorAll('[data-e]').forEach(x => x.classList.toggle('on', x === b)); });
    m.querySelectorAll('[data-m]').forEach(b => b.onclick = () => { mode = b.dataset.m; m.querySelectorAll('[data-m]').forEach(x => x.classList.toggle('on', x === b)); });
    m.querySelector('[data-save]').onclick = async () => { const patch = { notice: m.querySelector('#gd-sn').value }; if (boss) Object.assign(patch, { intro: m.querySelector('#gd-si').value, emblem: e, join_mode: mode });
      if (await act('guild_update', { p_patch: patch }, '저장했어요')) m.remove(); };
    m.querySelector('[data-rn]')?.addEventListener('click', async () => { const v = m.querySelector('#gd-rn').value.trim(); if (!v || !confirm(`🔮 500 을 써서 [${v}] 로 바꿀까요?`)) return; if (await act('guild_update', { p_patch: { name: v } }, '이름을 바꿨어요')) { m.remove(); window.VRGem?.status?.(true); } });
  }
  function logPop() {
    const A = { create: '창설', join: '가입', leave: '탈퇴', kick: '추방', role: '역할 변경', transfer: '보스 넘김', claim_boss: '보스 승계', invite: '초대', update: '설정 변경', level_up: '레벨 업', disband: '해산' };
    pop(`<div class="gd-h big">📜 기록</div><div class="gd-log">${st.log.map(l => `<div><span>${esc(A[l.action] || l.action)}${l.action === 'level_up' ? ` Lv.${l.meta?.level}` : ''}</span><b>${esc(l.actor || '')}${l.target && l.target !== l.actor ? ` → ${esc(l.target)}` : ''}</b><small>${new Date(l.at).toLocaleDateString('ko-KR', { month: 'numeric', day: 'numeric' })}</small></div>`).join('') || '<div class="gd-empty">기록 없음</div>'}</div>`);
  }
  // ---- 2단계: 집결 · 의뢰 (guild2.sql) ----
  const QIC = { phase: '🗡️', stamina: '🔋', pvp_win: '⚔️', tower: '🗼', draw: '🎴', boss: '💀', levelup: '⬆️', checkin: '🕯️' };
  const QIMG = { pvp_win: 'pvp', draw: 'gacha', checkin: 'gold' };
  const qic = (ev, fb) => `<span class="gd-qic"><i>${QIC[ev] || fb || '📜'}</i><img src="img/ui/guild/quest_${QIMG[ev] || ev}.webp" alt="" onerror="this.remove()"></span>`;
  const RW = { loyalty: LOY, gold: '🪙', gem: '🔮', tickets: '🎟️', exp: '⚜️' };
  const rwTxt = rw => Object.entries(rw || {}).filter(([k, v]) => RW[k] && v).map(([k, v]) => `<span>${RW[k]}${n(v)}</span>`).join('');
  const ERR2 = { 'already checked in': '오늘은 이미 집결했어요', 'already claimed': '이미 받았어요', 'not reached': '아직 조건이 안 됐어요', 'check in first': '먼저 집결하세요',
    'reroll used': '교체는 하루 1번', 'contribution too low': '기여도가 부족해요 (목표의 1% 이상)' };
  const err2 = e => { const m = String(e?.message || e); const k = Object.keys(ERR2).find(x => m.includes(x)); return k ? ERR2[k] : errText(e); };
  async function act2(m, name, args, draw) {
    try { const r = await rpc(name, args); if (r?.got) toast(`받음 ${Object.entries(r.got).filter(([k]) => RW[k]).map(([k, v]) => `${RW[k]}${n(v)}`).join(' ')}`); window.VRPlayer?.wallet?.(true); if (r?.got?.gem) window.VRGem?.status?.(true); if (m.isConnected) draw(r); refresh(); return r; }
    catch (e) { toast(err2(e)); return null; }
  }
  async function rallyPop() {
    const m = pop('<div class="gd-loading">…</div>', 'wide rally');
    const draw = R => {
      const W = ['월', '화', '수', '목', '금', '토', '일'];
      m.querySelector('.gd-pop-panel').innerHTML = `<button class="gd-x" data-x aria-label="닫기">✕</button>
        <div class="gd-rb"><img src="img/ui/guild/rally_banner.webp" alt="" onerror="this.remove()"><span class="gd-rb-fb">🕯️</span><b>집결</b></div>
        <button class="gd-big gd-checkin" data-in ${R.checked ? 'disabled' : ''}>${R.checked ? '✔ 오늘 집결 완료' : `🕯️ 집결 <small>${rwTxt(R.reward)}</small>`}</button>
        <div class="gd-rp"><div class="gd-rp-h"><b>${R.count}/${R.total}</b><small>${R.pct}%</small></div>
          <div class="gd-rp-bar"><i style="width:${Math.min(100, R.pct)}%"></i>${R.tiers.map(t => `<em style="left:${t.tier}%" class="${t.reached ? 'on' : ''}"></em>`).join('')}</div>
          <div class="gd-rt">${R.tiers.map(t => `<button data-tier="${t.tier}" class="${t.claimed ? 'done' : t.reached ? 'ready' : ''}" ${t.reached && !t.claimed && R.checked ? '' : 'disabled'}><b>${t.tier}%</b><span>${rwTxt(t.reward)}</span><small>${t.claimed ? '✔' : `⚜️${t.exp}`}</small></button>`).join('')}</div></div>
        <div class="gd-wk">${R.week.map((on, i) => `<span class="${on ? 'on' : ''}">${on ? '🕯️' : '·'}<small>${W[i]}</small></span>`).join('')}
          <button data-tier="7" class="${R.week_claimed ? 'done' : R.week_claimable ? 'ready' : ''}" ${R.week_claimable && !R.week_claimed ? '' : 'disabled'}>7/7 ${rwTxt(R.week_reward)}</button></div>
        <div class="gd-rm">${(st?.members || []).map(x => `<span class="${R.checked_users.includes(x.user_id) ? 'on' : ''}" title="${esc(x.name)}">${x.card ? `<img src="${IMG}${x.card}.webp" alt="" onerror="this.remove()">` : '👤'}</span>`).join('')}</div>
        ${R.checked_other ? '<small class="gd-hint">오늘은 다른 조직에서 집결했어요</small>' : ''}`;
      m.querySelector('[data-in]').onclick = e => { e.currentTarget.disabled = true; act2(m, 'guild_checkin', {}, draw); };
      m.querySelectorAll('[data-tier]').forEach(b => b.onclick = () => { b.disabled = true; act2(m, 'guild_rally_claim', { p_tier: +b.dataset.tier }, draw); });
    };
    try { draw(await rpc('guild_rally')); } catch (e) { toast(err2(e)); m.remove(); }
  }
  async function questPop() {
    let tab = 'daily';
    const m = pop('<div class="gd-loading">…</div>', 'wide quest');
    const draw = Q => {
      const bar = (p, g) => `<div class="gd-qbar"><i style="width:${Math.min(100, p / g * 100).toFixed(1)}%"></i></div>`;
      const left = Math.max(0, Math.ceil((new Date(Q.week_end) - Date.now()) / 864e5));
      m.querySelector('.gd-pop-panel').innerHTML = `<button class="gd-x" data-x aria-label="닫기">✕</button>
        <div class="gd-qtabs"><button data-tab="daily" class="${tab === 'daily' ? 'on' : ''}">📜 일일</button><button data-tab="weekly" class="${tab === 'weekly' ? 'on' : ''}"><img class="gd-tabic" src="img/ui/guild/quest_weekly.webp" alt="">주간 <small>D-${left}</small></button></div>
        ${tab === 'daily' ? `<div class="gd-ql">${Q.daily.map(q => `<div class="gd-q ${q.claimed ? 'done' : ''}">${qic(q.event, q.icon)}<div class="gd-q-m"><b>${esc(q.label)}</b><small>${q.progress}/${q.goal}</small>${bar(q.progress, q.goal)}<span class="gd-rw">${rwTxt(q.reward)}</span></div>
            <div class="gd-q-a">${q.claimed ? '✔' : q.progress >= q.goal ? `<button class="gd-ok" data-claim="${q.slot}">받기</button>` : Q.reroll_left ? `<button class="gd-rr" data-rr="${q.slot}" title="교체 (하루 1번)">🔄</button>` : ''}</div></div>`).join('')}</div>
          <button class="gd-big gd-all" data-claim="0" ${Q.daily.every(q => q.claimed) && !Q.all_claimed ? '' : 'disabled'}>${Q.all_claimed ? '✔ 3개 완료 보너스' : `3개 완료 보너스 ${rwTxt(Q.all_reward)}`}</button>`
        : `<div class="gd-ql">${Q.weekly.map(q => `<div class="gd-wq">${qic(q.event, q.icon)}<div class="gd-q-m"><b>${esc(q.label)}</b><small>${n(q.progress)}/${n(q.goal)} · 내 기여 ${n(q.mine)}${q.mine < q.min ? ` <em>(최소 ${q.min})</em>` : ''}</small>
            <div class="gd-qbar w">${'<i style="width:' + Math.min(100, q.progress / q.goal / 1.5 * 100).toFixed(1) + '%"></i>'}${q.tiers.map(t => `<em style="left:${t.tier / 1.5}%" class="${t.reached ? 'on' : ''}"></em>`).join('')}</div>
            <div class="gd-wt">${q.tiers.map(t => `<button data-w="${q.slot}:${t.tier}" class="${t.claimed ? 'done' : t.reached ? 'ready' : ''}" ${t.reached && !t.claimed && q.mine >= q.min ? '' : 'disabled'}><b>${t.tier}%</b>${rwTxt(t.reward)}</button>`).join('')}</div>
            <div class="gd-top">${q.top.map((x, i) => `<span>${['🥇', '🥈', '🥉', '4', '5'][i]} ${esc(x.name)} <b>${n(x.amount)}</b></span>`).join('')}</div></div></div>`).join('')}</div>`}`;
      m.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; draw(Q); });
      m.querySelectorAll('[data-claim]').forEach(b => b.onclick = () => { b.disabled = true; act2(m, 'guild_quest_claim', { p_slot: +b.dataset.claim }, r => draw(r || Q)); });
      m.querySelectorAll('[data-rr]').forEach(b => b.onclick = () => { b.disabled = true; act2(m, 'guild_quest_reroll', { p_slot: +b.dataset.rr }, r => draw(r || Q)); });
      m.querySelectorAll('[data-w]').forEach(b => b.onclick = () => { const [sl, t] = b.dataset.w.split(':'); b.disabled = true; act2(m, 'guild_weekly_claim', { p_slot: +sl, p_tier: +t }, r => draw(r || Q)); });
    };
    try { draw(await rpc('guild_quests')); } catch (e) { toast(err2(e)); m.remove(); }
  }
  /** 마이페이지 카드 (엠블럼 · 이름 · 레벨) */
  function myCard(s) {
    if (!s) return '';
    return s.guild ? `<button type="button" class="gd-mycard" data-guild-open>${emb(s.guild.emblem)}<span><b>${esc(s.guild.name)}</b><small>Lv.${s.guild.level} · ${ROLE[s.me.role][0]} ${ROLE[s.me.role][1]}</small></span><i>›</i></button>`
      : `<button type="button" class="gd-mycard none" data-guild-open><span class="gd-emb"><i>🩸</i></span><span><b>조직 찾기</b><small>가입하거나 직접 세우기</small></span><i>›</i></button>`;
  }
  document.addEventListener('click', e => { if (e.target.closest('[data-guild-open]')) { e.preventDefault(); window.VRMyPage?.close?.(); open(); } });
  const mount = () => { const b = document.getElementById('main-guild'); if (b) b.addEventListener('click', () => { if (window.VRCloud?.user || window.__GUILD_MOCK) open(); }); };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
  window.VRGuild = { open, close, status, myCard, EMB, get now() { return st; } };
})();
