// ===== 마이페이지 =====
// 로그인 유저: 리더 카드(크게) · 보유 카드 + 기본 덱 · 재화(소환권 · 골드 · 순수한 피 · 이상한 조각 · 각성자의 혼) · 전적(아케이드 승/패, 스토리 진행, 갤러리 수집률)
// 게스트: 로그인 안내. 팝업은 바깥을 누르면 닫힘.
// 확장: VRMyPage.addSection({ id, title, order, render(ctx) => html }) / CURRENCIES 에 재화 추가
// 리더 영상 훅: data/movie/<id>.mp4 가 있으면 리더 카드를 탭할 때 음소거 인라인 재생
(() => {
  const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
  const SHORT = { 'NORMAL': 'N', 'RARE': 'R', 'HIGH RARE': 'HR', 'SUPER RARE': 'SR', 'ULTRA RARE': 'UR', 'MYTHIC RARE': 'MR' };
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
    try { const v = JSON.parse(localStorage.getItem(`vrTcgStats.v1:${u.id}`) || 'null'); return v ? { wins: v.wins | 0, losses: v.losses | 0, draws: v.draws | 0 } : null; } catch { return null; }
  }
  // 지갑: supabase/phaseE_1.sql 의 wallet_status (SQL 실행 전이면 null → '-' 표시)
  async function walletStatus() {
    const sb = cloud()?.sb; if (!sb || !user()) return null;
    const { data, error } = await sb.rpc('wallet_status'); if (error) throw error; return data;
  }
  async function gather() {
    const m = window.__MYPAGE_MOCK;
    const safe = f => { try { return Promise.resolve(f()).catch(() => null); } catch { return Promise.resolve(null); } };
    const [story, gal, quest, wallet, player] = await Promise.all([
      safe(() => m?.story ? m.story() : window.VRStory?.summary?.()),
      safe(() => m?.gallery ? m.gallery() : window.VRGallery?.collection?.()),
      safe(() => m?.quest ? m.quest() : window.VRQuest?.bestFloor?.()),
      safe(() => m?.wallet ? m.wallet() : walletStatus()),
      safe(() => m?.player ? m.player() : window.VRPlayer?.status?.(true)),
    ]);
    const pool = window.TCG?.POOL || [];
    const cardOf = id => pool.find(c => String(c.id) === String(id));
    return { user: user(), story: story?.ok ? story : null, gallery: gal, questBest: quest, wallet: wallet?.ok ? wallet : null, player: player?.ok ? player : null, arcade: m?.arcade ? m.arcade() : arcadeRecord(), cardOf };
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
  const thumb = (o, cls = '', cnt = 1) => `<button type="button" class="mp-card rar-${SHORT[o.grade] || 'N'} ${cls}" data-uid="${esc(o.uid)}" data-id="${esc(o.id)}" title="${esc(o.name)}${cnt > 1 ? ` x${cnt}` : ''}" aria-label="${esc(o.name)} 카드 정보"><img loading="lazy" src="${IMG}${o.id}.webp" alt="${esc(o.name)}" onerror="this.style.visibility='hidden'">
    <span class="mp-rar">${SHORT[o.grade] || ''}</span>${o.leader ? '<span class="mp-lead">👑</span>' : ''}${cnt > 1 ? `<span class="mp-cnt">x${cnt}</span>` : ''}<span class="mp-lv">Lv.${o.level || 1}</span><span class="mp-nm">${esc(o.name)}</span></button>`;
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
    if (c && window.TCG?.showCardInfo) window.TCG.showCardInfo(c);
  }
  addSection({ id: 'leader', order: 10, render: ctx => {
    const s = ctx.story, L = s?.owned.find(o => o.uid === s.leaderUid) || s?.owned.find(o => s.deckUids?.[0] === o.uid);
    if (!L) return `<div class="mp-leader empty"><div class="mp-empty">아직 리더 카드가 없어요<br><small>스토리 모드에서 카드를 고르고 리더로 정해 보세요</small></div></div>`;
    return `<div class="mp-leader rar-${SHORT[L.grade] || 'N'}" id="mp-leader" data-id="${esc(L.id)}"><img src="${IMG}${L.id}.webp" alt="${esc(L.name)}" class="mp-leader-img" onerror="this.style.visibility='hidden'">
      <div class="mp-leader-cap"><span class="mp-rar">${SHORT[L.grade] || ''}</span><b>${esc(L.name)}</b><small>리더 · Lv.${L.level || 1}${L.power ? ` · ⚡ ${Number(L.power).toLocaleString('ko-KR')}` : ''}</small></div>
      <span class="mp-play" aria-hidden="true">▶</span></div>`;
  } });
  addSection({ id: 'player', order: 15, title: '플레이어', render: ctx => { const p = ctx.player; if (!p) return '';
    const pct = p.xp_next ? Math.min(100, Math.round(p.xp / p.xp_next * 100)) : 100, full = p.stamina >= p.stamina_max;
    return `<div class="mp-player"><div class="mp-plv"><b>Lv.${p.level}</b><small>/ ${p.max_level}</small></div>
      <div class="mp-pinfo"><div class="mp-pxp"><span>경험치</span><span>${p.xp_next ? `${p.xp.toLocaleString('ko-KR')} / ${p.xp_next.toLocaleString('ko-KR')}` : '최대 레벨'}</span></div><div class="mp-bar"><i style="width:${pct}%"></i></div>
      <div class="mp-pxp"><span>🔋 행동력</span><span><b>${p.stamina}</b> / ${p.stamina_max}${full ? '' : ` · +1 ${window.VRPlayer?.mmss?.(p.next_regen_secs) || ''}`}</span></div><div class="mp-bar st"><i style="width:${Math.min(100, Math.round(p.stamina / p.stamina_max * 100))}%"></i></div>
      <small class="mp-pnote">스토리 페이즈 1회 = 행동력 ${p.cost?.story ?? 6} (패배·포기 시 반환) · 6분에 1 회복 · 시련의 탑·아케이드는 무료</small></div></div>`; } });
  addSection({ id: 'wallet', order: 20, title: '재화', render: ctx => `<div class="mp-wallet">${CURRENCIES.map(c => { const v = c.value(ctx);
    return `<div class="mp-cur ${c.soon ? 'soon' : ''}" data-cur="${c.key}"><span class="mp-cur-ic">${c.icon}</span><span class="mp-cur-l">${c.label}</span><b>${v == null ? (c.soon ? '준비 중' : '-') : Number(v).toLocaleString('ko-KR')}</b></div>`; }).join('')}</div>` });
  addSection({ id: 'record', order: 30, title: '전적', render: ctx => {
    const a = ctx.arcade, s = ctx.story, g = ctx.gallery;
    const chs = s?.chapters || [], done = chs.reduce((x, c) => x + c.done, 0), tot = chs.reduce((x, c) => x + c.total, 0);
    const games = a ? a.wins + a.losses + a.draws : 0;
    return `<div class="mp-rec">
      <div class="mp-stat"><span>아케이드</span><b>${a ? `${a.wins}승 ${a.losses}패${a.draws ? ` ${a.draws}무` : ''}` : '-'}</b><small>${a && games ? `승률 ${pct(a.wins, games)}%` : '기록 없음'}</small></div>
      <div class="mp-stat"><span>스토리</span><b>${tot ? `${done}/${tot}` : '-'}</b><small>${chs.map(c => `${esc(c.title)} ${c.done}/${c.total}`).join(' · ') || '진행 없음'}</small></div>
      <div class="mp-stat"><span>시련의 탑</span><b>${ctx.questBest != null ? `${ctx.questBest}층` : '-'}</b><small>최고 기록</small></div>
      <div class="mp-stat"><span>갤러리</span><b>${g ? `${pct(g.have, g.total)}%` : '-'}</b><small>${g ? `${g.have}/${g.total} 수집` : ''}</small></div></div>`;
  } });
  addSection({ id: 'deck', order: 40, title: '기본 덱', render: ctx => {
    const s = ctx.story; if (!s) return '<div class="mp-note">스토리 카드를 불러오지 못했어요</div>';
    const by = new Map(s.owned.map(o => [o.uid, o])), deck = (s.deckUids || []).map(u => by.get(u)).filter(Boolean);
    return deck.length ? `<div class="mp-row">${deck.map(o => thumb(o)).join('')}</div><div class="mp-note">스토리 출전에 마지막으로 고른 카드예요 (없으면 리더 + 전투력 순)</div>` : '<div class="mp-note">아직 덱이 없어요</div>';
  } });
  addSection({ id: 'owned', order: 50, title: '보유 카드', render: ctx => {
    const s = ctx.story; if (!s) return '';
    const deck = new Set(s.deckUids || []), order = ['MYTHIC RARE', 'ULTRA RARE', 'SUPER RARE', 'HIGH RARE', 'RARE', 'NORMAL'];
    const list = groupOwned(s.owned, deck).sort((x, y) => { const a = x.rep, b = y.rep; return b.leader - a.leader || order.indexOf(a.grade) - order.indexOf(b.grade) || b.level - a.level; });
    return `<div class="mp-sub">${s.owned.length}장 · 종류 ${list.length}</div><div class="mp-grid">${list.map(({ rep, count }) => thumb(rep, deck.has(rep.uid) ? 'in-deck' : '', count)).join('') || '<div class="mp-note">보유 카드가 없어요</div>'}</div>`;
  } });

  // ---- 화면 ----
  function ensure() {
    let m = $('mp-modal'); if (m) return m;
    m = document.createElement('div'); m.id = 'mp-modal'; m.className = 'mp-modal hidden';
    m.innerHTML = `<div class="mp-panel" role="dialog" aria-label="마이페이지"><div class="mp-head"><div class="mp-title">👤 마이페이지</div><button class="mp-x" id="mp-close" aria-label="닫기">✕</button></div><div id="mp-body" class="mp-body"></div></div>`;
    document.body.appendChild(m);
    m.addEventListener('click', e => { if (e.target === m || e.target.closest('#mp-close')) return close();
      const t = e.target.closest('.mp-card[data-uid]'); if (t) openCard(t.dataset.uid, t.dataset.id); });   // 바깥 클릭 = 닫기
    document.addEventListener('keydown', e => { if (e.key === 'Escape' && !m.classList.contains('hidden')) close(); });
    return m;
  }
  function close() { const m = $('mp-modal'); if (!m) return; m.classList.add('hidden'); document.body.classList.remove('gal-lock'); m.querySelectorAll('video').forEach(v => v.pause()); }
  async function open() {
    const m = ensure(), body = $('mp-body');
    m.classList.remove('hidden'); document.body.classList.add('gal-lock');
    if (!user()) {
      body.innerHTML = `<div class="mp-guest"><img src="img/ui/profile.webp" alt="" width="72" height="72"><b>로그인하면 마이페이지를 볼 수 있어요</b><small>리더 카드 · 보유 카드 · 소환권 · 전적이 계정에 저장돼요</small>${cloud()?.sb ? '<button id="mp-login" class="main-btn mp-login">구글 로그인</button>' : '<small>지금은 로그인 서버에 연결할 수 없어요</small>'}</div>`;
      if ($('mp-login')) $('mp-login').onclick = () => cloud().login();
      return;
    }
    body.innerHTML = '<div class="mp-note">불러오는 중...</div>';
    const ctx = await gather();
    const meta = ctx.user.user_metadata || {};
    body.innerHTML = `<div class="mp-who">${meta.avatar_url ? `<img src="${esc(meta.avatar_url)}" referrerpolicy="no-referrer" alt="" class="mp-av" onerror="this.src='img/ui/profile.webp'">` : '<img src="img/ui/profile.webp" alt="" class="mp-av">'}<b>${esc(meta.name || meta.full_name || (ctx.user.email || '').split('@')[0] || '플레이어')}</b></div>`
      + sections.map(s => { let h = ''; try { h = s.render(ctx) || ''; } catch (e) { console.warn('[mypage] section', s.id, e); }
        return h ? `<section class="mp-sec" data-sec="${s.id}">${s.title ? `<h3>${s.title}</h3>` : ''}${h}</section>` : ''; }).join('');
    const lb = $('mp-leader'); if (lb) movieFor(lb.dataset.id).then(u => bindLeaderVideo(lb, u));
    return ctx;
  }
  function mount() { const b = $('main-mypage'); if (b) b.onclick = open; }
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', mount) : mount();
  window.VRMyPage = { open, close, addSection, CURRENCIES, _test: { gather, movieFor, sections, groupOwned, openCard } };
})();
