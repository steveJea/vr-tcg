// ===== 마이페이지 =====
// 로그인 유저: 리더 카드(크게) · [보유 카드]/[덱 설정] 이동 · 마이 덱(최대 10) · 즐겨찾기 · 재화(소환권 · 골드 · 순수한 피 · 이상한 조각 · 각성자의 혼) · 전적(아케이드 승/패, 스토리 진행, 갤러리 수집률)
// 게스트: 로그인 안내. 팝업은 바깥을 누르면 닫힘.
// 확장: VRMyPage.addSection({ id, title, order, render(ctx) => html }) / CURRENCIES 에 재화 추가
// 리더 영상 훅: data/movie/<id>.mp4 가 있으면 리더 카드를 탭할 때 음소거 인라인 재생
(() => {
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const SHORT = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR', 'LEGENDARY RARE': 'LR' };
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const cloud = () => window.__MYPAGE_MOCK?.cloud || window.VRCloud;
  const user = () => cloud()?.user || null;
  /** 재화 목록: value(ctx) 가 null 이면 '준비 중' 으로 표시 */
  const CURRENCIES = [
    { key: 'tickets', icon: '🎟️', label: '소환권', value: ctx => ctx.story?.tickets ?? null },
    { key: 'gold', icon: '🪙', label: '골드', value: ctx => ctx.wallet?.gold ?? null },
    { key: 'blood', icon: '🩸', label: '순수한 피', value: ctx => ctx.wallet?.blood ?? null },
    { key: 'shard', icon: '💠', label: '이상한 조각', value: ctx => ctx.wallet?.shard ?? null },
    { key: 'soul', icon: '🔥', label: '각성자의 혼', value: ctx => ctx.wallet?.soul ?? null },
  ];
  const sections = [];
  const addSection = s => { sections.push(s); sections.sort((a, b) => (a.order || 0) - (b.order || 0)); };

  // ---- 데이터 모으기 (각 출처는 실패해도 다른 칸은 표시) ----
  function arcadeRecord() {
    const u = user(); if (!u) return null;
    try { const v = JSON.parse(localStorage.getItem(`vrTcgStats.v5:${u.id}`) || 'null'); return v ? { wins: v.wins | 0, losses: v.losses | 0, draws: v.draws | 0 } : null; } catch { return null; }
  }
  // 지갑: supabase/phaseE_1.sql 의 wallet_status (SQL 실행 전이면 null → '-' 표시)
  async function walletStatus() {
    const sb = cloud()?.sb; if (!sb || !user()) return null;
    const { data, error } = await sb.rpc('wallet_status'); if (error) throw error; return data;
  }
  async function gather() {
    const m = window.__MYPAGE_MOCK;
    const safe = f => { try { return Promise.resolve(f()).catch(() => null); } catch { return Promise.resolve(null); } };
    const [story, gal, quest, wallet, player, gem, guild] = await Promise.all([
      safe(() => m?.story ? m.story() : window.VRStory?.summary?.()),
      safe(() => m?.gallery ? m.gallery() : window.VRGallery?.collection?.()),
      safe(() => m?.quest ? m.quest() : window.VRQuest?.bestFloor?.()),
      safe(() => m?.wallet ? m.wallet() : walletStatus()),
      safe(() => m?.player ? m.player() : window.VRPlayer?.status?.(true)),
      safe(() => m?.gem ? m.gem() : window.VRGem?.status?.(true)),
      safe(() => m?.guild ? m.guild() : window.VRGuild?.status?.()),
    ]);
    const pool = window.TCG?.POOL || [];
    const cardOf = id => pool.find(c => String(c.id) === String(id));
    return { user: user(), story: story?.ok ? story : null, gallery: gal, questBest: quest, wallet: wallet?.ok ? wallet : null, player: player?.ok ? player : null, gem: gem?.ok ? gem : null, guild: guild?.ok ? guild : null, arcade: m?.arcade ? m.arcade() : arcadeRecord(), cardOf };
  }

  // ---- 리더 영상 훅 ----
  const movieCache = new Map();
  async function movieFor(id) {
    if (movieCache.has(id)) return movieCache.get(id);
    const url = `data/movie/${id}.mp4`;
    let ok = false;
    try { const r = await fetch(url, { method: 'HEAD' }); ok = r.ok && /video|octet/.test(r.headers.get('content-type') || 'video/mp4'); } catch {}
    movieCache.set(id, ok ? url : null); return ok ? url : null;
  }
  function bindLeaderVideo(box, url) {
    if (!box || !url) return;
    box.classList.add('has-movie');
    box.addEventListener('click', () => {
      let v = box.querySelector('video');
      if (!v) {
        v = document.createElement('video'); v.src = url; v.muted = true; v.defaultMuted = true; v.playsInline = true; v.setAttribute('playsinline', ''); v.preload = 'auto'; v.className = 'mp-movie';
        v.addEventListener('playing', () => box.classList.add('playing'));
        v.addEventListener('ended', () => box.classList.remove('playing'));
        box.appendChild(v);
      }
      if (box.classList.contains('playing') && !v.paused) { v.pause(); box.classList.remove('playing'); return; }
      v.currentTime = 0; v.play().catch(() => box.classList.remove('playing'));
    });
  }

  // ---- 기본 섹션 ----
  const pct = (a, b) => b ? Math.floor(a / b * 100) : 0;
  const thumb = (o, cls = '', cnt = 1) => `<button type="button" class="mp-card rar-${SHORT[o.grade] || 'N'} ${cls}" data-uid="${esc(o.uid)}" data-id="${esc(o.id)}" title="${esc(o.name)}${cnt > 1 ? ` x${cnt}` : ''}" aria-label="${esc(o.name)} 인재 정보"><img loading="lazy" src="${cardThumb(o.id)}" alt="${esc(o.name)}" onerror="this.style.visibility='hidden'">
    <span class="mp-rar">${SHORT[o.grade] || ''}</span>${o.leader ? '<span class="mp-lead">👑</span>' : ''}${o.fav ? '<span class="mp-fav">★</span>' : ''}${cnt > 1 ? `<span class="mp-cnt">x${cnt}</span>` : ''}<span class="mp-lv">Lv.${o.level || 1}</span><span class="mp-nm">${esc(o.name)}</span></button>`;
  /** 같은 카드(id) 여러 장은 한 칸으로: 대표 = 리더 > 덱 > 레벨·EX 높은 것, 개수는 x<n> */
  function groupOwned(owned, deck) {
    const g = new Map();
    for (const o of owned) { const k = String(o.id); if (!g.has(k)) g.set(k, []); g.get(k).push(o); }
    return [...g.values()].map(list => {
      const rep = list.slice().sort((a, b) => b.leader - a.leader || deck.has(b.uid) - deck.has(a.uid) || (b.ex | 0) - (a.ex | 0) || (b.level | 0) - (a.level | 0))[0];
      return { rep, count: list.length };
    });
  }
  /** 카드 정보 (전투·갤러리와 같은 상세 창, 바깥 클릭으로 닫힘). 스토리 레벨·EX·스탯 분배 반영 */
  function openCard(uid, id) {
    let c = null;
    try { const inst = window.VRStory?.save?.owned?.find(o => o.uid === uid); if (inst) c = window.VRStory.api.battleCards([inst])[0] || null; } catch {}
    if (!c) c = (window.TCG?.POOL || []).find(x => String(x.id) === String(id)) || null;
    if (c && window.TCG?.showCardInfo) window.TCG.showCardInfo(c, { power: true });   // ATK 위에 전투력(레벨 반영)
  }
  addSection({ id: 'leader', order: 10, render: ctx => {
    const s = ctx.story, L = s?.owned.find(o => o.uid === s.leaderUid) || s?.owned.find(o => s.deckUids?.[0] === o.uid);
    if (!L) return `<div class="mp-leader empty"><div class="mp-empty">—</div></div>`;
    return `<div class="mp-leader rar-${SHORT[L.grade] || 'N'}" id="mp-leader" data-id="${esc(L.id)}"><img src="${IMG}${L.id}.webp" alt="${esc(L.name)}" class="mp-leader-img" onerror="this.style.visibility='hidden'">
      <div class="mp-leader-cap"><span class="mp-rar">${SHORT[L.grade] || ''}</span><b>${esc(L.name)}</b><small>리더 · Lv.${L.level || 1}${L.power ? ` · ⚡ ${Number(L.power).toLocaleString('ko-KR')}` : ''}</small></div>
      <span class="mp-play" aria-hidden="true">▶</span></div>`;
  } });
  addSection({ id: 'player', order: 15, render: ctx => { const p = ctx.player; if (!p) return '';
    const pct = p.xp_next ? Math.min(100, Math.round(p.xp / p.xp_next * 100)) : 100, full = p.stamina >= p.stamina_max;
    return `<div class="mp-player"><div class="mp-plv"><b>Lv.${p.level}</b><small>/ ${p.max_level}</small></div>
      <div class="mp-pinfo"><div class="mp-pxp"><span>EXP</span><span>${p.xp_next ? `${p.xp.toLocaleString('ko-KR')} / ${p.xp_next.toLocaleString('ko-KR')}` : '최대 레벨'}</span></div><div class="mp-bar"><i style="width:${pct}%"></i></div>
      <div class="mp-pxp"><span>${window.VRIcon?.cur?.('stamina') || '🔋'}</span><span><b>${p.stamina}</b> / ${p.stamina_max}</span></div><div class="mp-bar st"><i style="width:${Math.min(100, Math.round(p.stamina / p.stamina_max * 100))}%"></i></div></div></div>`; } });
  addSection({ id: 'wallet', order: 20, render: ctx => `<div class="mp-wallet">${CURRENCIES.map(c => { const v = c.value(ctx);
    return `<div class="mp-cur ${c.soon ? 'soon' : ''}" data-cur="${c.key}" title="${esc(c.label)}"><span class="mp-cur-ic">${window.VRIcon?.cur?.(c.key, { alt: c.label }) || c.icon}</span><b>${v == null ? (c.soon ? '준비 중' : '-') : Number(v).toLocaleString('ko-KR')}</b></div>`; }).join('')}</div>` });
  // 조직 (guild.sql · js/guild.js): 엠블럼 · 이름 · 레벨 → 조직 화면
  addSection({ id: 'guild', order: 11, render: ctx => ctx.guild ? window.VRGuild?.myCard?.(ctx.guild) || '' : '' });
  // 심연석 (gem.sql · js/gem.js): 잔액 + 최근 20건
  addSection({ id: 'gem', order: 21, render: ctx => ctx.gem ? window.VRGem?.section?.(ctx.gem) || '' : '' });
  addSection({ id: 'record', order: 30, render: ctx => {
    const a = ctx.arcade, s = ctx.story, g = ctx.gallery;
    const chs = s?.chapters || [], done = chs.reduce((x, c) => x + c.done, 0), tot = chs.reduce((x, c) => x + c.total, 0);
    const games = a ? a.wins + a.losses + a.draws : 0;
    return `<div class="mp-rec">
      ${s?.current ? (() => { const c = s.current; return `<button type="button" class="mp-story" data-nav="story" data-ch="${c.i}" aria-label="스토리 맵"><span class="mp-story-bg" style="background-image:url(img/story/ch_bg_${esc(c.bg || c.id)}.webp),url(img/story/ch_bg_${esc(c.id)}.webp)${c.cover ? `,url(${esc(c.cover)})` : ''},url(img/story/opening_poster.webp)"></span>
        <span class="mp-story-t"><small>${esc(c.title)}</small><b>${esc(c.subtitle)}</b><i>${c.phase ? `Phase.${c.phase}${c.boss ? ' · BOSS' : ''}` : `✔ ${c.done}/${c.total}`}</i></span></button>`; })() : ''}
      <div class="mp-stat"><span>아케이드 · 검증 전적</span><b>${a ? `${a.wins}승 ${a.losses}패${a.draws ? ` ${a.draws}무` : ''}` : '-'}</b><small>${a && games ? `승률 ${pct(a.wins, games)}%` : '기록 없음'}</small></div>
      <div class="mp-stat"><span>시련의 탑</span><b>${ctx.questBest != null ? `${ctx.questBest}층` : '-'}</b><small>최고 기록</small></div>
      <div class="mp-stat"><span>갤러리</span><b>${g ? `${pct(g.have, g.total)}%` : '-'}</b><small>${g ? `${g.have}/${g.total} 수집` : ''}</small></div></div>`;
  } });
  addSection({ id: 'nav', order: 12, render: ctx => ctx.story ? `<div class="mp-nav"><button type="button" class="mp-navbtn" data-nav="cards"><img class="ui-btn-ic" src="img/ui/icon/my_cards.webp" alt="인재" width="22" height="22">보유 인재<small>${ctx.story.owned.length}</small></button><button type="button" class="mp-navbtn" data-nav="decks"><img class="ui-btn-ic" src="img/ui/icon/decks.webp" alt="덱" width="22" height="22">덱 설정<small>${(ctx.story.decks || []).filter(d => d.uids.length).length}/10</small></button>${ctx.story.serverMode && window.VRGear && !window.VRGear.off ? '<button type="button" class="mp-navbtn mp-navbtn-wide" data-nav="gearbag"><img class="ui-btn-ic" src="img/ui/icon/gearbag.webp" alt="장비" width="22" height="22">장비 가방</button>' : ''}${ctx.story.serverMode && window.VRCamp && !window.VRCamp.off ? '<button type="button" class="mp-navbtn mp-navbtn-wide" data-nav="camp"><img class="ui-btn-ic" src="img/ui/icon/camp.webp" alt="훈련소" width="22" height="22">훈련소<i data-campdot></i></button>' : ''}</div>` : '' });
  addSection({ id: 'deck', order: 40, title: '마이 덱', render: ctx => {
    const s = ctx.story; if (!s) return '';
    const by = new Map(s.owned.map(o => [o.uid, o])), ds = (s.decks || []).filter(d => d.uids.length);
    if (!ds.length) return `<button type="button" class="mp-note mp-navlink" data-nav="decks">＋</button>`;
    return ds.map(d => `<div class="mp-deck mp-deck-go" data-nav="decks" role="button" title="덱 설정"><div class="mp-deck-h">${esc(d.name)}</div><div class="mp-row">${d.uids.map(u => by.get(u)).filter(Boolean).map(o => thumb(o, o.fav ? 'fav' : '')).join('')}</div></div>`).join('');
  } });
  addSection({ id: 'fav', order: 45, title: '즐겨찾기', render: ctx => {
    const s = ctx.story; if (!s) return '';
    const list = groupOwned(s.owned.filter(o => o.fav), new Set());
    return list.length ? `<div class="mp-row">${list.map(({ rep, count }) => thumb(rep, 'fav', count)).join('')}</div>` : '';
  } });

  // ---- 화면 ----
  function ensure() {
    let m = $('mp-modal'); if (m) return m;
    m = document.createElement('div'); m.id = 'mp-modal'; m.className = 'mp-modal hidden';
    m.innerHTML = `<div class="mp-panel" role="dialog" aria-label="마이페이지"><div class="mp-head"><div class="mp-title">${window.VRIcon?.icon('mypage_btn', { alt: '' }) || '👤'} 마이페이지</div><span data-friendbtn class="mp-friend"></span><button class="mp-x" id="mp-close" aria-label="닫기">✕</button></div><div id="mp-body" class="mp-body"></div></div>`;
    document.body.appendChild(m);
    m.addEventListener('click', e => { if (e.target === m) close(); });   // 바깥 클릭 = 닫기 (팝업일 때)
    m.querySelector('.mp-panel').addEventListener('click', e => { if (e.target.closest('#mp-close')) return close();   // 판에 달아 둠: 페이지로 옮겨가도 동작
      const nv = e.target.closest('[data-nav]'); if (nv) { if (nv.dataset.nav === 'gearbag') return window.VRGear?.bag?.(); if (nv.dataset.nav === 'camp') return window.VRCamp?.open?.();   // 장비 가방은 팝업이라 마이페이지는 그대로
        close(); const S = window.VRStory; return nv.dataset.nav === 'story' ? S?.openMap?.(+nv.dataset.ch) : nv.dataset.nav === 'decks' ? S?.openDecks?.() : S?.openCards?.(); }
      const t = e.target.closest('.mp-card[data-uid]'); if (t) openCard(t.dataset.uid, t.dataset.id); });   // 바깥 클릭 = 닫기
    document.addEventListener('keydown', e => { if (e.key === 'Escape' && !m.classList.contains('hidden')) close(); });
    return m;
  }
  function cleanup() { if (prevTrack !== null) { const t = prevTrack; prevTrack = null; if (t) try { window.VRSound?.setTrack?.(t); } catch {} } document.body.classList.remove('gal-lock'); document.querySelectorAll('.mp-panel video').forEach(v => v.pause()); }
  function close() { if (window.VRPages?.current === 'mypage') return window.VRPages.closeNow(); cleanup(); const m = $('mp-modal'); if (!m) return; m.classList.add('hidden'); }
  // 페이지 시스템: 마이페이지 판을 페이지로 옮겼다가 떠날 때 돌려놓음 (BGM 복귀·영상 정지 포함). 없거나 실패하면 예전 팝업
  window.VRPages?.register?.('mypage', { title: '👤 마이페이지', render: body => { const p = ensure().querySelector('.mp-panel'); if (p) body.appendChild(p); }, leave: () => { const p = document.querySelector('#vr-page .mp-panel'); if (p) $('mp-modal')?.appendChild(p); cleanup(); } });
  let prevTrack = null;   // 열 때 mypage BGM, 닫으면 이전 트랙 복귀
  async function open() {
    if (prevTrack === null) { prevTrack = window.VRSound?.track || ''; try { window.VRSound?.setTrack?.('audio/mypage.mp3'); } catch {} }
    const m = ensure(), body = $('mp-body');
    if (!(window.VRPages?.current === 'mypage' || window.VRPages?.open?.('mypage'))) { m.classList.remove('hidden'); document.body.classList.add('gal-lock'); }
    if (!user()) {
      body.innerHTML = `<div class="mp-guest"><img src="img/ui/profile.webp" alt="" width="72" height="72"><b>로그인 필요</b>${cloud()?.sb ? '<button id="mp-login" class="main-btn mp-login">로그인</button>' : '<small>오프라인</small>'}</div>`;
      if ($('mp-login')) $('mp-login').onclick = () => cloud().login();
      return;
    }
    body.innerHTML = '<div class="mp-note">…</div>';
    const ctx = await gather();
    const meta = ctx.user.user_metadata || {};
    const nick = cloud()?.profile?.nickname || meta.name || meta.full_name || (ctx.user.email || '').split('@')[0] || '플레이어';
    const cos = await window.VRCosmo?.status?.();
    const eq = cos?.equipped || {};
    const lead = ctx.story?.owned?.find(o => o.uid === ctx.story.leaderUid) || ctx.story?.owned?.find(o => ctx.story.deckUids?.[0] === o.uid);
    const leadAv = lead?.id ? (window.cardThumb || (x => 'img/thumb/' + x + '.webp'))(lead.id) : null;
    const av = leadAv || meta.avatar_url || null;
    const whoChip = window.VRCosmo?.chip?.({ name: nick, title: eq.title, title_name: window.VRCosmo.titleName?.(eq.title), frame: eq.frame, avatar: av })
      || `<img src="${av ? esc(av) : 'img/ui/profile.webp'}" referrerpolicy="no-referrer" alt="" class="mp-av" onerror="this.src='img/ui/profile.webp'"><b class="mp-nick">${esc(nick)}</b>`;
    body.innerHTML = `<div class="mp-who">${whoChip}<button id="mp-cosmo" class="mp-cosmo" type="button"><img class="ui-btn-ic" src="img/ui/icon/cosmetics.webp" alt="꾸미기" width="16" height="16">꾸미기</button><button id="mp-nick-edit" class="mp-nick-edit" type="button">닉네임 변경${cloud()?.profile?.nick_set ? ' <small>🔮200</small>' : ''}</button></div>`
      + sections.map(s => { let h = ''; try { h = s.render(ctx) || ''; } catch (e) { console.warn('[mypage] section', s.id, e); }
        return h ? `<section class="mp-sec" data-sec="${s.id}">${s.title ? `<h3>${s.title}</h3>` : ''}${h}</section>` : ''; }).join('');
    const ne = $('mp-nick-edit'); if (ne) ne.onclick = async () => { const n = await cloud()?.askNickname?.(); if (n) { const b = body.querySelector('.cosmo-nm, .mp-nick'); if (b) b.textContent = n; } };
    const cb = $('mp-cosmo'); if (cb) cb.onclick = () => window.VRCosmo?.open?.();
    const lb = $('mp-leader'); if (lb) movieFor(lb.dataset.id).then(u => bindLeaderVideo(lb, u));
    return ctx;
  }
  function mount() { const b = $('main-mypage'); if (b) b.onclick = open; }
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', mount) : mount();
  window.VRMyPage = { open, close, addSection, CURRENCIES, _test: { gather, movieFor, sections, groupOwned, openCard } };
})();
