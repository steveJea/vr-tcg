// ===== 👥 친구 + 일일 선물 — 서버: supabase/friends.sql · daily_social.sql =====
// 버튼: [data-friendbtn] (마이페이지 상단) · 받은 신청·선물 수 뱃지: 버튼 + 마이 탭([data-friendbadge])
// 탭: 친구 목록 / 받은 신청 / 보낸 신청 / 찾기 / 선물
// 접속 상태: 3분마다 friends_ping, 5분 이내면 🟢 접속 중
// SQL 실행 전이거나 비로그인이면 버튼이 안 보임
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, rec = null, fbMode = '1v1', off = false, pending = 0, gifts = 0, tab = 'list', found = null, lastQ = '';
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) {
      if (missing(error)) {
        // 선물 RPC 만 없으면 선물만 숨기고, 친구 자체는 유지
        if (/friend_gift/i.test(name)) return null;
        off = true; paint(); return null;
      }
      throw error;
    }
    return data;
  }
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = { 'already friends': '이미 친구예요', 'their friend cap': '상대의 친구 목록이 가득 찼어요', 'friend cap': '친구는 최대 50명까지예요', 'too many requests': '보낸 신청이 너무 많아요',
    'request not found': '이미 처리된 신청이에요', 'not friends': '친구가 아니에요', 'query too short': '2글자 이상 입력해 주세요', 'invalid user': '찾을 수 없는 플레이어예요', 'login required': '로그인이 필요해요',
    'already sent': '오늘 이미 보냈어요', 'already claimed': '이미 받았어요', 'claim cap': '오늘 받을 수 있는 선물을 다 받았어요', 'gift not found': '없는 선물이에요', 'nothing to claim': '받을 선물이 없어요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const ago = t => { if (!t) return '기록 없음'; const m = (Date.now() - new Date(t)) / 6e4; return m < 5 ? '접속 중' : m < 60 ? `${Math.floor(m)}분 전` : m < 1440 ? `${Math.floor(m / 60)}시간 전` : `${Math.floor(m / 1440)}일 전`; };
  const badgeN = () => pending + (gifts > 0 ? gifts : 0);
  const rwGift = r => r?.stamina ? `🔋 +${r.stamina}` : r?.gold ? `🪙 ${Number(r.gold).toLocaleString('ko-KR')}` : '선물';

  async function ping() { if (off || !window.VRCloud?.user) return; try { const r = await rpc('friends_ping'); if (r) { pending = r.pending | 0; gifts = r.gifts | 0; paint(); } } catch (e) { console.warn('[friends]', e?.message); } }
  async function load() { if (off) return null; try { const r = await rpc('friends_list'); if (r?.ok) { cache = r; pending = r.incoming.length; gifts = r.gifts?.inbox?.length | 0; paint(); } } catch (e) { console.warn('[friends]', e?.message); }
    try { const h = await window.VRCloud.sb.rpc('friend_battle_history', { p_friend: null }); rec = h.error ? null : h.data; } catch { rec = null; }
    return cache; }

  function paint() {
    for (const t of document.querySelectorAll('[data-friendbadge]')) { t.querySelector('.fr-tabbadge')?.remove(); if (!off && window.VRCloud?.user && badgeN() > 0) t.insertAdjacentHTML('beforeend', `<i class="story-badge fr-tabbadge">${badgeN()}</i>`); }
    for (const w of document.querySelectorAll('[data-friendbtn]')) {
      if (off || !window.VRCloud?.user) { w.innerHTML = ''; continue; }
      if (!w.querySelector('.friend-btn')) { w.innerHTML = '<button class="story-mailbtn friend-btn" type="button" aria-label="친구" title="친구">👥<span>친구</span></button>'; w.firstChild.onclick = open; }
      const b = w.firstChild; b.querySelector('.story-badge')?.remove();
      if (badgeN() > 0) b.insertAdjacentHTML('beforeend', `<i class="story-badge">${badgeN()}</i>`);
    }
  }
  const row = (p, btns) => `<div class="fr-row"><span class="fr-dot ${p.online ? 'on' : ''}"></span><div class="fr-info">${window.VRCosmo?.chip?.({ name: p.name, title: p.title, title_name: p.title_name, frame: p.frame, avatar: p.avatar }, { sm: true }) || `<b>${esc(p.name)}</b>`}<small>Lv.${p.level | 0} · ${esc(p.code)} · ${p.online ? '🟢 접속 중' : ago(p.seen_at)}</small></div><div class="fr-btns">${btns}</div></div>`;
  const empty = t => `<div class="fr-empty">${t}</div>`;

  function open() {
    document.querySelector('.friend-pop:not(.vr-in-page)')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop friend-pop';
    const act = async (fn, args, msg) => { try { const r = await rpc(fn, args); if (r == null && /friend_gift/i.test(fn)) { toast('아직 준비 중이에요'); return; } if (msg) toast(msg); } catch (e) { toast(errText(e)); } await load(); if (found && lastQ) await search(lastQ, true); draw(); };
    async function search(q, quiet) { lastQ = q; try { found = await rpc('friends_search', { p_q: q }) || []; } catch (e) { found = null; if (!quiet) toast(errText(e)); } }
    const draw = () => {
      const s = cache;
      const hasGift = !!s?.gifts;
      const gInbox = s?.gifts?.inbox?.length | 0;
      if (tab === 'gift' && !hasGift) tab = 'list';
      const tabs = [['list', `친구 ${s ? s.friends.length : ''}${s ? '/' + s.cap : ''}`], ...(hasGift ? [['gift', `선물${gInbox ? ` <i class="story-badge">${gInbox}</i>` : ''}`]] : []), ['in', `받은 신청${s?.incoming.length ? ` <i class="story-badge">${s.incoming.length}</i>` : ''}`], ['out', '보낸 신청'], ['find', '🔍 찾기']];
      let body = '';
      if (!s) body = empty('불러오는 중...');
      else if (tab === 'list') {
        const sendable = hasGift ? s.friends.filter(f => !f.gift_sent) : [];
        body = s.friends.length ? (rec ? `<div class="fr-fb">⚔️ 친구 대전 <button class="fr-tab ${fbMode === '1v1' ? 'on' : ''}" data-fbm="1v1">1v1</button><button class="fr-tab ${fbMode === '3v3' ? 'on' : ''}" data-fbm="3v3">3v3</button><small>오늘 ${rec.left}회 · 무제한 리그 덱</small></div>` : '')
          + (sendable.length ? `<div class="fr-giftbar"><button class="fr-b" data-sendall>🎁 모두 보내기 (${sendable.length})</button><small>${rwGift(s.gifts?.reward)}</small></div>` : '')
          + s.friends.map(f => row(f, `${rec ? `${rec.records?.[f.user_id] ? `<span class="fr-st">${rec.records[f.user_id].w}승 ${rec.records[f.user_id].l}패</span>` : ''}<button class="fr-b" data-fb="${f.user_id}">⚔️ 대전</button>` : ''}${hasGift ? `<button class="fr-b ${f.gift_sent ? 'ghost' : ''}" data-gift="${f.user_id}" ${f.gift_sent ? 'disabled' : ''}>${f.gift_sent ? '보냄' : '🎁'}</button>` : ''}<button class="fr-b ghost" data-rm="${f.user_id}" data-nm="${esc(f.name)}">삭제</button>`)).join('')
          : empty('아직 친구가 없어요. 🔍 찾기에서 친구를 추가해 보세요!');
      } else if (tab === 'gift') {
        const g = s.gifts || {};
        body = `<div class="fr-giftbar"><span>오늘 ${g.claimed_today | 0}/${g.cap | 20} · ${rwGift(g.reward)}</span>${(g.inbox || []).length && (g.left | 0) > 0 ? `<button class="fr-b" data-claimall>모두 받기</button>` : ''}</div>`
          + ((g.inbox || []).length ? g.inbox.map(x => row(x, `<button class="fr-b" data-claim="${x.gift_id}" ${(g.left | 0) <= 0 ? 'disabled' : ''}>받기</button>`)).join('')
            : empty((g.claimed_today | 0) >= (g.cap | 20) ? '오늘 받을 수 있는 선물을 다 받았어요' : '받은 선물이 없어요'));
      } else if (tab === 'in') body = s.incoming.length ? s.incoming.map(r => row(r, `<button class="fr-b" data-acc="${r.req_id}">수락</button><button class="fr-b ghost" data-dec="${r.req_id}">거절</button>`)).join('') : empty('받은 신청이 없어요');
      else if (tab === 'out') body = s.outgoing.length ? s.outgoing.map(r => row(r, `<button class="fr-b ghost" data-cancel="${r.req_id}">취소</button>`)).join('') : empty('보낸 신청이 없어요');
      else body = `<form class="fr-search"><input name="q" maxlength="20" placeholder="닉네임 또는 친구 코드" value="${esc(lastQ)}" autocomplete="off"><button class="fr-b">검색</button></form>
        ${found == null ? empty('닉네임 일부나 친구 코드(8자리)로 찾을 수 있어요') : found.length ? found.map(p => row(p,
          p.state === 'friend' ? '<span class="fr-st">친구</span>' : p.state === 'sent' ? '<span class="fr-st">신청함</span>'
          : p.state === 'received' ? `<button class="fr-b" data-req="${p.user_id}">수락</button>` : `<button class="fr-b" data-req="${p.user_id}">신청</button>`)).join('') : empty('검색 결과가 없어요')}`;
      pop.innerHTML = `<div class="gem-panel friend-panel" role="dialog" aria-label="친구"><button class="gem-x" data-x aria-label="닫기">✕</button>
        <h3 class="daily-h">👥 친구 ${s ? `<small>내 코드 <b class="fr-code" title="눌러서 복사">${esc(s.me.code)}</b></small>` : ''}</h3>
        <div class="fr-tabs">${tabs.map(([k, l]) => `<button class="fr-tab ${tab === k ? 'on' : ''}" data-tab="${k}">${l}</button>`).join('')}</div>
        <div class="fr-body">${body}</div></div>`;
      pop.querySelector('[data-x]').onclick = () => pop.remove();
      pop.querySelector('.fr-code')?.addEventListener('click', () => { navigator.clipboard?.writeText(s.me.code); toast('친구 코드를 복사했어요'); });
      pop.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; draw(); });
      pop.querySelectorAll('[data-acc]').forEach(b => b.onclick = () => act('friend_respond', { p_req: +b.dataset.acc, p_accept: true }, '친구가 되었어요 🎉'));
      pop.querySelectorAll('[data-dec]').forEach(b => b.onclick = () => act('friend_respond', { p_req: +b.dataset.dec, p_accept: false }, '신청을 거절했어요'));
      pop.querySelectorAll('[data-cancel]').forEach(b => b.onclick = () => act('friend_cancel', { p_req: +b.dataset.cancel }, '신청을 취소했어요'));
      pop.querySelectorAll('[data-fbm]').forEach(b => b.onclick = () => { fbMode = b.dataset.fbm; draw(); });
      pop.querySelectorAll('[data-fb]').forEach(b => b.onclick = async () => { if (!window.VRPvp?.friendFight) return; b.disabled = true; pop.remove(); await window.VRPvp.friendFight(b.dataset.fb, fbMode); load(); });
      pop.querySelectorAll('[data-rm]').forEach(b => b.onclick = async () => { if (await window.VRAsk(`${b.dataset.nm}님을 친구에서 삭제할까요?`)) act('friend_remove', { p_user: b.dataset.rm }, '친구를 삭제했어요'); });
      pop.querySelectorAll('[data-gift]').forEach(b => b.onclick = () => act('friend_gift_send', { p_user: b.dataset.gift }, '선물을 보냈어요 🎁'));
      pop.querySelector('[data-sendall]')?.addEventListener('click', async () => {
        const list = (cache?.friends || []).filter(f => !f.gift_sent); let ok = 0;
        for (const f of list) { try { await rpc('friend_gift_send', { p_user: f.user_id }); ok++; } catch (e) { if (!/already sent/i.test(String(e?.message || e))) { toast(errText(e)); break; } } }
        if (ok) toast(`🎁 ${ok}명에게 선물을 보냈어요`); await load(); draw();
      });
      pop.querySelectorAll('[data-claim]').forEach(b => b.onclick = async () => {
        try { const r = await rpc('friend_gift_claim', { p_id: +b.dataset.claim }); toast(`🎁 ${rwGift(r?.got)}`); if (r?.stamina != null) window.VRPlayer?.status?.(true); }
        catch (e) { toast(errText(e)); } await load(); draw();
      });
      pop.querySelector('[data-claimall]')?.addEventListener('click', async () => {
        try { const r = await rpc('friend_gift_claim_all'); toast(`🎁 ${r?.n || 0}개 · ${rwGift(r?.got)}`); if (r?.stamina != null) window.VRPlayer?.status?.(true); }
        catch (e) { toast(errText(e)); } await load(); draw();
      });
      pop.querySelectorAll('[data-req]').forEach(b => b.onclick = async () => { b.disabled = true; try { const r = await rpc('friend_request', { p_user: b.dataset.req }); toast(r?.state === 'friend' ? '친구가 되었어요 🎉' : '친구 신청을 보냈어요'); } catch (e) { toast(errText(e)); } await load(); await search(lastQ, true); draw(); });
      const f = pop.querySelector('.fr-search');
      if (f) f.onsubmit = async e => { e.preventDefault(); const q = f.q.value.trim(); if (q.length < 2) { toast(ERR['query too short']); return; } await search(q); draw(); };
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    if (!window.VRPages?.host?.('friends', '👥 친구', pop)) document.body.appendChild(pop);
    draw(); load().then(draw);
  }
  window.VRFriends = { open, load, ping, paint, get data() { return cache; } };
  setTimeout(() => { paint(); ping(); }, 1500); setTimeout(() => { paint(); ping(); }, 4000);
  setInterval(() => { if (!document.hidden) ping(); }, 180000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) ping(); });
  new MutationObserver(() => { if (document.querySelector('[data-friendbtn]:empty') || document.querySelector('[data-friendbadge]:not(:has(.fr-tabbadge))') && badgeN() > 0) paint(); }).observe(document.body, { childList: true, subtree: true });
})();
