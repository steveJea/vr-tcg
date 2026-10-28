// ===== 관리자 페이지 (admin.html) =====
// 권한 판정은 서버(supabase/admin.sql 의 security definer RPC)가 함. 이 화면은 결과만 보여 줌:
// admin_check() 가 admin:false 면 '접근 거부'. 다른 RPC 도 관리자가 아니면 서버가 'forbidden' 으로 거부.
// anon 키 + 로그인 세션만 사용 (js/cloud.js). service_role 키 없음.
(() => {
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const M = () => window.__ADMIN_MOCK;
  const cloud = () => M()?.cloud || window.VRCloud;
  const rpc = async (name, args) => {
    if (M()?.rpc) return M().rpc(name, args);
    const { data, error } = await cloud().sb.rpc(name, args);
    if (error) throw error; return data;
  };
  const fmt = t => t ? new Date(t).toLocaleString('ko-KR', { timeZone: 'Asia/Seoul', hour12: false }) + ' KST' : '-';
  const root = () => $('ad-root');
  let names = new Map(), users = [], tab = 'users';

  async function loadNames() {
    try { const t = await (await fetch('data/cards.csv')).text(); const [h, ...r] = t.trim().split(/\r?\n/); const H = h.split(',');
      const iI = H.indexOf('id'), iN = H.indexOf('name'), iG = H.indexOf('grade');
      names = new Map(r.map(x => { const v = x.split(','); return [v[iI], { name: v[iN], grade: v[iG] }]; })); } catch {}
  }
  const SHORT = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR', 'LEGENDARY RARE': 'LR' };
  const CUR = [['gold', '🪙', '골드'], ['blood', '🩸', '순수한 피'], ['shard', '💠', '이상한 조각'], ['soul', '🔥', '각성자의 혼']];
  const ACT = { grant_tickets: '소환권 지급', grant_gold: '골드 지급', grant_blood: '순수한 피 지급', grant_shard: '이상한 조각 지급', grant_soul: '각성자의 혼 지급' };
  const cname = id => names.get(String(id))?.name || id;

  async function waitCloud() {
    for (let i = 0; i < 100; i++) { const c = cloud(); if (c && (c.ready || c.sb === null && i > 60)) return c; await new Promise(r => setTimeout(r, 100)); }
    return cloud();
  }
  function denied(msg) { root().innerHTML = `<div class="ad-denied" id="ad-denied"><b>접근 거부 (Access denied)</b>${esc(msg || '이 페이지는 관리자만 볼 수 있어요.')}</div>`; }

  async function boot() {
    const c = await waitCloud();
    if (!c?.sb && !M()) return denied('로그인 서버에 연결할 수 없어요.');
    const u = c.user;
    if (!u) {
      root().innerHTML = `<div class="ad-denied" id="ad-denied"><b>접근 거부 (Access denied)</b>관리자 계정으로 로그인해 주세요.<br><br><button class="ad-btn" id="ad-login">구글 로그인</button><br><small>로그인 후 메인 화면으로 이동하면 이 주소(admin.html)로 다시 들어오세요.</small></div>`;
      $('ad-login').onclick = () => c.login(); return;
    }
    $('ad-who').textContent = u.email || '';
    let chk = null; try { chk = await rpc('admin_check'); } catch (e) { return denied(/admin_check/.test(e?.message || '') ? '서버에 관리자 함수(supabase/admin.sql)가 아직 없어요.' : '권한을 확인하지 못했어요.'); }
    if (!chk?.admin) return denied();
    await loadNames();
    render();
  }

  function render() {
    root().innerHTML = `<div class="ad-tabs"><button class="ad-btn sub ${tab === 'users' ? 'on' : ''}" data-tab="users">가입 유저</button><button class="ad-btn sub ${tab === 'logs' ? 'on' : ''}" data-tab="logs">관리자 기록</button><button class="ad-btn sub ${tab === 'notices' ? 'on' : ''}" data-tab="notices">공지</button></div><div id="ad-view"></div>`;
    root().querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; render(); });
    tab === 'users' ? renderUsers() : tab === 'notices' ? renderNotices() : renderLogs();
  }
  async function renderUsers(q = '') {
    const v = $('ad-view');
    v.innerHTML = `<div class="ad-bar"><input id="ad-q" placeholder="이메일 · 이름 · 닉네임 검색" value="${esc(q)}"><button class="ad-btn" id="ad-search">검색</button></div><div id="ad-list" class="ad-msg">불러오는 중...</div>`;
    $('ad-search').onclick = () => renderUsers($('ad-q').value.trim());
    $('ad-q').onkeydown = e => { if (e.key === 'Enter') renderUsers($('ad-q').value.trim()); };
    try { users = await rpc('admin_list_users', { p_search: q || null, p_limit: 200, p_offset: 0 }) || []; }
    catch (e) { $('ad-list').innerHTML = `<span class="ad-err">${/forbidden/.test(e?.message) ? '접근 거부 (Access denied)' : esc(e?.message || '불러오기 실패')}</span>`; return; }
    $('ad-list').className = 'ad-wrap';
    $('ad-list').innerHTML = `<div style="margin-bottom:6px;opacity:.75">${users.length}명</div><table class="ad-table"><thead><tr><th>이메일</th><th>이름</th><th>닉네임</th><th>가입</th><th>마지막 로그인</th><th>🎟️</th><th>카드</th><th>아케이드</th></tr></thead><tbody>
      ${users.map(u => `<tr data-uid="${esc(u.id)}"><td>${esc(u.email)}</td><td>${esc(u.name)}</td><td>${esc(u.nickname)}</td><td>${fmt(u.created_at)}</td><td>${fmt(u.last_sign_in_at)}</td><td>${u.tickets}</td><td>${u.cards}</td><td>${u.wins}승 ${u.losses}패${u.draws ? ` ${u.draws}무` : ''}</td></tr>`).join('')}</tbody></table>`;
    $('ad-list').querySelectorAll('[data-uid]').forEach(tr => tr.onclick = () => openUser(tr.dataset.uid));
  }
  async function renderLogs() {
    const v = $('ad-view'); v.innerHTML = '<div class="ad-msg">불러오는 중...</div>';
    try {
      const rows = await rpc('admin_logs', { p_limit: 200 }) || [];
      v.innerHTML = `<div class="ad-wrap"><table class="ad-table"><thead><tr><th>시각</th><th>관리자</th><th>작업</th><th>대상</th><th>수량</th><th>전→후</th><th>사유</th></tr></thead><tbody>
        ${rows.map(r => `<tr><td>${fmt(r.created_at)}</td><td>${esc(r.admin_email)}</td><td>${(ACT[r.action] || esc(r.action))}</td><td>${esc(r.target_email || r.target_user)}</td><td>${r.amount ?? ''}</td><td>${r.before_val ?? ''} → ${r.after_val ?? ''}</td><td>${esc(r.reason)}</td></tr>`).join('') || '<tr><td colspan="7">기록 없음</td></tr>'}</tbody></table></div>`;
    } catch (e) { v.innerHTML = `<div class="ad-err">${esc(e?.message)}</div>`; }
  }

  // --- 공지 게시판: 쓰기·수정·삭제·고정 (서버 admin_notice_save / admin_notice_delete, 관리자만). 게임 메인의 흐르는 공지에 표시 ---
  const listNotices = async () => {
    if (M()?.notices) return M().notices();
    const { data, error } = await cloud().sb.from('notices').select('*').order('pinned', { ascending: false }).order('created_at', { ascending: false });
    if (error) throw error; return data || [];
  };
  async function renderNotices(edit = null) {
    const v = $('ad-view'); v.innerHTML = '<div class="ad-msg">불러오는 중...</div>';
    let rows; try { rows = await listNotices(); } catch (e) { v.innerHTML = `<div class="ad-msg ad-err">불러오기 실패: ${esc(e.message)} (supabase/pvp_info_notices.sql 실행 필요)</div>`; return; }
    const cur = rows.find(r => r.id === edit);
    v.innerHTML = `<div class="ad-sec ad-nform"><h3>${cur ? '공지 수정' : '새 공지'}</h3>
      <textarea id="ad-nbody" maxlength="200" rows="3" placeholder="게임 메인에 흐르는 공지 (200자)">${esc(cur?.body || '')}</textarea>
      <div class="ad-nrow"><label><input type="checkbox" id="ad-npin" ${cur?.pinned ? 'checked' : ''}> 📌 맨 앞 고정</label><span id="ad-ncnt">${(cur?.body || '').length}/200</span>
      ${cur ? '<button class="ad-btn sub" id="ad-ncancel">취소</button>' : ''}<button class="ad-btn" id="ad-nsave">${cur ? '수정 저장' : '올리기'}</button></div><div id="ad-nmsg"></div></div>
      <div class="ad-nlist">${rows.map(r => `<div class="ad-nitem ${r.pinned ? 'pin' : ''}"><div class="ad-ntext">${r.pinned ? '📌 ' : ''}${esc(r.body)}<small>${fmt(r.created_at)}</small></div>
        <button class="ad-btn sub" data-nedit="${r.id}">수정</button><button class="ad-btn sub ad-del" data-ndel="${r.id}">삭제</button></div>`).join('') || '<div class="ad-msg">공지 없음</div>'}</div>`;
    const body = $('ad-nbody'); body.oninput = () => { $('ad-ncnt').textContent = `${body.value.length}/200`; };
    if ($('ad-ncancel')) $('ad-ncancel').onclick = () => renderNotices();
    $('ad-nsave').onclick = async () => {
      const t = body.value.trim(); if (!t) { $('ad-nmsg').innerHTML = '<span class="ad-err">내용을 써 주세요</span>'; return; }
      try { await rpc('admin_notice_save', { p_id: cur?.id ?? null, p_body: t, p_pinned: $('ad-npin').checked }); renderNotices(); }
      catch (e) { $('ad-nmsg').innerHTML = `<span class="ad-err">실패: ${esc(e.message)}</span>`; }
    };
    v.querySelectorAll('[data-nedit]').forEach(b => b.onclick = () => renderNotices(+b.dataset.nedit));
    v.querySelectorAll('[data-ndel]').forEach(b => b.onclick = async () => {
      if (!confirm('이 공지를 삭제할까요?')) return;
      try { await rpc('admin_notice_delete', { p_id: +b.dataset.ndel }); renderNotices(); } catch (e) { alert('삭제 실패: ' + e.message); }
    });
  }
  async function openUser(id) {
    const m = $('ad-modal'), box = $('ad-detail'); m.classList.remove('hidden'); box.innerHTML = '<div class="ad-msg">불러오는 중...</div>';
    let d, log, qd = null, wl = null, pl = null, gm = null;
    try { [d, log, qd, wl, pl, gm] = await Promise.all([rpc('admin_user_detail', { p_user: id }), rpc('admin_gacha_log', { p_user: id, p_limit: 200 }), rpc('admin_user_quest', { p_user: id }).catch(() => null), rpc('admin_user_wallet', { p_user: id }).catch(() => null), rpc('admin_user_player', { p_user: id }).catch(() => null), rpc('admin_gem_ledger', { p_user: id, p_limit: 50 }).catch(() => null)]); }
    catch (e) { box.innerHTML = `<div class="ad-err">${esc(e?.message)}</div>`; return; }
    const owned = d.owned || [], cleared = d.cleared || {}, r = d.record || {};
    const kv = (k, v) => `<div><span>${k}</span>${v}</div>`;
    const ownedSorted = owned.slice().sort((a, b) => (b.uid === d.leader) - (a.uid === d.leader) || (b.level | 0) - (a.level | 0));
    box.innerHTML = `<h2 style="margin:0 0 4px;font-size:17px">${esc(d.name || d.nickname || d.email)}</h2><div style="opacity:.75">${esc(d.email)}</div>
      <div class="ad-sec"><div class="ad-kv">${kv('가입', fmt(d.created_at))}${kv('마지막 로그인', fmt(d.last_sign_in_at))}${kv('소환권', `<b id="ad-tk">${d.tickets}</b>장`)}${kv('아케이드', `${r.wins | 0}승 ${r.losses | 0}패 ${r.draws | 0}무`)}${kv('스토리', Object.entries(cleared).map(([c, l]) => `챕터${esc(c)} ${(l || []).length}`).join(' · ') || '-')}${kv('갤러리', `${d.gallery?.cards | 0}종 · MVP ${d.gallery?.mvp | 0}`)}${kv('스탯 포인트', esc(d.points))}${CUR.map(([k, ic, nm]) => kv(`${ic} ${nm}`, wl ? `<b id="ad-w-${k}">${Number(wl[k] || 0).toLocaleString('ko-KR')}</b>` : '-')).join('')}${kv('플레이어', pl ? `Lv.${pl.level} · 경험치 ${pl.xp}/${pl.xp_next || '-'}` : '-')}${kv('🔋 행동력', pl ? `${pl.stamina}/${pl.stamina_max}` : '-')}${kv('시련의 탑', qd ? `최고 ${qd.best_floor | 0}층 · 승리 ${qd.clears | 0}회` : '-')}</div></div>
      <div class="ad-sec"><h3>🎟️ 소환권 지급</h3><div class="ad-grant"><input type="number" id="ad-amt" min="1" max="1000" value="10"><input type="text" id="ad-reason" maxlength="200" placeholder="사유 (필수, 기록됨)"><button class="ad-btn" id="ad-give">지급</button></div><div id="ad-gmsg" style="margin-top:4px"></div></div>
      <div class="ad-sec"><h3>💰 재화 지급 / 회수</h3>${wl ? `<div class="ad-grant"><select id="ad-ck">${CUR.map(([k, ic, nm]) => `<option value="${k}">${ic} ${nm}</option>`).join('')}</select><input type="number" id="ad-camt" min="-1000000" max="1000000" value="100"><input type="text" id="ad-creason" maxlength="200" placeholder="사유 (필수, 기록됨 · 음수 = 회수)"><button class="ad-btn" id="ad-cgive">적용</button></div><div id="ad-cmsg" style="margin-top:4px"></div>` : '<div class="ad-msg">supabase/phaseE_1.sql 을 실행하면 사용할 수 있어요</div>'}</div>
      <div class="ad-sec"><h3>🔮 심연석 <b id="ad-gem">${gm ? Number(gm.gem).toLocaleString('ko-KR') : '-'}</b> <small>${gm ? `무료 ${gm.free} · 유료 ${gm.paid}` : ''}</small></h3>${gm ? `<div class="ad-grant"><input type="number" id="ad-gamt" min="-1000000" max="1000000" value="100"><input type="text" id="ad-greason" maxlength="200" placeholder="사유 (필수, 기록됨 · 음수 = 회수 · 무료분)"><button class="ad-btn" id="ad-ggive">적용</button></div><div id="ad-gmsg2" style="margin-top:4px"></div>
        <div class="ad-cards" style="max-height:180px;overflow:auto;display:block">${gm.log.map(x => `<div style="font-size:12px">${esc(fmt(x.at))} · ${esc(x.reason)} · <b>${x.d_free + x.d_paid > 0 ? '+' : ''}${x.d_free + x.d_paid}</b>${x.d_paid ? ` (유료 ${x.d_paid})` : ''} → ${x.free_after + x.paid_after} <small style="opacity:.6">${esc(x.ref)}</small></div>`).join('') || '기록 없음'}</div>` : '<div class="ad-msg">supabase/gem.sql 을 실행하면 사용할 수 있어요</div>'}</div>
      <div class="ad-sec"><h3>보유 카드 (${owned.length}장)</h3><div class="ad-cards">${ownedSorted.map(o => `<span class="ad-chip ${o.uid === d.leader ? 'lead' : ''}">${o.uid === d.leader ? '👑 ' : ''}${esc(SHORT[names.get(String(o.id))?.grade] || '')} ${esc(cname(o.id))} Lv.${o.level | 0}${o.ex ? ` EX${o.ex}` : ''}</span>`).join('') || '없음'}</div></div>
      <div class="ad-sec"><h3>최근 아케이드 판</h3><div class="ad-wrap"><table class="ad-table"><thead><tr><th>시각</th><th>결과</th><th>턴</th><th>피해</th><th>MVP</th></tr></thead><tbody>${(d.recent || []).map(x => `<tr><td>${fmt(x.created_at)}</td><td>${({ win: '승', lose: '패', draw: '무' })[x.result] || esc(x.result)}</td><td>${x.turns ?? ''}</td><td>${x.damage ?? ''}</td><td>${esc(x.mvp_name)}</td></tr>`).join('') || '<tr><td colspan="5">기록 없음</td></tr>'}</tbody></table></div></div>
      <div class="ad-sec"><h3>뽑기 기록 (${(log || []).length})</h3><div class="ad-wrap"><table class="ad-table"><thead><tr><th>시각</th><th>종류</th><th>등급</th><th>카드</th></tr></thead><tbody>${(log || []).map(x => `<tr><td>${fmt(x.created_at)}</td><td>${x.kind === 'ticket' ? '소환권' : x.kind === 'daily' ? '매일 뽑기' : esc(x.kind)}</td><td>${esc(SHORT[x.grade] || x.grade)}</td><td>${esc(cname(x.card_id))}</td></tr>`).join('') || '<tr><td colspan="4">기록 없음</td></tr>'}</tbody></table></div></div>`;
    $('ad-give').onclick = async () => {
      const amt = +$('ad-amt').value | 0, reason = $('ad-reason').value.trim(), msg = $('ad-gmsg');
      if (amt < 1 || amt > 1000) { msg.innerHTML = '<span class="ad-err">1~1000장만 지급할 수 있어요</span>'; return; }
      if (!reason) { msg.innerHTML = '<span class="ad-err">사유를 적어 주세요</span>'; return; }
      if (!confirm(`${d.email} 에게 소환권 ${amt}장을 지급할까요?`)) return;
      $('ad-give').disabled = true;
      try { const res = await rpc('admin_grant_tickets', { p_user: id, p_amount: amt, p_reason: reason }); $('ad-tk').textContent = res.tickets; msg.innerHTML = `<span class="ad-ok">지급 완료: ${res.before} → ${res.tickets}장</span>`; $('ad-reason').value = ''; }
      catch (e) { msg.innerHTML = `<span class="ad-err">${esc(e?.message)}</span>`; }
      finally { $('ad-give').disabled = false; }
    };
    bindCurrency(id, d); bindGem(id, d);
  }
  function bindGem(id, d) {
    const btn = $('ad-ggive'); if (!btn) return;
    btn.onclick = async () => {
      const amt = Math.trunc(+$('ad-gamt').value || 0), reason = $('ad-greason').value.trim(), msg = $('ad-gmsg2');
      if (!amt || Math.abs(amt) > 1000000) { msg.innerHTML = '<span class="ad-err">±1~1,000,000 사이로 적어 주세요</span>'; return; }
      if (!reason) { msg.innerHTML = '<span class="ad-err">사유를 적어 주세요</span>'; return; }
      if (!confirm(`${d.email} 에게 심연석 ${amt > 0 ? `${amt} 지급` : `${-amt} 회수`}할까요?`)) return;
      btn.disabled = true;
      try { const res = await rpc('admin_grant_gem', { p_user: id, p_amount: amt, p_reason: reason }); $('ad-gem').textContent = Number(res.after).toLocaleString('ko-KR'); msg.innerHTML = `<span class="ad-ok">완료: ${res.before} → ${res.after}</span>`; $('ad-greason').value = ''; }
      catch (e) { msg.innerHTML = `<span class="ad-err">${esc(/not enough/.test(e?.message) ? '무료 잔액보다 많이 회수할 수 없어요' : e?.message)}</span>`; }
      finally { btn.disabled = false; }
    };
  }
  function bindCurrency(id, d) {
    const btn = $('ad-cgive'); if (!btn) return;
    btn.onclick = async () => {
      const key = $('ad-ck').value, amt = Math.trunc(+$('ad-camt').value || 0), reason = $('ad-creason').value.trim(), msg = $('ad-cmsg');
      const nm = (CUR.find(c => c[0] === key) || [])[2] || key;
      if (!amt || Math.abs(amt) > 1000000) { msg.innerHTML = '<span class="ad-err">±1~1,000,000 사이로 적어 주세요</span>'; return; }
      if (!reason) { msg.innerHTML = '<span class="ad-err">사유를 적어 주세요</span>'; return; }
      if (!confirm(`${d.email} 에게 ${nm} ${amt > 0 ? `${amt} 지급` : `${-amt} 회수`}할까요?`)) return;
      btn.disabled = true;
      try { const res = await rpc('admin_grant_currency', { p_user: id, p_key: key, p_amount: amt, p_reason: reason }); $(`ad-w-${key}`).textContent = Number(res.after).toLocaleString('ko-KR'); msg.innerHTML = `<span class="ad-ok">완료: ${nm} ${res.before} → ${res.after}</span>`; $('ad-creason').value = ''; }
      catch (e) { msg.innerHTML = `<span class="ad-err">${esc(/not enough/.test(e?.message) ? '잔액보다 많이 회수할 수 없어요' : e?.message)}</span>`; }
      finally { btn.disabled = false; }
    };
  }
  function closeModal() { $('ad-modal').classList.add('hidden'); if (tab === 'users') renderUsers($('ad-q')?.value.trim() || ''); }
  $('ad-modal').addEventListener('click', e => { if (e.target.id === 'ad-modal' || e.target.closest('#ad-close')) closeModal(); });   // 바깥 클릭 = 닫기
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && !$('ad-modal').classList.contains('hidden')) closeModal(); });
  window.VRAdmin = { boot, openUser };
  if (!window.__ADMIN_NO_BOOT) boot();
})();
