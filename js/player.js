// ===== 플레이어 레벨 · 행동력 (단계 E-2) =====
// 서버: supabase/phaseE_2.sql (player_status / story_abort_phase, 스토리 시작·완료 RPC 가 행동력·경험치 처리)
// SQL 실행 전이거나 비로그인이면 status() 는 null → 화면에서 숨기고 스토리는 예전처럼 동작
// 화면 표시: <span data-vr-player></span> 을 넣고 VRPlayer.paint() (1초마다 회복 남은 시간 갱신)
(() => {
  const cloud = () => window.__PLAYER_MOCK?.cloud || window.VRCloud;
  const missing = e => /PGRST202|PGRST205|42883|42P01|Could not find|does not exist/i.test(`${e?.code} ${e?.message}`);
  let cache = null, at = 0, pending = null, timer = null;
  async function rpc(name, args) {
    const m = window.__PLAYER_MOCK; if (m?.rpc) return m.rpc(name, args);
    const sb = cloud()?.sb; if (!sb || !cloud()?.user) return null;
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (missing(error)) return null; throw error; }
    return data;
  }
  function set(s) { if (s && s.ok) { cache = s; at = Date.now(); paint(); } return cache; }
  async function status(force = false) {
    if (!force && cache && Date.now() - at < 30000) return now();
    if (!pending) pending = rpc('player_status').then(set).catch(e => { console.warn('[player]', e?.message); return null; }).finally(() => { pending = null; });
    await pending; return now();
  }
  /** 캐시 + 지난 시간으로 지금 값 추정 (서버 값이 기준, 화면 표시용) */
  function now() {
    if (!cache) return null;
    const s = { ...cache }, el = Math.floor((Date.now() - at) / 1000);
    if (s.stamina < s.stamina_max && s.next_regen_secs > 0) {
      let left = s.next_regen_secs - el;
      while (left <= 0 && s.stamina < s.stamina_max) { s.stamina++; left += s.regen_secs; }
      s.next_regen_secs = s.stamina >= s.stamina_max ? 0 : left;
    }
    return s;
  }
  async function abort() { try { return set(await rpc('story_abort_phase')); } catch (e) { console.warn('[player] abort', e?.message); return null; } }
  const mmss = t => `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
  function chip(s = now()) {
    if (!s) return '';
    const full = s.stamina >= s.stamina_max;
    return `<span class="vrp-lv" title="플레이어 레벨">Lv.${s.level}</span><span class="vrp-st ${s.stamina < (s.cost?.story || 6) ? 'low' : ''}" title="행동력 · 6분에 1 회복">🔋 <b>${s.stamina}</b>/${s.stamina_max}${full ? '' : `<small>+1 ${mmss(s.next_regen_secs)}</small>`}</span>`;
  }
  function paint() {
    const els = document.querySelectorAll('[data-vr-player]'); if (!els.length) return;
    const h = chip(); els.forEach(e => { e.innerHTML = h; e.classList.toggle('vrp-chip', !!h); });
    if (!timer) timer = setInterval(() => { if (!document.querySelector('[data-vr-player]')) { clearInterval(timer); timer = null; return; } paint(); }, 1000);
  }
  /** 이후 단계 해금 확인용 (서버가 최종 판단) */
  const unlocked = key => { const s = now(); return !!s && s.level >= (s.unlocks?.[key] ?? Infinity); };
  /** 재화 표시: { gold, blood, shard, soul } → "🪙 +120 · 🩸 +12 · 💠 +1" (0 은 생략) */
  const CUR_IC = [['gold', '🪙', '골드'], ['blood', '🩸', '순수한 피'], ['shard', '💠', '이상한 조각'], ['soul', '🔥', '각성자의 혼']];
  const curTxt = c => CUR_IC.filter(([k]) => (c?.[k] | 0) > 0).map(([k, i, n]) => `<span class="vr-cur" title="${n}">${window.VRIcon?.cur?.(k, { alt: n }) || i} +${Number(c[k]).toLocaleString('ko-KR')}</span>`).join(' · ') || '<span class="text-zinc-500">없음</span>';
  // 지갑 (phaseE_1.sql wallet_status). 캐시 + 서버 응답의 wallet 으로 갱신
  let wcache = null, wat = 0;
  async function wallet(force = false) {
    if (!force && wcache && Date.now() - wat < 30000) return wcache;
    try { const w = await rpc('wallet_status'); if (w?.ok) { wcache = w; wat = Date.now(); } } catch (e) { console.warn('[wallet]', e?.message); }
    return wcache;
  }
  const setWallet = w => { if (w && typeof w.gold !== 'undefined') { wcache = { ok: true, ...w }; wat = Date.now(); } return wcache; };
  window.VRPlayer = { curTxt, wallet, setWallet, get walletNow() { return wcache; }, status, now, set, abort, chip, paint, unlocked, mmss, get cost() { return cache?.cost?.story ?? 6; }, _reset() { cache = null; at = 0; } };
})();
