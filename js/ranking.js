// ===== 랭킹 팝업 (Supabase rankings_weekly / rankings_all, anon 키로 공개 조회) =====
(() => {
  const IC = n => window.VRIcon?.icon(n) || '';   // js/icons.js
  const URL_ = 'https://htarwisgkkphutxxnuak.supabase.co/rest/v1/';
  const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0YXJ3aXNna2twaHV0eHhudWFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNTMwOTgsImV4cCI6MjEwNzcyOTA5OH0.xaIda-o8QwRhoG5yDRLAcMo8LbU1rNHUA7xznO-tEfc';
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  let tab = 'weekly';

  const css = document.createElement('style');
  css.textContent = `
  #rank-ov{position:fixed;inset:0;z-index:9000;background:rgba(0,0,0,.7);display:none;align-items:center;justify-content:center;padding:12px}
  #rank-ov.on{display:flex}
  #rank-box{width:100%;max-width:440px;max-height:86vh;display:flex;flex-direction:column;background:linear-gradient(#1e1530,#0e0a18);border:1px solid rgba(251,191,36,.45);border-radius:16px;color:#fde68a;box-shadow:0 10px 40px rgba(0,0,0,.6)}
  #rank-box .rh{display:flex;justify-content:space-between;align-items:center;padding:12px 14px 6px;font-weight:800;font-size:18px}
  #rank-box .rx{background:none;border:0;color:#fde68a;font-size:22px;cursor:pointer}
  #rank-box .rt{display:flex;gap:6px;padding:0 14px}
  #rank-box .rt button{flex:1;padding:7px;border-radius:10px;border:1px solid rgba(251,191,36,.35);background:rgba(0,0,0,.3);color:#fde68a;font-weight:700;cursor:pointer}
  #rank-box .rt button.on{background:#f59e0b;color:#1a1200}
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
    <div class="rt"><button data-t="weekly">주간</button><button data-t="all">전체</button></div>
    <div class="rn"></div><div class="rl"></div><div class="mine"></div><div class="rf"></div></div>`;
  document.body.appendChild(ov);
  const $ = s => ov.querySelector(s);
  ov.addEventListener('click', e => { if (e.target === ov) close(); });
  $('.rx').onclick = close;
  ov.querySelectorAll('.rt button').forEach(b => b.onclick = () => { tab = b.dataset.t; load(); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && ov.classList.contains('on')) close(); });

  function close() { ov.classList.remove('on'); }
  function open() { ov.classList.add('on'); load(); }

  async function token() {
    try { const sb = window.VRCloud?.sb; if (!sb || !window.VRCloud.user) return null; const { data } = await sb.auth.getSession(); return data?.session?.access_token || null; } catch { return null; }
  }
  async function q(path, tok) {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000);
    try {
      const r = await fetch(URL_ + path, { signal: ctl.signal, headers: { apikey: KEY, Authorization: 'Bearer ' + (tok || KEY) } });
      if (!r.ok) throw new Error(r.status); return await r.json();
    } finally { clearTimeout(t); }
  }
  const wdl = r => r.draws == null ? `${r.wins}승` : `${r.wins}/${r.draws}/${r.losses}`;
  const row = r => `<tr class="${r.is_me ? 'me' : ''}"><td>${r.rank <= 3 ? ['🥇','🥈','🥉'][r.rank - 1] : r.rank}</td><td class="nm">${esc(r.nickname)}${r.is_me ? ' (나)' : ''}</td><td>${r.score}</td><td>${wdl(r)}</td></tr>`;
  const head = `<tr><th>순위</th><th style="text-align:left">닉네임</th><th>점수</th><th>승/무/패</th></tr>`;

  async function load() {
    ov.querySelectorAll('.rt button').forEach(b => b.classList.toggle('on', b.dataset.t === tab));
    $('.rn').textContent = tab === 'weekly' ? '주간 랭킹은 매주 월요일 0시(한국 시간)에 초기화돼요 · 승 3점, 무 1점' : '서비스 시작부터 누적된 점수예요 · 승 3점, 무 1점';
    $('.rl').innerHTML = '<div class="empty">불러오는 중...</div>'; $('.mine').innerHTML = '';
    const logged = !!window.VRCloud?.user;
    $('.rf').innerHTML = logged ? '' : `로그인하면 랭킹에 참여할 수 있어요!<button id="rank-login">${IC('login')} 구글로 로그인</button>`;
    const lb = $('#rank-login'); if (lb) lb.onclick = () => window.VRCloud ? window.VRCloud.login() : alert('지금은 로그인 서버에 연결할 수 없어요.');
    const view = tab === 'weekly' ? 'rankings_weekly' : 'rankings_all', cur = tab;
    const tok = logged ? await token() : null;
    let rows;
    try { rows = await q(`${view}?select=*&order=rank.asc&limit=50`, tok); }
    catch { if (cur === tab) $('.rl').innerHTML = '<div class="empty">랭킹 서버에 연결할 수 없어요.<br>잠시 후 다시 시도해 주세요.</div>'; return; }
    if (cur !== tab) return;
    if (!rows.length) { $('.rl').innerHTML = '<div class="empty">아직 기록이 없어요</div>'; return; }
    $('.rl').innerHTML = `<table>${head}${rows.map(row).join('')}</table>`;
    if (tok && !rows.some(r => r.is_me)) {
      try {
        const me = await q(`${view}?select=*&is_me=eq.true&limit=1`, tok);
        if (cur === tab && me[0]) $('.mine').innerHTML = `<table>${row(me[0])}</table>`;
        else if (cur === tab) $('.rf').textContent = tab === 'weekly' ? '이번 주 기록이 아직 없어요. 한 판 해보세요!' : '아직 기록이 없어요. 한 판 해보세요!';
      } catch {}
    }
  }
  window.VRRanking = { open, close };
  const bind = () => { const b = document.getElementById('main-rank'); if (b) b.onclick = open; };
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', bind) : bind();
})();
