// ===== 앱 같은 손맛: 팝업 열림·화면 전환 애니메이션 + 짧은 진동 (게임 로직 건드리지 않음 · css/polish.css) =====
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  // 전투 화면(#game)이 열려 있는 동안엔 페이지 전체 감시를 쉬어요 (아이폰 버벅임 줄이기). 전투 밖으로 나가면 다시 돌아요
  const inBattle = () => { const g = document.getElementById('game'); const e = document.getElementById('end-screen'); return !!g && !g.classList.contains('hidden') && !(e && !e.classList.contains('hidden')); };
  const HAP_KEY = 'vrHaptic';
  const hapOn = () => localStorage.getItem(HAP_KEY) !== '0';
  // --- 진동: 버튼 누를 때 8ms (지원 기기만 · 전투 화면 #game 안은 제외 · 설정에서 끔) ---
  document.addEventListener('pointerdown', e => {
    if (!hapOn() || !navigator.vibrate) return;
    const b = e.target.closest('button, [role="button"], .main-tile, [data-go]');
    if (!b || b.disabled || b.closest('#game')) return;
    try { navigator.vibrate(8); } catch {}
  }, { passive: true });
  const tg = document.getElementById('main-haptic');
  const paint = () => { if (!tg) return; const on = hapOn(); tg.textContent = on ? 'ON' : 'OFF'; tg.classList.toggle('on', on); tg.setAttribute('aria-checked', String(on)); };
  if (tg) { tg.onclick = () => { localStorage.setItem(HAP_KEY, hapOn() ? '0' : '1'); paint(); if (hapOn()) try { navigator.vibrate?.(15); } catch {} }; paint(); }
  // --- 카드 목록: 처음 보일 때 위에서부터 차례로 (앞 24장만 · 정렬·필터로 다시 그릴 땐 없음) ---
  const TILES = '.story-group, .story-pick-card, .story-own-tile, .gal-card, .pvp-card';
  const stagger = root => { if (!root || root.closest?.('#game')) return; let i = 0; for (const t of root.querySelectorAll(TILES)) { if (i >= 24) break; if (t.parentElement?.closest(TILES)) continue; t.style.setProperty('--si', i++); t.classList.remove('ui-stagger'); void t.offsetWidth; t.classList.add('ui-stagger'); setTimeout(() => t.classList.remove('ui-stagger'), 700); } };
  // --- 재화 숫자: 골드·심연석이 바뀌면 이전 값에서 새 값까지 0.5초 동안 올라감/내려감 ---
  // 숫자만 담긴 칸만 본다: 칩 버튼 전체(+ 포함)나 '100k' 같은 줄임 표기는 제외 (줄임 '100k'를 100으로 읽어 100→100,720 으로 계속 다시 올라가던 문제)
  const CUR = [['.gem-chip b, .gem-big b, .gem-mp-top b, [title="심연석"]:not(.gem-chip)', 'gem'], ['[title="골드"]:not(.mp-cur), .mp-cur[data-cur="gold"] b', 'gold']];   // 마이페이지 골드 칸은 숫자(b)만: 칸 전체 textContent를 바꾸면 아이콘이 지워졌음
  const lastCur = {}, numOf = t => { t = t || ''; if (/\d\s*[kKmM만억]/.test(t)) return null; const m = /[\d,]+(?!.*\d)/.exec(t); return m ? +m[0].replace(/,/g, '') : null; };
  const countUp = (el, from, to) => {
    // 숫자가 든 마지막 글자 조각만 바꿈 (칸 전체 textContent를 바꾸면 안의 아이콘 그림이 지워짐)
    const tw = document.createTreeWalker(el, NodeFilter.SHOW_TEXT); let tn = null; for (let n; (n = tw.nextNode());) if (/\d/.test(n.nodeValue)) tn = n;
    if (!tn) return; const txt = tn.nodeValue, m = /[\d,]+(?!.*\d)/.exec(txt); if (!m) return;
    const pre = txt.slice(0, m.index), post = txt.slice(m.index + m[0].length), t0 = performance.now(), D = 500;
    el.classList.add('ui-cur-tick'); el.dataset.cnt = '1';
    const step = now => { if (!el.isConnected) return; const k = Math.min(1, (now - t0) / D), v = Math.round(from + (to - from) * (1 - Math.pow(1 - k, 3)));
      tn.nodeValue = pre + v.toLocaleString('ko-KR') + post; if (k < 1) requestAnimationFrame(step); else { delete el.dataset.cnt; setTimeout(() => el.classList.remove('ui-cur-tick'), 200); } };
    requestAnimationFrame(step);
  };
  let curQ = 0;
  const scanCur = () => { curQ = 0; if (document.getElementById('game') && !document.getElementById('game').classList.contains('hidden')) return;
    for (const [sel, k] of CUR) { const prev = lastCur[k]; let v1 = null;
      for (const el of document.querySelectorAll(sel)) { if (el.dataset.cnt) continue; const v = numOf(el.textContent); if (v == null) continue; v1 = v;
        if (prev != null && prev !== v && el.dataset.curSeen !== String(v)) countUp(el, prev, v); el.dataset.curSeen = String(v); }
      if (v1 != null) lastCur[k] = v1; } };
  // --- 폴리시3 (e) 전투력: 같은 화면(같은 카드 상세·같은 PvP 덱·같은 마이페이지 리더)에서 숫자가 바뀌면 올라감/내려감. 다른 카드로 바뀌면 그냥 표시 ---
  const POW = [['.cd-power b', el => [document.getElementById('story-pop'), el.closest('.story-pop-panel')?.querySelector('img')?.getAttribute('src')]],
    ['.pvp-pw', el => [el.closest('.pvp-modal'), el.closest('.pvp-modal')?.id]], ['.mp-leader-cap small', el => [el.closest('.mp-panel'), el.closest('.mp-leader-cap')?.querySelector('b')?.textContent]], ['.ci-power b', el => [document.getElementById('detail'), document.querySelector('#detail img')?.getAttribute('src')]]];
  const powSeen = new WeakMap();
  const scanPow = () => { for (const [sel, ctxOf] of POW) for (const el of document.querySelectorAll(sel)) { if (el.dataset.cnt) continue; const v = numOf(el.textContent); if (v == null) continue;
    const [ctx, id] = ctxOf(el); if (!ctx) continue; const p = powSeen.get(ctx); powSeen.set(ctx, { id, v });
    if (p && p.id === id && p.v !== v && el.dataset.curSeen !== String(v)) countUp(el, p.v, v); el.dataset.curSeen = String(v); } };
  const scanAll = () => { scanCur(); try { scanPow(); } catch {} };
  if (!reduce) new MutationObserver(() => { if (inBattle()) return; if (!curQ) curQ = requestAnimationFrame(scanAll); }).observe(document.body, { childList: true, subtree: true, characterData: true });
  // ===== 폴리시 4: 등급별 영입 빛 (R 초록 · HR 파랑 · SR 보라 링 · UR/MR/LR 화면 전체 섬광). 보이는 것만 =====
  const SUM = { 'RARE': ['r', 1], 'HIGH RARE': ['hr', 2], 'SUPER RARE': ['sr', 3], 'ULTRA RARE': ['ur', 4], 'MYTHIC RARE': ['mr', 4], 'LEGENDARY RARE': ['lr', 4] };
  const summon = (grade, el, delay = 0, opt = {}) => { const g = SUM[grade]; if (!g || !el) return; const [k, lv] = g;
    setTimeout(() => { if (!el.isConnected) return;
      const b = document.createElement('i'); b.className = `sfx-burst sfx-${k} sfx-lv${lv}`; b.setAttribute('aria-hidden', 'true'); el.appendChild(b); setTimeout(() => b.remove(), 1200); el.classList.add('sfx-glow', `sfx-${k}`); setTimeout(() => el.classList.remove('sfx-glow'), 900);
      if (lv >= 4 && !opt.noScreen) { const f = document.createElement('div'); f.className = `sfx-screen sfx-${k}`; f.setAttribute('aria-hidden', 'true'); document.body.appendChild(f); setTimeout(() => f.remove(), reduce ? 400 : 1100); }
    }, Math.max(0, delay)); };
  window.VRPolish = { ...(window.VRPolish || {}), summon };
  if (reduce) return;
  const replay = (el, cls) => { el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls); setTimeout(() => el.classList.remove(cls), 260); };
  // --- 팝업: 숨김(hidden) → 보임 으로 바뀔 때만 (같은 팝업 다시 그리기는 애니메이션 없음) ---
  const POPS = ['story-pop', 'vr-confirm', 'main-menu-pop'];
  const watchPop = el => new MutationObserver(rs => {
    const wasHidden = String(rs[0].oldValue || '').split(/\s+/).includes('hidden');
    if (wasHidden && !el.classList.contains('hidden')) { replay(el, 'ui-pop-in'); stagger(el); }
  }).observe(el, { attributes: true, attributeFilter: ['class'], attributeOldValue: true });
  const seen = new WeakSet();
  const hook = () => { for (const id of POPS) { const el = document.getElementById(id); if (el && !seen.has(el)) { seen.add(el); watchPop(el); } } };
  hook();
  // 새로 붙는 팝업 층 (PvP·조직 등 modal 을 새로 만드는 곳) + story-pop 첫 생성
  new MutationObserver(rs => { for (const r of rs) for (const n of r.addedNodes) {
    if (n.nodeType !== 1) continue;
    if (POPS.includes(n.id)) { hook(); if (!n.classList.contains('hidden')) { replay(n, 'ui-pop-in'); stagger(n); } }
    else if (n.matches?.('.pvp-modal, .gd-pop, .gd-ov, .mp-modal, .gal-modal')) { replay(n, 'ui-pop-in'); stagger(n); }
  } }).observe(document.body, { childList: true });
  // --- 스토리 화면 전환: 제목이 바뀔 때만 살짝 페이드 (정렬·필터로 다시 그릴 땐 그대로) ---
  const sr = document.getElementById('story-screen');
  if (sr) { let last = ''; new MutationObserver(() => {
    const t = sr.querySelector('.story-top-title')?.textContent || sr.firstElementChild?.className || '';
    if (t === last) return; last = t; const w = sr.firstElementChild; if (w) { replay(w, 'ui-screen-in'); stagger(w); }
  }).observe(sr, { childList: true }); }
  // ===== 폴리시 3 =====
  const fxOff = () => !!(window.TCG?.fxOff || localStorage.getItem('vrTcgSkipFx') === '1');
  // (b) 결과 화면: 승리/패배 글자가 쾅 → 보상 줄이 하나씩 (연출만 · 버튼은 바로 누를 수 있음)
  const RES_T = '.story-chapter-big, .end-big, .pvp-res';
  const resultFx = t => { if (fxOff() || t.dataset.slam) return; if (!/VICTORY|DEFEAT|DRAW|CLEAR|WIN|LOSE/.test(t.textContent)) return; t.dataset.slam = '1';
    t.classList.add('ui-slam');
    const box = t.closest('#end-screen') || t.closest('.pvp-panel') || t.closest('.text-center') || t.parentElement; if (!box) return;
    const rows = [...box.querySelectorAll('.story-reward, .story-drops, .story-explist > *, #end-mvp-wrap > *, #end-stats > *, .pvp-round, .pvp-delta, .pvp-res-streak, .text-amber-200, .story-stars, .sc-stars')].filter(x => !x.closest('button')).slice(0, 14);
    rows.forEach((r, i) => { r.style.setProperty('--ri', i); r.classList.add('ui-rise'); }); };
  // (c) 불러오는 중 자리: 반짝이는 뼈대 막대 (글자 '…' · '불러오는 중' 인 자리만)
  const SKEL = '.gd-loading, .pvp-empty, .dsp-empty, .gear-dim, .gd-empty, .vr-page-body > div, .story-pop-panel > div';
  const skelFx = n => { const t = (n.textContent || '').trim(); if (n.children.length > 1 || !(t === '…' || t === '...' || /^불러오는 중/.test(t))) return; n.classList.add('ui-skel'); n.setAttribute('aria-busy', 'true'); };
  // (d) 빨간 알림 점: 처음 나타날 때 톡 (같은 점이 다시 그려질 땐 없음)
  const DOTS = '.gd-dot, .gd-badge, .gear-badge, .story-badge, .fr-tabbadge';
  const dotKey = d => (d.closest('[data-t],[data-go],[data-tab],button')?.outerHTML.slice(0, 80) || '') + '|' + d.textContent;
  const dotSeen = new Set();
  const dotFx = d => { if (d.hidden || d.closest('#game')) return; const k = dotKey(d); if (dotSeen.has(k)) return; dotSeen.add(k); replay(d, 'ui-dot-pop'); };
  let p3q = 0;
  const scan3 = () => { p3q = 0;
    for (const t of document.querySelectorAll(RES_T)) if (t.offsetParent || t.closest('#end-screen')) resultFx(t);
    for (const n of document.querySelectorAll(SKEL)) if (!n.classList.contains('ui-skel')) skelFx(n);
    for (const n of document.querySelectorAll('.ui-skel')) { const t = (n.textContent || '').trim(); if (n.children.length > 1 || !(t === '…' || t === '...' || /^불러오는 중/.test(t))) { n.classList.remove('ui-skel'); n.removeAttribute('aria-busy'); } }   // 같은 자리에 글(오류 등)이 들어오면 원래대로
    for (const d of document.querySelectorAll(DOTS)) if (d.offsetParent) dotFx(d); };
  new MutationObserver(() => { if (inBattle()) return; if (!p3q) p3q = requestAnimationFrame(scan3); }).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden', 'class'] });
})();
