// ===== 시안: 전역 하단 탭 (GNB) — 홈 · 소환 · 탑 · 조직 · PvP · 마이 =====
// 모든 화면(로비·페이지·스토리)에 따라다님. 전투·대사·영상·확인창 중엔 숨김. 거래소는 홈(로비 타일)으로 이동.
// 시안이라 기존 탭 버튼을 그대로 눌러 여는 방식 (끄려면 localStorage vrGnb=0)
(() => {
  if (localStorage.getItem('vrGnb') === '0') return;
  const $ = id => document.getElementById(id), V = () => window.VRPages;
  const vis = el => el && !el.classList.contains('hidden');
  const homeNow = () => { const P = V(); while (P?.depth) P.closeNow(); if (vis($('story-screen'))) window.VRStory?.api?.home?.(); };
  const T = [
    ['home', '홈', 'img/ui/main/tab_home.webp', '🏠', homeNow],
    ['summon', '소환', '', '🎴', () => { homeNow(); window.VRStory?.openShop?.(); }],
    ['tower', '탑', '', '🗼', () => { homeNow(); window.VRQuest?.open?.(); }],
    ['guild', '조직', 'img/ui/main/tab_guild.webp', '🩸', () => { homeNow(); $('main-guild')?.click(); }],
    ['pvp', 'PvP', '', '⚔️', () => { homeNow(); $('main-pvp')?.click(); }],
    ['my', '마이', 'img/ui/main/tab_my.webp', '👤', () => { homeNow(); $('main-mypage')?.click(); }],
  ];
  const nav = document.createElement('nav');
  nav.id = 'vr-gnb'; nav.setAttribute('aria-label', '하단 메뉴');
  nav.innerHTML = T.map(([k, l, img, em]) => `<button type="button" class="gnb-t gnb-${k}" data-gnb="${k}"${k === 'my' ? ' data-friendbadge' : ''}><i>${img ? `<img src="${img}" alt="">` : em}</i><span>${l}</span></button>`).join('');
  document.body.appendChild(nav); document.body.classList.add('gnb-on');
  nav.addEventListener('click', e => { const b = e.target.closest('[data-gnb]'); if (!b) return; if (b.classList.contains('lock')) return; T.find(t => t[0] === b.dataset.gnb)[4](); setTimeout(paint, 60); });
  // 홈 로비에 거래소 타일 (하단 탭에서 빠진 대신)
  const grid = document.querySelector('#start-screen .main-grid');
  if (grid && !$('main-trade-tile')) grid.insertAdjacentHTML('beforeend', `<button id="main-trade-tile" class="main-tile tile-trade" type="button" data-auth title="거래소"><img src="img/ui/trade.webp" alt="" class="main-tile-ic"><b class="main-tile-t">⚖️ 거래소</b></button>`);
  $('main-trade-tile')?.addEventListener('click', () => $('main-trade') ? $('main-trade').click() : window.VRTrade?.open?.());
  const busy = () => vis($('game')) || !!document.querySelector('.story-vcut, .story-ovp, #story-video, .pvp-vsx, #pvp-play, #story-screen:not(.hidden) #story-dlg, #vr-confirm:not(.hidden), .gr-forced') || !!window.__storyVideo?.el?.isConnected || vis($('story-intro')) || vis($('intro'));
  const active = () => { const c = V()?.current || ''; if (c === 'quest') return 'tower'; if (/^pvp/.test(c)) return 'pvp'; if (/^guild|^raid|^war/.test(c)) return 'guild'; if (/^mypage|^talent|^gallery|^friends/.test(c)) return 'my';
    if (c) return nav.dataset.last || 'home'; if (vis($('story-screen'))) return document.querySelector('#story-screen .gr-banners, #story-screen #gacha-stage, #story-screen #tk-result') ? 'summon' : 'home'; return 'home'; };
  function paint() { const hide = busy(); nav.classList.toggle('gnb-hide', hide); document.body.classList.toggle('gnb-hidden', hide); const a = active(); nav.dataset.last = a;
    nav.querySelectorAll('[data-gnb]').forEach(b => { const on = b.dataset.gnb === a; b.classList.toggle('on', on); b.toggleAttribute('aria-current', on); }); }
  paint(); setInterval(paint, 250);
})();
