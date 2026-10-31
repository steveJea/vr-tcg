// ===== 👥 친구 (1단계) — 서버: supabase/friends.sql =====
// 버튼: [data-friendbtn] (메인 상단·스토리 허브) · 받은 신청 수 뱃지
// 탭: 친구 목록 / 받은 신청 / 보낸 신청 / 찾기 (닉네임 또는 친구 코드 8자리)
// 접속 상태: 3분마다 friends_ping, 5분 이내면 🟢 접속 중
// SQL 실행 전이거나 비로그인이면 버튼이 안 보임
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, off = false, pending = 0, tab = 'list', found = null, lastQ = '';
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { off = true; paint(); return null; } throw error; }
    return data;
  }
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = { 'already friends': '이미 친구예요', 'their friend cap': '상대의 친구 목록이 가득 찼어요', 'friend cap': '친구는 최대 50명까지예요', 'too many requests': '보낸 신청이 너무 많아요',
    'request not found': '이미 처리된 신청이에요', 'not friends': '친구가 아니에요', 'query too short': '2글자 이상 입력해 주세요', 'invalid user': '찾을 수 없는 플레이어예요', 'login required': '로그인이 필요해요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const ago = t => { if (!t) return '기록 없음'; const m = (Date.now() - new Date(t)) / 6e4; return m < 5 ? '접속 중' : m < 60 ? `${Math.floor(m)}분 전` : m < 1440 ? `${Math.floor(m / 60)}시간 전` : `${Math.floor(m / 1440)}일 전`; };

  async function ping() { if (off || !window.VRCloud?.user) return; try { const r = await rpc('friends_ping'); if (r) { pending = r.pending | 0; paint(); } } catch (e) { console.warn('[friends]', e?.message); } }
  async function load() { if (off) return null; try { const r = await rpc('friends_list'); if (r?.ok) { cache = r; pending = r.incoming.length; paint(); } } catch (e) { console.warn('[friends]', e?.message); } return cache; }

  function paint() {
    for (const w of document.querySelectorAll('[data-friendbtn]')) {
      if (off || !window.VRCloud?.user) { w.innerHTML = ''; continue; }
      if (!w.querySelector('.friend-btn')) { w.innerHTML = '<button class="story-mailbtn friend-btn" type="button" aria-label="친구" title="친구">👥<span>친구</span></button>'; w.firstChild.onclick = open; }
      const b = w.firstChild; b.querySelector('.story-badge')?.remove();
      if (pending > 0) b.insertAdjacentHTML('beforeend', `<i class="story-badge">${pending}</i>`);
    }
  }
  const row = (p, btns) => `<div class="fr-row"><span class="fr-dot ${p.online ? 'on' : ''}"></span><div class="fr-info"><b>${esc(p.name)}</b><small>Lv.${p.level | 0} · ${esc(p.code)} · ${p.online ? '🟢 접속 중' : ago(p.seen_at)}</small></div><div class="fr-btns">${btns}</div></div>`;
  const empty = t => `<div class="fr-empty">${t}</div>`;

  function open() {
    document.querySelector('.friend-pop')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop friend-pop';
    const act = async (fn, args, msg) => { try { await rpc(fn, args); if (msg) toast(msg); } catch (e) { toast(errText(e)); } await load(); if (found && lastQ) await search(lastQ, true); draw(); };
    async function search(q, quiet) { lastQ = q; try { found = await rpc('friends_search', { p_q: q }) || []; } catch (e) { found = null; if (!quiet) toast(errText(e)); } }
    const draw = () => {
      const s = cache;
      const tabs = [['list', `친구 ${s ? s.friends.length : ''}${s ? '/' + s.cap : ''}`], ['in', `받은 신청${s?.incoming.length ? ` <i class="story-badge">${s.incoming.length}</i>` : ''}`], ['out', '보낸 신청'], ['find', '🔍 찾기']];
      let body = '';
      if (!s) body = empty('불러오는 중...');
      else if (tab === 'list') body = s.friends.length ? s.friends.map(f => row(f, `<button class="fr-b ghost" data-rm="${f.user_id}" data-nm="${esc(f.name)}">삭제</button>`)).join('') : empty('아직 친구가 없어요. 🔍 찾기에서 친구를 추가해 보세요!');
      else if (tab === 'in') body = s.incoming.length ? s.incoming.map(r => row(r, `<button class="fr-b" data-acc="${r.req_id}">수락</button><button class="fr-b ghost" data-dec="${r.req_id}">거절</button>`)).join('') : empty('받은 신청이 없어요');
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
      pop.querySelectorAll('[data-rm]').forEach(b => b.onclick = () => { if (confirm(`${b.dataset.nm}님을 친구에서 삭제할까요?`)) act('friend_remove', { p_user: b.dataset.rm }, '친구를 삭제했어요'); });
      pop.querySelectorAll('[data-req]').forEach(b => b.onclick = async () => { b.disabled = true; try { const r = await rpc('friend_request', { p_user: b.dataset.req }); toast(r?.state === 'friend' ? '친구가 되었어요 🎉' : '친구 신청을 보냈어요'); } catch (e) { toast(errText(e)); } await load(); await search(lastQ, true); draw(); });
      const f = pop.querySelector('.fr-search');
      if (f) f.onsubmit = async e => { e.preventDefault(); const q = f.q.value.trim(); if (q.length < 2) { toast(ERR['query too short']); return; } await search(q); draw(); };
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    document.body.appendChild(pop); draw(); load().then(draw);
  }
  window.VRFriends = { open, load, ping, paint, get data() { return cache; } };
  setTimeout(() => { paint(); ping(); }, 1500); setTimeout(() => { paint(); ping(); }, 4000);
  setInterval(() => { if (!document.hidden) ping(); }, 180000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) ping(); });
  new MutationObserver(() => { if (document.querySelector('[data-friendbtn]:empty')) paint(); }).observe(document.body, { childList: true, subtree: true });
})();
