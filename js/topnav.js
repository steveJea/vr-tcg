// ===== 통합 상단 바 (TNB) — 하단 GNB와 같은 금색·어두운 톤 =====
// 1줄: 왼쪽(로비 = 프로필·레벨 / 스토리 허브 = ⌂ / 그 밖 = ←) · 가운데 제목 · 오른쪽 📮 우편 · ⚙ 설정
// 2줄: Lv · 🔋 행동력(스토리·탑만) · 🔮 심연석 · 🪙 골드 · 🥤 드링크 (+ = 심연석 상점). PC(768px~)는 한 줄
// 전투·대사·영상·확인창(GNB busy())·큰 팝업 중엔 숨김. 전투 HUD는 그대로.
// ← 는 기존 화면의 뒤로 버튼을 그대로 누름 (VRPages 뒤로 쌓기 · 스토리 화면 '처음으로/스토리 메인' 동작 유지)
// 끄기: localStorage vrTnb=0 (예전 머리줄이 그대로 보임)
// 그림 교체: 아래 ART 표의 파일을 img/ui/topnav/ 에 넣으면 자동으로 이모지·CSS 대신 씀 (없으면 그대로)
(() => {
  if (localStorage.getItem('vrTnb') === '0') return;
  const $ = id => document.getElementById(id), V = () => window.VRPages;
  const vis = el => !!el && !el.classList.contains('hidden') && getComputedStyle(el).display !== 'none' && el.getClientRects().length > 0;
  const ART_DIR = 'img/ui/topnav/';
  // 그림순이 에셋 (img/ui/topnav/*_v1.webp). 그림이 안 뜨면 이모지·CSS로 대신 보여줌
  const ART = {
    back: ['btn_back_normal_v1.webp', 'btn_back_pressed_v1.webp', '←'], home: ['btn_home_normal_v1.webp', 'btn_home_pressed_v1.webp', '⌂'],
    mail: ['btn_mail_normal_v1.webp', 'btn_mail_pressed_v1.webp', '📮'], settings: ['btn_settings_normal_v1.webp', 'btn_settings_pressed_v1.webp', '⚙️'],
    gem: ['cur_abyss_48_v1.webp', null, '🔮'], stamina: ['cur_stamina_48_v1.webp', null, '🔋'], plus: ['chip_plus_v1.webp', null, '+'],
    // CSS 에서 쓰는 것: topbar_bg_mobile / topbar_bg_pc_9slice / chip_frame_9slice / badge_number_9slice / badge_dot / lv_badge_frame / profile_ring (css/topnav.css)
  };
  const CUR_IMG = { gold: 'img/ui/cur_gold.webp', drink: 'img/ui/cur_drink.webp' };   // 이미 있는 그림
  const FB = "this.closest('.tnb-btn,.tnb-ici')?.classList.add('noart');this.remove()";
  const ic = k => { const [nm, pr, em] = ART[k];
    return pr ? `<img class="tnb-art" src="${ART_DIR}${nm}" alt="" onerror="${FB}"><img class="tnb-art tnb-pr" src="${ART_DIR}${pr}" alt="" onerror="this.remove()"><span class="tnb-em">${em}</span>`
      : `<span class="tnb-ici"><img src="${ART_DIR}${nm}" alt="" onerror="${FB}"><span class="tnb-em">${em}</span></span>`; };
  const full = v => (v | 0).toLocaleString('ko-KR');
  // 폰(767px 이하)은 1만 넘으면 84.2k 처럼 줄임 (정확한 값은 title·aria) — 칩 6개가 390·360 한 줄에 들어가게
  const n = v => (v | 0) >= 1e6 ? (Math.floor(v / 1e5) / 10) + 'M' : (v | 0) >= 1e4 && innerWidth < 768 ? (Math.floor(v / 100) / 10) + 'k' : full(v);
  const bar = document.createElement('header');
  bar.id = 'vr-tnb'; bar.setAttribute('aria-label', '상단 메뉴');
  document.body.classList.add('tnb-on');
  const build = () => {
    bar.innerHTML = `<div class="tnb-r1"><div class="tnb-l"><button type="button" class="tnb-btn tnb-back" aria-label="뒤로">${ic('back')}</button><div class="tnb-acct"></div></div>
      <h1 class="tnb-t"></h1>
      <div class="tnb-r"><button type="button" class="tnb-btn tnb-mail" aria-label="우편함">${ic('mail')}<i class="tnb-badge" hidden></i></button><button type="button" class="tnb-btn tnb-set" aria-label="설정">${ic('settings')}</button></div></div>
      <div class="tnb-r2"><span class="tnb-chip tnb-lv" hidden></span><span class="tnb-chip tnb-st" hidden></span><span class="tnb-sp"></span>
        <button type="button" class="tnb-chip tnb-cur" data-cur="gem" hidden></button><button type="button" class="tnb-chip tnb-cur" data-cur="gold" hidden></button><button type="button" class="tnb-chip tnb-cur" data-cur="drink" hidden></button></div>`;
    bar.querySelector('.tnb-back').onclick = back;
    bar.querySelector('.tnb-mail').onclick = () => { const G = window.VRGear; if (G && !G.off) G.mailbox({ back: () => G.unread?.() }); else document.querySelector('.story-mailbtn')?.click(); };
    bar.querySelector('.tnb-set').onclick = () => { if (where() === 'lobby') $('main-settings')?.click(); else window.VRSettings?.open?.(); };
    bar.querySelectorAll('[data-cur]').forEach(b => b.onclick = () => window.VRGem?.open?.());
  };
  build();
  document.body.appendChild(bar);
  document.addEventListener('vr-mail-unread', e => { const b = bar.querySelector('.tnb-badge'); b.hidden = !(e.detail > 0); b.textContent = e.detail > 99 ? '99+' : e.detail; });
  // 지금 어느 화면인지
  const SS = () => $('story-screen');
  function where() {
    if (V()?.depth) return 'page';
    if (vis(SS())) { const s = SS(); if (s.querySelector('.hub-top')) return 'hub'; if (s.querySelector('.gr-banners, #gacha-stage, #tk-result')) return 'gacha'; if (s.querySelector('.story-map-screen')) return 'map'; return 'story'; }
    return 'lobby';
  }
  function title(w) {
    if (w === 'page') return document.querySelector('#vr-page .vr-page-title')?.textContent?.trim() || '';
    if (w === 'hub') return SS()?.querySelector('.hub-title')?.textContent?.trim() || '📜 스토리';
    if (w === 'gacha') return '🎴 인재 영입';
    const t = SS()?.querySelector('.story-top-title')?.textContent?.trim();
    if (t) return t;
    if (w === 'map') { const c = SS()?.querySelector('.story-map-ch b, .story-map-title, .smap-title')?.textContent?.trim(); return c || '챕터 지도'; }
    return '';
  }
  function back() {
    if (V()?.closeOverlays?.()) return;   // 떠 있는 작은 창이 있으면 그것부터 닫음 (뒤로가기와 같은 순서)
    const w = where();
    if (w === 'page') { const b = document.querySelector('#vr-page .vr-page-back'); if (b) return b.click(); return V().back(); }
    // 스토리 화면: 그 화면의 뒤로 버튼(처음으로 / 스토리 메인 / 탑 목록 / 돌아가기)을 그대로 누름
    const b = SS()?.querySelector('.story-back, #q-home'); if (b) return b.click();
    window.VRStory?.api?.home?.();
  }
  const overlay = () => !!document.querySelector('.gem-pop, .main-pop:not(.hidden), .tr-bg:not(.vr-in-page), #story-pop:not(.hidden), .gal-detail, #detail:not(.hidden), #vr-mailbox, .gear-pop, .vr-mail-pop');
  const busy = () => (window.VRGnb?.busy?.() ?? (vis($('game')))) || vis($('game')) || overlay();
  let last = '';
  function paint(force) {
    const hide = busy(); bar.classList.toggle('tnb-hide', hide); document.body.classList.toggle('tnb-hidden', hide);
    if (hide && !force) return;
    const w = where(), cq = V()?.current || '';
    const st = w === 'hub' || w === 'map' || w === 'story' || cq === 'quest';
    const P = window.VRPlayer?.now?.(), W = window.VRPlayer?.walletNow, G = window.VRGem?.now, D = window.VRDrink?.now;
    const acct = bar.querySelector('.tnb-acct'), box = $('acct-box');
    // 로비: 계정 칩(cloud.js 가 그림)을 바 왼쪽으로 옮겨 씀 · 다른 화면에선 숨김
    if (box && box.parentElement !== acct) acct.appendChild(box);
    bar.dataset.w = w;
    bar.querySelector('.tnb-back').hidden = w === 'lobby';
    const bk = bar.querySelector('.tnb-back'), bm = w === 'hub' ? 'home' : 'back'; if (bk.dataset.ic !== bm) { bk.dataset.ic = bm; bk.classList.remove('noart'); bk.innerHTML = ic(bm); }
    bar.querySelector('.tnb-back').setAttribute('aria-label', w === 'hub' ? '처음으로' : '뒤로');
    acct.hidden = w !== 'lobby';
    const t = title(w); const T = bar.querySelector('.tnb-t'); if (T.textContent !== t) T.textContent = t;
    const lv = bar.querySelector('.tnb-lv'); lv.hidden = !P || w === 'lobby'; if (P) lv.textContent = `Lv.${P.level}`;
    const se = bar.querySelector('.tnb-st'); se.hidden = !(P && st);
    if (P && st) { const full = P.stamina >= P.stamina_max, mm = window.VRPlayer.mmss?.(P.next_regen_secs) || '';
      se.classList.toggle('low', P.stamina < (P.cost?.story || 6));
      if (!se.firstChild) se.innerHTML = `${ic('stamina')}<b></b><small></small><em></em>`; se.querySelector('b').textContent = P.stamina; se.querySelector('small').textContent = '/' + P.stamina_max; se.querySelector('em').textContent = full ? '' : mm; se.title = full ? '행동력 가득' : `행동력 · +1 까지 ${mm}`; }
    const cur = (k, v, img, name) => { const b = bar.querySelector(`[data-cur="${k}"]`); b.hidden = v == null; if (v == null) return;
      const h = `${img ? `<img src="${img}" alt="">` : ic(k)}<b>${n(v)}</b><i class="tnb-plus">${ic('plus')}</i>`; if (b.dataset.v !== n(v)) { b.dataset.v = n(v); b.innerHTML = h; } b.title = `${name} ${full(v)} · 눌러서 충전`; b.setAttribute('aria-label', `${name} ${full(v)} · 충전`); };
    cur('gem', G?.gem, null, '심연석'); cur('gold', W?.gold, CUR_IMG.gold, '골드'); cur('drink', D ? D.total : null, CUR_IMG.drink, '체력의 드링크');
    const key = w + t; if (key !== last) { last = key; document.body.dataset.tnb = w; }
  }
  // 재화 처음 불러오기 (로그인 뒤) — 각 모듈이 캐시를 채우면 paint 가 읽음
  let tries = 0; const warm = () => { if (!window.VRCloud?.user && !window.__STORY_MOCK_USER) { if (++tries < 40) setTimeout(warm, 500); return; }
    window.VRPlayer?.status?.(); window.VRPlayer?.wallet?.(); window.VRGem?.status?.(); window.VRDrink?.status?.(); };
  warm(); addEventListener('tcg:ready', warm);
  paint(true); setInterval(paint, 250);
  window.VRTnb = { paint, where, ART, ART_DIR };
})();
