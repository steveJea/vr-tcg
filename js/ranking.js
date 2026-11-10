import { config } from './config.js';
// ===== 랭킹 팝업: 아케이드(rankings_weekly/all) · 시탑(tower_rankings) · PVP(pvp_rankings) · 스토리(story_rankings). anon 키로 공개 조회 =====
(() => {
  const IC = n => window.VRIcon?.icon(n) || '';   // js/icons.js
  const URL_ = config.enabled ? config.supabaseUrl + '/rest/v1/' : '';
  const KEY = config.anonKey;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  let main = 'arcade', tab = 'weekly', tower = 'normal', league = 'open', pmode = '1v1';
  const MAIN = [['arcade', '아케이드'], ['tower', '시탑'], ['pvp', 'PVP'], ['story', '스토리']];
  const TOWERS = [['normal', '시련'], ['wind', '바람'], ['ice', '얼음'], ['fire', '불'], ['light', '빛'], ['dark', '어둠']];
  const LEAGUES = [['open', '무제한'], ['hr', 'HR↓']], PMODES = [['1v1', '1v1'], ['3v3', '3v3'], ['boss', '보스']];

  const css = document.createElement('style');
  css.textContent = `
  #rank-ov{position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,.7);display:none;align-items:center;justify-content:center;padding:12px}
  #rank-ov.on{display:flex}
  #rank-box{width:100%;max-width:440px;max-height:86vh;min-height:min(560px,80vh);display:flex;flex-direction:column;background:linear-gradient(#1e1530,#0e0a18);border:1px solid rgba(251,191,36,.45);border-radius:16px;color:#fde68a;box-shadow:0 10px 40px rgba(0,0,0,.6)}
  #rank-box .rh{display:flex;justify-content:space-between;align-items:center;padding:12px 14px 6px;font-weight:800;font-size:18px}
  #rank-box .rx{background:none;border:0;color:#fde68a;font-size:22px;cursor:pointer}
  #rank-box .rt{display:flex;gap:6px;padding:0 14px}
  #rank-box .rt button{flex:1;padding:7px;border-radius:10px;border:1px solid rgba(251,191,36,.35);background:rgba(0,0,0,.3);color:#fde68a;font-weight:700;cursor:pointer}
  #rank-box .rt button.on{background:#f59e0b;color:#1a1200}
  #rank-box .rm{display:flex;gap:4px;padding:0 14px 8px}
  #rank-box .rm button{flex:1;padding:8px 2px;border:0;border-bottom:2px solid transparent;background:none;color:#fde68a;opacity:.65;font-weight:800;font-size:14px;cursor:pointer}
  #rank-box .rm button.on{opacity:1;border-bottom-color:#f59e0b}
  #rank-box .rt{flex-wrap:wrap}
  #rank-box .rt+.rt{margin-top:6px}
  #rank-box .rt button{min-width:0;font-size:12px;white-space:nowrap}
  #rank-box .rn{font-size:11px;opacity:.7;padding:6px 14px}
  #rank-box .rl{overflow:auto;padding:0 10px 6px;flex:1}
  #rank-box table{width:100%;border-collapse:collapse;font-size:13px}
  #rank-box th{position:sticky;top:0;background:#1a1229;font-size:11px;opacity:.85;padding:6px 4px;font-weight:600}
  #rank-box td{padding:7px 4px;text-align:center;border-top:1px solid rgba(255,255,255,.06);color:#fef3c7}
  #rank-box td.nm{text-align:left;max-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  #rank-box tr.me td{background:rgba(245,158,11,.22);color:#fff;font-weight:700}
  #rank-box .mine{margin:0 10px;border-top:1px dashed rgba(251,191,36,.5)}
  #rank-box .rf{padding:8px 14px 12px;font-size:12px;text-align:center;opacity:.9}
  #rank-box .rf button{margin-left:6px;text-decoration:underline;background:none;border:0;color:#fbbf24;cursor:pointer;font-size:12px}
  #rank-box .empty{padding:36px 0;text-align:center;opacity:.8}`;
  document.head.appendChild(css);

  const ov = document.createElement('div');
  ov.id = 'rank-ov';
  ov.innerHTML = `<div id="rank-box" role="dialog" aria-label="랭킹">
    <div class="rh"><span>${IC('rank')} 랭킹</span><button class="rx" aria-label="닫기">×</button></div>
    <div class="rm">${MAIN.map(([k, l]) => `<button data-m="${k}">${l}</button>`).join('')}</div><div class="rsub"></div>
    <div class="rn"></div><div class="rl"></div><div class="mine"></div><div class="rf"></div></div>`;
  document.body.appendChild(ov);
  const $ = s => document.getElementById('rank-box').querySelector(s);   // 판이 페이지로 옮겨가도 찾게
  ov.addEventListener('click', e => { if (e.target === ov) close(); });
  $('.rx').onclick = close;
  ov.querySelectorAll('.rm button').forEach(b => b.onclick = () => { main = b.dataset.m; load(); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && ov.classList.contains('on')) close(); });

  // 페이지 시스템: 랭킹 판(#rank-box)을 페이지 몸통으로 옮겼다가 떠날 때 돌려놓음. 없거나 실패하면 예전 팝업
  const box = ov.querySelector('#rank-box');
  window.VRPages?.register?.('ranking', { title: '🏆 랭킹', render: body => body.appendChild(box), leave: () => ov.appendChild(box) });
  function close() { if (window.VRPages?.current === 'ranking') return window.VRPages.closeNow(); ov.classList.remove('on'); }
  function open(m) { main = typeof m === 'string' && MAIN.some(x => x[0] === m) ? m : 'arcade'; if (!window.VRPages?.open?.('ranking')) ov.classList.add('on'); load(); }

  async function token() {
    try { const sb = window.VRCloud?.sb; if (!sb || !window.VRCloud.user) return null; const { data } = await sb.auth.getSession(); return data?.session?.access_token || null; } catch { return null; }
  }
  async function q(path, tok) {
    if (!config.enabled) throw new Error(config.reason);
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000);
    try {
      const r = await fetch(URL_ + path, { signal: ctl.signal, headers: { apikey: KEY, Authorization: 'Bearer ' + (tok || KEY) } });
      if (!r.ok) throw new Error(r.status); return await r.json();
    } finally { clearTimeout(t); }
  }
  const wdl = r => r.draws == null ? `${r.wins}승` : `${r.wins}/${r.draws}/${r.losses}`;
  const row = r => `<tr class="${r.is_me ? 'me' : ''}"><td>${r.rank <= 3 ? (window.VRIcon?.icon(`rank_${r.rank}`, { alt: `${r.rank}위` }) || ['🥇','🥈','🥉'][r.rank - 1]) : r.rank}</td><td class="nm">${esc(r.nickname)}${r.is_me ? ' (나)' : ''}</td><td>${r.score}</td><td>${wdl(r)}</td></tr>`;
  const head = `<tr><th>순위</th><th style="text-align:left">닉네임</th><th>점수</th><th>승/무/패</th></tr>`;

  async function rpc(name, args, tok) {
    if (!config.enabled) throw new Error(config.reason);
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000);
    try {
      const r = await fetch(URL_ + 'rpc/' + name, { method: 'POST', signal: ctl.signal, headers: { apikey: KEY, Authorization: 'Bearer ' + (tok || KEY), 'Content-Type': 'application/json' }, body: JSON.stringify(args || {}) });
      if (!r.ok) throw new Error(r.status); return await r.json();
    } finally { clearTimeout(t); }
  }
  const medal = n => n <= 3 ? (window.VRIcon?.icon(`rank_${n}`, { alt: `${n}위` }) || ['🥇','🥈','🥉'][n - 1]) : n;
  const subBar = (list, cur, key) => `<div class="rt">${list.map(([k, l]) => `<button data-${key}="${k}" class="${k === cur ? 'on' : ''}">${l}</button>`).join('')}</div>`;
  // 시탑·PVP·스토리 공용: { top:[{rank,name,me,...}], me:{rank,...} } 형태를 표로
  const SPEC = {
    tower: { th: ['최고 층'], td: r => [`${r.floor}층`], note: () => '탑마다 가장 높이 올라간 층 기준이에요 · 같은 층이면 먼저 도달한 사람이 위' },
    pvp: { th: ['점수', '승/패'], td: r => [r.rating, `${r.wins}/${r.losses}`], note: () => '이번 시즌 PvP 점수 기준이에요 · 매주 새 시즌' },
    story: { th: ['진행'], td: r => [`${r.ch}-${r.ph}`], note: () => '<details class="vr-tip"><summary>ⓘ</summary><p>깬 곳 중 가장 먼 챕터-페이즈예요 (예: 9-15 = 9챕터 15페이즈)</p></details>' },
  };
  const nmCell = (r, nm) => { const label = (nm ?? r.name) + (r.me && nm == null ? ' (나)' : ''); const t = r.title_name || ''; return window.VRCosmo ? `${esc(label)}${t ? `<i class="cosmo-ttl t-${esc(r.title || '')}"> ${esc(t)}</i>` : ''}` : esc(label); };
  const row2 = (sp, r, nm) => `<tr class="${r.me ? 'me' : ''}"><td>${medal(r.rank)}</td><td class="nm">${nmCell(r, nm)}</td>${sp.td(r).map(v => `<td>${esc(v)}</td>`).join('')}</tr>`;
  async function loadOther(cur, tok) {
    const sp = SPEC[main];
    $('.rn').innerHTML = sp.note();
    let r;
    try {
      r = main === 'tower' ? await rpc('tower_rankings', { p_tower: tower }, tok)
        : main === 'pvp' ? await rpc('pvp_rankings', { p_league: league, p_mode: pmode, p_season: null }, tok)
        : await rpc('story_rankings', {}, tok);
    } catch { if (cur === key()) $('.rl').innerHTML = '<div class="empty">랭킹 서버에 연결할 수 없어요.<br>잠시 후 다시 시도해 주세요.</div>'; return; }
    if (cur !== key()) return;
    const top = r?.top || [];
    if (!top.length) { $('.rl').innerHTML = '<div class="empty">기록 없음</div>'; return; }
    $('.rl').innerHTML = `<table><tr><th>순위</th><th style="text-align:left">닉네임</th>${sp.th.map(h => `<th>${h}</th>`).join('')}</tr>${top.map(x => row2(sp, x)).join('')}</table>`;
    if (r.me && !top.some(x => x.me)) $('.mine').innerHTML = `<table>${row2(sp, { ...r.me, me: true }, '나')}</table>`;
  }
  const key = () => [main, tab, tower, league, pmode].join('|');

  async function load() {
    box.querySelectorAll('.rm button').forEach(b => b.classList.toggle('on', b.dataset.m === main));
    const sub = $('.rsub');
    sub.innerHTML = main === 'arcade' ? subBar([['weekly', '주간'], ['all', '전체']], tab, 't')
      : main === 'tower' ? subBar(TOWERS, tower, 'tw')
      : main === 'pvp' ? subBar(LEAGUES, league, 'lg') + subBar(PMODES, pmode, 'pm') : '';
    sub.querySelectorAll('button').forEach(b => b.onclick = () => { const d = b.dataset; if (d.t) tab = d.t; if (d.tw) tower = d.tw; if (d.lg) league = d.lg; if (d.pm) pmode = d.pm; load(); });
    if (main !== 'arcade') {
      $('.rl').innerHTML = '<div class="empty">불러오는 중...</div>'; $('.mine').innerHTML = '';
      const logged = !!window.VRCloud?.user, cur = key();
      $('.rf').innerHTML = logged ? '' : `<button id="rank-login">${IC('login')} 🔑 로그인</button>`;
      const lb = $('#rank-login'); if (lb) lb.onclick = () => window.VRCloud ? window.VRCloud.login() : (window.VRGem?.toast || alert)('지금은 로그인 서버에 연결할 수 없어요.');
      return loadOther(cur, logged ? await token() : null);
    }
    $('.rn').textContent = tab === 'weekly' ? `⏱ ${(() => { const now = Date.now() + 9 * 3600e3, day = 86400e3, wd = (Math.floor(now / day) + 4) % 7, into = now % day, ahead = (1 - wd + 7) % 7, ms = ahead === 0 ? (into === 0 ? 7 * day : 7 * day - into) : ahead * day - into, h = Math.floor(ms / 3600e3), m = Math.floor(ms % 3600e3 / 6e4); return Math.floor(h / 24) + '일 ' + (h % 24) + ':' + String(m).padStart(2, '0'); })()} · 승3 무1` : '승3 무1';
    $('.rl').innerHTML = '<div class="empty">불러오는 중...</div>'; $('.mine').innerHTML = '';
    const logged = !!window.VRCloud?.user;
    $('.rf').innerHTML = logged ? '' : `<button id="rank-login">${IC('login')} 🔑 로그인</button>`;
    const lb = $('#rank-login'); if (lb) lb.onclick = () => window.VRCloud ? window.VRCloud.login() : (window.VRGem?.toast || alert)('지금은 로그인 서버에 연결할 수 없어요.');
    const view = tab === 'weekly' ? 'rankings_weekly' : 'rankings_all', cur = key();
    const tok = logged ? await token() : null;
    let rows;
    try { rows = await q(`${view}?select=*&order=rank.asc&limit=50`, tok); }
    catch { if (cur === key()) $('.rl').innerHTML = '<div class="empty">랭킹 서버에 연결할 수 없어요.<br>잠시 후 다시 시도해 주세요.</div>'; return; }
    if (cur !== key()) return;
    if (!rows.length) { $('.rl').innerHTML = '<div class="empty">기록 없음</div>'; return; }
    $('.rl').innerHTML = `<table>${head}${rows.map(row).join('')}</table>`;
    if (tok && !rows.some(r => r.is_me)) {
      try {
        const me = await q(`${view}?select=*&is_me=eq.true&limit=1`, tok);
        if (cur === key() && me[0]) $('.mine').innerHTML = `<table>${row(me[0])}</table>`;
        else if (cur === key()) $('.rf').textContent = '기록 없음';
      } catch {}
    }
  }
  window.VRRanking = { open, close };
  const bind = () => { const b = document.getElementById('main-rank'); if (b) b.onclick = open; };
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', bind) : bind();
})();
