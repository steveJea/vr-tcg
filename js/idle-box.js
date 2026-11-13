// ===== 🎁 방치 보상 상자 — 서버: supabase/idle_box.sql =====
// 버튼: [data-idlebtn] (메인 상단 📅·🏆 옆) · 쌓인 보상 있으면 빨간 점
// SQL 실행 전이거나 비로그인이면 버튼이 안 보임
// 무료 드링크 (supabase/idle_drink_staging.sql): 쌓인 2시간당 1개 · 귀속(거래 불가). SQL 전이면 드링크 줄은 안 보임
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, off = false, acting = false;
  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { off = true; paint(); return null; } throw error; }
    return data;
  }
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const rwText = r => [
    r?.gold && `🪙 ${n(r.gold)}`,
    r?.shard && `💠 ${n(r.shard)}`,
    r?.blood && `🩸 ${n(r.blood)}`,
    r?.dust && `✨ ${n(r.dust)}`,
    r?.drink && `🥤 드링크 ${n(r.drink)}`,
  ].filter(Boolean).join(' · ');
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = {
    'not done': '아직 쌓인 보상이 없어요', 'login required': '로그인이 필요해요',
    'daily limit': '오늘은 빠른 보상을 다 썼어요', 'not enough gem': '심연석이 부족해요 (빠른 보상은 유료예요)',
    'dust unavailable': '장비 가루를 줄 수 없어요',
  };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  function set(s) { if (s?.ok) { cache = s; paint(); } return cache; }
  async function status() {
    if (off) return null;
    try { return set(await rpc('idle_box_status')); } catch (e) { console.warn('[idle]', e?.message); return null; }
  }
  function paint() {
    const ws = document.querySelectorAll('[data-idlebtn]');
    for (const w of ws) {
      if (off || !window.VRCloud?.user) { w.innerHTML = ''; continue; }
      if (!w.querySelector('.idle-btn')) {
        w.innerHTML = '<button class="story-mailbtn idle-btn" type="button" aria-label="방치 보상" title="방치 보상"><img class="ui-btn-ic" src="img/ui/icon/idle_box.webp" alt="보상" width="20" height="20"><span>보상</span></button>';
        w.firstChild.onclick = open;
      }
      const b = w.firstChild; b.querySelector('.story-badge')?.remove();
      if (cache?.ready) b.insertAdjacentHTML('beforeend', '<i class="story-badge">!</i>');
    }
  }
  async function act(fn) {
    if (acting) return; acting = true;
    try {
      const r = await rpc(fn); if (!r) return;
      set(r);
      toast(`🎁 ${rwText(r.got || {}) || '받음'}`);
      if (r.wallet) window.VRPlayer?.setWallet?.(r.wallet);
      if (r.gem) window.VRGem?.status?.(true);
      if (r.got?.drink) window.VRDrink?.status?.();
      window.VRPlayer?.status?.(true);
    } catch (e) { toast(errText(e)); } finally { acting = false; }
  }
  function hrsTxt(h) {
    const x = Number(h) || 0;
    if (x <= 0) return '0분';
    const m = Math.floor(x * 60), hh = Math.floor(m / 60), mm = m % 60;
    if (hh <= 0) return `${mm}분`;
    return mm ? `${hh}시간 ${mm}분` : `${hh}시간`;
  }
  function open() {
    document.querySelector('.idle-pop:not(.vr-in-page)')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop idle-pop';
    const draw = () => {
      const s = cache;
      if (!s) { pop.innerHTML = '<div class="gem-panel daily-panel idle-panel">불러오는 중...</div>'; return; }
      const p = s.pending || {}, rate = s.rate || {}, b = s.boost || {};
      const pct = Math.min(100, Math.round((Number(s.hours) || 0) / (Number(s.max_hours) || 8) * 100));
      pop.innerHTML = `<div class="gem-panel daily-panel idle-panel" role="dialog" aria-label="방치 보상"><button class="gem-x" data-x aria-label="닫기">✕</button>
        <h3 class="daily-h">🎁 방치 보상 <small>Lv.${s.level}</small></h3>
        <div class="idle-bar-wrap"><div class="daily-bar idle-bar"><i style="width:${pct}%"></i></div>
          <small>${hrsTxt(s.hours)} / ${s.max_hours}시간${s.full ? ' · 가득' : ''}</small></div>
        <div class="idle-got">${rwText(p) || '—'}</div>
        <div class="idle-rate">시간당 ${rwText(rate)}${rate.drink_every_h ? ` · 🥤 드링크 ${rate.drink_every_h}시간당 1` : ''}</div>
        ${s.drink ? `<div class="idle-drink-note">무료 드링크 (거래 불가) · ${s.full ? '가득 찼어요' : `다음 1개까지 ${hrsTxt(s.drink.next_in_h)}`} · 한 번에 최대 ${s.drink.max_per_claim}개</div>` : ''}
        <button class="daily-claim" data-claim ${s.ready ? '' : 'disabled'}>쌓인 보상 받기 (무료)</button>
        <div class="idle-boost">
          <div class="idle-boost-h"><b>⚡ 빠른 보상 (심연석 사용)</b><small>오늘 ${b.left ?? 0}/${b.max ?? 2}</small></div>
          <div class="idle-boost-r">${rwText(b.reward)}</div>
          <button class="daily-claim idle-boost-btn" data-boost ${(b.left | 0) < 1 ? 'disabled' : ''}>심연석 ${n(b.cost ?? 30)}개로 ${b.hours ?? 4}시간분 받기</button>
        </div></div>`;
      pop.querySelector('[data-x]').onclick = () => pop.remove();
      pop.querySelector('[data-claim]')?.addEventListener('click', async e => {
        e.currentTarget.disabled = true; await act('idle_box_claim'); draw();
      });
      pop.querySelector('[data-boost]')?.addEventListener('click', async e => {
        e.currentTarget.disabled = true;
        const msg = `심연석 ${n(b.cost ?? 30)}개를 사용해 ${b.hours ?? 4}시간분 보상을 받을까요?`;
        try {
          const ok = await (window.VRAsk ? window.VRAsk(msg) : confirm(msg));
          if (ok && pop.isConnected) await act('idle_box_boost');
        } finally { draw(); }
      });
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    if (!window.VRPages?.host?.('idle-box', '🎁 방치 보상', pop)) document.body.appendChild(pop);
    draw(); status().then(draw);
  }
  window.VRIdleBox = { open, status, paint };
  setTimeout(() => { paint(); status(); }, 1700);
  setTimeout(() => { paint(); status(); }, 4500);
  new MutationObserver(() => { if (document.querySelector('[data-idlebtn]:empty')) paint(); }).observe(document.body, { childList: true, subtree: true });
})();
