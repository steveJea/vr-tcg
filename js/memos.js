// ===== 친구 1:1 쪽지 (1단계) — 서버: supabase/friend_memos_staging.sql =====
// 플래그 friend_memos 가 꺼져 있으면 일반 유저에게는 안 보임. 관리자(stevejean77@gmail.com)는 테스트 가능.
// 우편(player_mail)과 분리. SQL 전이거나 비로그인이면 조용히 숨김.
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  const FOCUS_GAP = 60000, NAV_GAP = 2000;
  let enabled = false, unread = 0, sanction = null, off = false, inFlight = false, lastPollAt = 0;
  let inbox = [], sent = [], blocks = [];
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = {
    'feature off': '쪽지 기능을 아직 열지 않았어요',
    'not friends': '친구만 쪽지를 주고받을 수 있어요',
    'blocked': '차단한 상대와는 쪽지를 주고받을 수 없어요',
    'muted': '쪽지 이용이 잠시 제한되어 있어요',
    'suspended': '쪽지 이용이 정지되어 있어요',
    'rate second': '너무 자주 보내고 있어요. 잠시 후 다시 시도해 주세요',
    'rate minute': '잠시 후에 다시 보내 주세요',
    'rate daily': '오늘 이 친구에게 보낼 수 있는 쪽지를 다 썼어요',
    'bad word': '쓸 수 없는 표현이 들어 있어요',
    'body too long': '쪽지는 200자까지예요',
    'empty body': '내용을 입력해 주세요',
    'already reported': '이미 신고한 쪽지예요',
    'own memo': '내가 보낸 쪽지는 신고할 수 없어요',
    'memo not found': '쪽지를 찾을 수 없어요',
    'not blocked': '차단한 상대가 아니에요',
    'invalid user': '찾을 수 없는 플레이어예요',
    'login required': '로그인이 필요해요',
    'bad reason': '신고 사유를 입력해 주세요'
  };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const ago = t => { if (!t) return ''; const s = Math.max(0, (Date.now() - new Date(t)) / 1000); return s < 60 ? '방금' : s < 3600 ? `${Math.floor(s / 60)}분 전` : s < 86400 ? `${Math.floor(s / 3600)}시간 전` : `${Math.floor(s / 86400)}일 전`; };
  const nameOf = p => p?.name || '플레이어';

  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) {
      if (missing(error)) { off = true; enabled = false; unread = 0; window.VRFriends?.setMemoBadge?.(false, 0); return null; }
      throw error;
    }
    return data;
  }

  function paintFriends() { window.VRFriends?.setMemoBadge?.(enabled, unread); }

  async function poll(kind) {
    if (off || inFlight || !window.VRCloud?.user) return;
    const now = Date.now();
    const gap = (kind === 'focus' || kind === 'visible') ? FOCUS_GAP : (kind === 'start' || kind === 'open' || kind === 'send') ? 0 : NAV_GAP;
    if (gap && now - lastPollAt < gap) return;
    inFlight = true; lastPollAt = now;
    try {
      const r = await rpc('memo_status');
      if (r == null) return;
      enabled = !!r.enabled;
      unread = r.unread | 0;
      sanction = r.sanction || null;
      paintFriends();
    } catch (e) { console.warn('[memos]', e?.message); }
    finally { inFlight = false; }
  }

  async function loadBox(box) {
    if (!enabled) return [];
    try {
      const r = await rpc('memo_list', { p_box: box, p_limit: 50 });
      const items = r?.items || [];
      if (box === 'inbox') inbox = items; else sent = items;
      return items;
    } catch (e) { toast(errText(e)); return box === 'inbox' ? inbox : sent; }
  }
  async function loadBlocks() {
    if (!enabled) return [];
    try { const r = await rpc('player_blocks'); blocks = r?.items || []; return blocks; }
    catch (e) { toast(errText(e)); return blocks; }
  }

  function boxHtml(tab) {
    if (sanction === 'suspend') return `<div class="fr-empty">쪽지 이용이 정지되어 있어요</div>`;
    if (tab === 'blocks') {
      return blocks.length
        ? blocks.map(p => `<div class="fr-row"><div class="fr-info" data-clarity-mask="true"><b>${esc(nameOf(p))}</b><small>차단 · ${ago(p.at)}</small></div><div class="fr-btns"><button class="fr-b ghost" data-unblock="${p.user_id}" data-nm="${esc(nameOf(p))}">해제</button></div></div>`).join('')
        : `<div class="fr-empty">차단한 플레이어가 없어요</div>`;
    }
    const items = tab === 'sent' ? sent : inbox;
    if (!items.length) return `<div class="fr-empty">${tab === 'sent' ? '보낸 쪽지가 없어요' : '받은 쪽지가 없어요'}</div>`;
    return items.map(m => {
      const who = tab === 'sent' ? m.to : m.from;
      return `<button type="button" class="fr-row mm-row ${m.read || tab === 'sent' ? '' : 'unread'}" data-open="${m.id}" data-box="${tab}">
        <div class="fr-info" data-clarity-mask="true"><b>${esc(nameOf(who))}</b><small>${ago(m.created_at)}${m.read || tab === 'sent' ? '' : ' · 안 읽음'}</small>
          <span class="mm-prev">${esc(m.body)}</span></div></button>`;
    }).join('');
  }

  function bindBox(pop) {
    pop.querySelectorAll('[data-open]').forEach(b => b.onclick = () => openMemo(+b.dataset.open, b.dataset.box));
    pop.querySelectorAll('[data-unblock]').forEach(b => b.onclick = async () => {
      if (!await window.VRAsk?.(`${b.dataset.nm}님 차단을 해제할까요?`)) return;
      try { await rpc('player_unblock', { p_user: b.dataset.unblock }); toast('차단을 해제했어요'); await loadBlocks(); window.VRFriends?.redraw?.(); }
      catch (e) { toast(errText(e)); }
    });
  }

  async function compose(userId, name) {
    if (!enabled) return toast(ERR['feature off']);
    if (sanction === 'mute') return toast(ERR.muted);
    if (sanction === 'suspend') return toast(ERR.suspended);
    document.querySelector('.mm-compose')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop mm-compose';
    pop.innerHTML = `<div class="gem-panel mm-panel" role="dialog" aria-label="쪽지 보내기"><button class="gem-x" data-x aria-label="닫기">✕</button>
      <h3 class="daily-h">✉️ 쪽지 보내기</h3>
      <p class="mm-to" data-clarity-mask="true">${esc(name || '플레이어')}님에게</p>
      ${sanction === 'mute' ? '<div class="mm-warn">쪽지 이용이 잠시 제한되어 있어요</div>' : ''}
      <textarea class="mm-body" maxlength="200" rows="5" placeholder="내용을 적어 주세요 (200자)"></textarea>
      <div class="mm-foot"><small class="mm-cnt">0/200</small><button class="fr-b" data-send>보내기</button></div></div>`;
    const ta = pop.querySelector('.mm-body'), cnt = pop.querySelector('.mm-cnt'), send = pop.querySelector('[data-send]');
    const tick = () => { cnt.textContent = `${ta.value.length}/200`; };
    ta.addEventListener('input', tick); tick();
    pop.querySelector('[data-x]').onclick = () => pop.remove();
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    send.onclick = async () => {
      const body = ta.value.trim(); if (!body) return toast(ERR['empty body']);
      send.disabled = true;
      try {
        await rpc('memo_send', { p_user: userId, p_body: body });
        toast('쪽지를 보냈어요'); pop.remove(); await poll('send'); await loadBox('sent'); window.VRFriends?.redraw?.();
      } catch (e) { toast(errText(e)); send.disabled = false; }
    };
    document.body.appendChild(pop); ta.focus();
  }

  async function openMemo(id, box) {
    const items = box === 'sent' ? sent : inbox;
    const m = items.find(x => x.id === id); if (!m) return;
    if (box === 'inbox' && !m.read) {
      try { await rpc('memo_read', { p_id: id }); m.read = true; await poll('send'); window.VRFriends?.redraw?.(); } catch {}
    }
    document.querySelector('.mm-read')?.remove();
    const who = box === 'sent' ? m.to : m.from;
    const pop = document.createElement('div'); pop.className = 'gem-pop mm-read';
    pop.innerHTML = `<div class="gem-panel mm-panel" role="dialog" aria-label="쪽지"><button class="gem-x" data-x aria-label="닫기">✕</button>
      <h3 class="daily-h">✉️ 쪽지</h3>
      <p class="mm-to" data-clarity-mask="true">${box === 'sent' ? '받는 사람' : '보낸 사람'} · ${esc(nameOf(who))}<small> · ${ago(m.created_at)}</small></p>
      <div class="mm-text" data-clarity-mask="true">${esc(m.body)}</div>
      <div class="mm-acts">${box === 'inbox' ? `<button class="fr-b" data-reply>답장</button><button class="fr-b ghost" data-rep>신고</button><button class="fr-b ghost" data-blk>차단</button>` : ''}</div></div>`;
    pop.querySelector('[data-x]').onclick = () => pop.remove();
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    pop.querySelector('[data-reply]')?.addEventListener('click', () => { pop.remove(); compose(who.user_id, nameOf(who)); });
    pop.querySelector('[data-rep]')?.addEventListener('click', () => reportMemo(m, pop));
    pop.querySelector('[data-blk]')?.addEventListener('click', async () => {
      if (!await window.VRAsk?.(`${nameOf(who)}님을 차단할까요? 서로 쪽지를 보낼 수 없게 됩니다.`)) return;
      try { await rpc('player_block', { p_user: who.user_id }); toast('차단했어요'); pop.remove(); await loadBlocks(); }
      catch (e) { toast(errText(e)); }
    });
    document.body.appendChild(pop);
  }

  function reportMemo(m, parent) {
    document.querySelector('.mm-report')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop mm-report';
    pop.innerHTML = `<div class="gem-panel mm-panel" role="dialog" aria-label="쪽지 신고"><button class="gem-x" data-x aria-label="닫기">✕</button>
      <h3 class="daily-h">신고</h3>
      <textarea class="mm-body" maxlength="200" rows="4" placeholder="사유를 적어 주세요"></textarea>
      <div class="mm-foot"><small class="mm-cnt">0/200</small><button class="fr-b" data-go>신고하기</button></div></div>`;
    const ta = pop.querySelector('.mm-body'), cnt = pop.querySelector('.mm-cnt');
    ta.addEventListener('input', () => { cnt.textContent = `${ta.value.length}/200`; });
    pop.querySelector('[data-x]').onclick = () => pop.remove();
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    pop.querySelector('[data-go]').onclick = async () => {
      const reason = ta.value.trim(); if (!reason) return toast(ERR['bad reason']);
      try { await rpc('chat_report', { p_memo_id: m.id, p_reason: reason }); toast('신고를 접수했어요'); pop.remove(); parent?.remove(); }
      catch (e) { toast(errText(e)); }
    };
    document.body.appendChild(pop); ta.focus();
  }

  async function blockUser(userId, name) {
    if (!enabled) return toast(ERR['feature off']);
    if (!await window.VRAsk?.(`${name}님을 차단할까요? 서로 쪽지를 보낼 수 없게 됩니다.`)) return;
    try { await rpc('player_block', { p_user: userId }); toast('차단했어요'); await loadBlocks(); window.VRFriends?.redraw?.(); }
    catch (e) { toast(errText(e)); }
  }

  async function prepare(tab) {
    if (!enabled) return;
    if (tab === 'memo-in') await loadBox('inbox');
    else if (tab === 'memo-out') await loadBox('sent');
    else if (tab === 'blocks') await loadBlocks();
  }

  function hookHome() {
    const scr = document.getElementById('start-screen'); if (!scr || typeof MutationObserver !== 'function') return;
    let was = !scr.classList.contains('hidden');
    new MutationObserver(() => {
      const vis = !scr.classList.contains('hidden');
      if (vis && !was) poll('home');
      was = vis;
    }).observe(scr, { attributes: true, attributeFilter: ['class'] });
  }

  function start() {
    off = false; enabled = false; unread = 0; lastPollAt = 0; paintFriends();
    if (!window.VRCloud?.user) return;
    hookHome(); poll('start');
  }

  window.VRMemos = {
    get enabled() { return enabled && !off; },
    get unread() { return unread; },
    poll, compose, blockUser, boxHtml, bindBox, prepare,
    tabs() {
      if (!enabled) return [];
      return [
        ['memo-in', `받은 쪽지${unread ? ` <i class="story-badge">${unread > 99 ? '99+' : unread}</i>` : ''}`],
        ['memo-out', '보낸 쪽지'],
        ['blocks', '차단']
      ];
    }
  };
  window.addEventListener('vr:user', start);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) poll('visible'); });
  window.addEventListener('focus', () => poll('focus'));
  window.addEventListener('hashchange', () => poll('nav'));
  setTimeout(start, 1600);
})();
