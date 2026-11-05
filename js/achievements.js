// ===== 🏆 업적 — 서버: supabase/achievements.sql =====
// 버튼: [data-achbtn] (메인 상단 📅 옆) · 받을 수 있는 보상 수 뱃지 · 진행·달성은 서버 계산
// SQL 실행 전이거나 비로그인이면 버튼이 안 보임
(() => {
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, off = false, tab = 'growth';
  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) { off = true; paint(); return null; } throw error; }
    return data;
  }
  const n = v => Number(v || 0).toLocaleString('ko-KR');
  const rwText = r => [r?.gold && `🪙 ${n(r.gold)}`, r?.gem && `🔮 ${n(r.gem)}`, r?.tickets && `🎟️ ${r.tickets}`].filter(Boolean).join(' · ');
  function toast(t) { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const ERR = { 'already claimed': '이미 받았어요', 'not done': '아직 완료하지 않았어요', 'login required': '로그인이 필요해요', 'invalid key': '잘못된 요청이에요' };
  const errText = e => { const m = String(e?.message || e); const k = Object.keys(ERR).find(x => m.includes(x)); return k ? ERR[k] : m.slice(0, 60); };
  const TIER_LABEL = { pvp_tier: { 1: '실버', 2: '골드', 3: '플래티넘', 4: '다이아' } };
  function goalTxt(it) {
    if (it.id === 'pvp_tier') return TIER_LABEL.pvp_tier[it.goal] || it.goal;
    if (it.id === 'guild_join') return '가입';
    if (it.unit) return `${n(it.goal)}${it.unit}`;
    return n(it.goal);
  }
  function progTxt(it) {
    if (it.id === 'pvp_tier') return TIER_LABEL.pvp_tier[it.raw] || (it.raw > 0 ? n(it.raw) : '브론즈');
    if (it.id === 'guild_join') return it.raw >= 1 ? '가입' : '미가입';
    if (it.unit) return `${n(it.raw)}${it.unit}`;
    return n(it.raw);
  }
  function set(s) { if (s?.ok) { cache = s; paint(); } return cache; }
  async function status() {
    if (off) return null;
    try { return set(await rpc('achievements_status')); } catch (e) { console.warn('[ach]', e?.message); return null; }
  }
  function paint() {
    const ws = document.querySelectorAll('[data-achbtn]');
    for (const w of ws) {
      if (off || !window.VRCloud?.user) { w.innerHTML = ''; continue; }
      if (!w.querySelector('.ach-btn')) { w.innerHTML = '<button class="story-mailbtn ach-btn" type="button" aria-label="업적" title="업적"><img class="ui-btn-ic" src="img/ui/icon/achievement.webp" alt="업적" width="20" height="20"><span>업적</span></button>'; w.firstChild.onclick = open; }
      const b = w.firstChild; b.querySelector('.story-badge')?.remove();
      const k = cache?.ready | 0;
      if (k > 0) b.insertAdjacentHTML('beforeend', `<i class="story-badge">${k}</i>`);
    }
  }
  async function claim(fn, args) {
    try {
      const r = await rpc(fn, args); if (!r) return;
      set(r);
      const got = r.got || {};
      toast(`🎁 ${r.claimed_n ? `${r.claimed_n}개 · ` : ''}${rwText(got) || '받음'}`);
      if (r.wallet) window.VRPlayer?.setWallet?.(r.wallet);
      if (got.gem) window.VRGem?.status?.(true);
      window.VRPlayer?.status?.(true);
    } catch (e) { toast(errText(e)); }
  }
  function groupRows(items) {
    const map = new Map();
    for (const it of items || []) {
      if (!map.has(it.id)) map.set(it.id, []);
      map.get(it.id).push(it);
    }
    return [...map.values()];
  }
  function rowsHtml(items) {
    return groupRows(items).map(group => {
      const head = group[0];
      const next = group.find(x => !x.claimed) || group[group.length - 1];
      const pct = next.goal ? Math.min(100, Math.round((next.raw / next.goal) * 100)) : 0;
      const tiers = group.map(it => {
        const ok = it.ready, done = it.claimed;
        return `<div class="ach-tier ${done ? 'done' : ''} ${ok ? 'ready' : ''}">
          <div class="ach-tt"><b>${goalTxt(it)}</b><small>${rwText(it.reward)}${it.pts ? ` · +${it.pts}점` : ''}</small></div>
          <button class="daily-claim sm" data-k="${it.key}" ${done || !ok ? 'disabled' : ''}>${done ? '완료' : ok ? '받기' : `${progTxt(it)}`}</button>
        </div>`;
      }).join('');
      return `<div class="ach-m ${group.every(x => x.claimed) ? 'done' : ''}">
        <div class="ach-mh"><b>${head.name}</b><small>${progTxt(next)} / ${goalTxt(next)}</small>
          <div class="daily-bar"><i style="width:${pct}%"></i></div></div>
        <div class="ach-tiers">${tiers}</div></div>`;
    }).join('');
  }
  function open() {
    document.querySelector('.ach-pop:not(.vr-in-page)')?.remove();
    const pop = document.createElement('div'); pop.className = 'gem-pop ach-pop';
    const draw = () => {
      const s = cache;
      if (!s) { pop.innerHTML = '<div class="gem-panel daily-panel ach-panel">불러오는 중...</div>'; return; }
      const cats = s.cats || [];
      if (!cats.some(c => c.id === tab)) tab = cats[0]?.id || 'growth';
      const cur = cats.find(c => c.id === tab) || cats[0];
      pop.innerHTML = `<div class="gem-panel daily-panel ach-panel" role="dialog" aria-label="업적"><button class="gem-x" data-x aria-label="닫기">✕</button>
        <h3 class="daily-h">🏆 업적 <small>${n(s.score)}점</small></h3>
        <div class="ach-score">${(s.score_items || []).map(it => {
          const done = it.claimed, ok = it.ready;
          return `<div class="ach-score-i ${done ? 'done' : ''} ${ok ? 'ready' : ''}"><b>${n(it.goal)}점</b><span>${rwText(it.reward)}</span>
            <button class="daily-claim sm" data-k="${it.key}" ${done || !ok ? 'disabled' : ''}>${done ? '완료' : ok ? '받기' : `${n(s.score)}`}</button></div>`;
        }).join('')}</div>
        <div class="ach-tabs">${cats.map(c => {
          const r = (c.items || []).filter(x => x.ready).length;
          return `<button type="button" class="ach-tab ${c.id === tab ? 'on' : ''}" data-tab="${c.id}">${c.name}${r ? `<i class="story-badge">${r}</i>` : ''}</button>`;
        }).join('')}</div>
        <div class="ach-tools"><button class="daily-claim" data-all ${(s.ready | 0) < 1 ? 'disabled' : ''}>모두 받기${s.ready ? ` (${s.ready})` : ''}</button></div>
        <div class="ach-list">${rowsHtml(cur?.items)}</div></div>`;
      pop.querySelector('[data-x]').onclick = () => pop.remove();
      pop.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => { tab = b.dataset.tab; draw(); });
      pop.querySelectorAll('[data-k]').forEach(b => b.onclick = async () => { await claim('achievements_claim', { p_key: b.dataset.k }); draw(); });
      pop.querySelector('[data-all]')?.addEventListener('click', async () => { await claim('achievements_claim_all'); draw(); });
    };
    pop.onclick = e => { if (e.target === pop) pop.remove(); };
    if (!window.VRPages?.host?.('achievements', '🏆 업적', pop)) document.body.appendChild(pop);
    draw(); status().then(draw);
  }
  window.VRAchievements = { open, status, paint };
  setTimeout(() => { paint(); status(); }, 1600);
  setTimeout(() => { paint(); status(); }, 4200);
  new MutationObserver(() => { if (document.querySelector('[data-achbtn]:empty')) paint(); }).observe(document.body, { childList: true, subtree: true });
})();
