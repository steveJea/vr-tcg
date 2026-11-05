// ===== 훈련소 1단계 (서버: supabase/camp.sql) =====
// 인재를 칸에 넣어 두면 시간이 지나며 EXP 가 쌓임 (칸당 시간당 20 + 플레이어 Lv × 1.5, 최대 24시간, 상한 min(등급 최대, 플레이어 Lv − 5))
// 마이페이지 [🏋️ 훈련소] 버튼 · 받을 EXP 가 있으면 빨간 점. 시간·EXP 는 전부 서버가 계산 (화면은 보여주기만)
(() => {
  const G = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE'];
  const GS = ['N', 'R', 'HR', 'SR', 'UR', 'MR', 'LR'], GC = ['#9ca3af', '#22c55e', '#3b82f6', '#a855f7', '#f59e0b', '#ef4444', '#ef4444'];
  const GCAP = [20, 30, 40, 50, 60, 70, 70];
  const ERR = { 'slot locked': '아직 열지 않은 칸이에요', 'slot busy': '이미 인재가 있는 칸이에요', 'already training': '이미 훈련 중인 인재예요', 'not owned': '보유하지 않은 인재예요',
    'at cap': '훈련소에서 올릴 수 있는 최대 레벨이에요', 'already open': '이미 열린 칸이에요', 'open previous': '앞 칸부터 열어 주세요', 'need level': '플레이어 레벨이 부족해요',
    'not enough gold': '골드가 부족해요', 'not enough gem': '심연석이 부족해요' };
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const errText = e => { const m = e?.message || String(e); for (const k in ERR) if (m.includes(k)) return ERR[k]; return '⚠️ ' + m; };
  const toast = t => { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); };
  const fmt = n => Number(n || 0).toLocaleString('ko-KR');
  let st = null, owned = [], off = false, tick = 0;

  async function rpc(name, args) {
    if (window.VRCamp?._mock) return window.VRCamp._mock(name, args);
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) throw new Error('login required');
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (/function .* does not exist|Could not find the function/i.test(error.message || '')) off = true; throw error; }
    return data;
  }
  const meta = o => { const c = window.TCG?.cardById?.(o.id) || {}; return { ...o, g: Math.max(0, G.indexOf(c.grade || o.grade)), name: o.name || c.name || o.id }; };
  const capOf = c => Math.min(GCAP[c.g] + 5 * (c.ex | 0), (st?.level || 1) - (st?.cap_minus ?? 5));
  const costText = c => c?.gold ? `💰 ${fmt(c.gold)}` : c?.gem ? `🔮 ${fmt(c.gem)}` : '무료';
  const sinceText = t => { if (!t) return ''; const h = Math.min(st.max_hours, (Date.now() - new Date(t)) / 3600e3); return h >= st.max_hours ? `⏱ ${st.max_hours}시간 가득 (더 안 쌓여요)` : `⏱ ${Math.floor(h)}시간 ${Math.floor(h % 1 * 60)}분 쌓임 / 최대 ${st.max_hours}시간`; };
  const ready = () => (st?.slots || []).some(s => s.pending > 0);

  const css = document.createElement('style');
  css.textContent = `
  #camp-ov{position:fixed;inset:0;z-index:8800;background:rgba(0,0,0,.72);display:flex;align-items:center;justify-content:center;padding:10px}
  #camp-box{width:100%;max-width:480px;max-height:92vh;display:flex;flex-direction:column;background:linear-gradient(#1e1530,#0e0a18);border:1px solid rgba(251,191,36,.45);border-radius:16px;color:#fde68a;box-shadow:0 10px 40px rgba(0,0,0,.6)}
  #camp-box .ch{display:flex;justify-content:space-between;align-items:center;padding:12px 14px 4px;font-weight:800;font-size:18px}
  #camp-box .cx{background:none;border:0;color:#fde68a;font-size:22px;cursor:pointer}
  #camp-box .csub{padding:0 14px 6px;font-size:11px;opacity:.8;line-height:1.5}
  #camp-box .cbody{overflow:auto;padding:0 10px 8px;flex:1}
  .camp-slot{display:flex;align-items:center;gap:8px;padding:10px;margin-bottom:6px;border-radius:12px;background:rgba(0,0,0,.32);border:1px solid rgba(251,191,36,.18);color:#fef3c7}
  .camp-slot.ready{border-color:#22c55e}.camp-slot.locked{opacity:.75;border-style:dashed}
  .camp-no{width:26px;height:26px;flex:none;border-radius:8px;background:rgba(255,255,255,.08);display:flex;align-items:center;justify-content:center;font-weight:900;font-size:13px}
  .camp-slot .grow{flex:1;min-width:0}.camp-slot small{display:block;font-size:11px;opacity:.8;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .camp-slot b{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .camp-bar{height:6px;margin:4px 0 2px;border-radius:99px;background:rgba(255,255,255,.1);overflow:hidden}.camp-bar i{display:block;height:100%;background:linear-gradient(90deg,#f59e0b,#fde68a)}
  .camp-g{display:inline-block;padding:1px 6px;border-radius:6px;font-size:11px;font-weight:800;color:#111}
  .camp-pend{color:#86efac;font-weight:800}
  .camp-slot button,.camp-acts button{padding:8px 10px;border-radius:10px;border:1px solid rgba(251,191,36,.35);background:rgba(0,0,0,.3);color:#fde68a;font-weight:700;cursor:pointer;font-size:13px;white-space:nowrap}
  .camp-slot button.go,.camp-acts button.go{background:#f59e0b;color:#1a1200}
  .camp-slot button:disabled,.camp-acts button:disabled{opacity:.45}
  .camp-acts{display:flex;gap:6px;padding:8px 10px 12px;border-top:1px solid rgba(255,255,255,.08)}.camp-acts button{flex:1;padding:10px 4px}
  .camp-empty{padding:12px;text-align:center;opacity:.7;font-size:12px;line-height:1.5}
  .camp-list{display:grid;grid-template-columns:repeat(auto-fill,minmax(96px,1fr));gap:6px}
  .camp-card{padding:7px 6px;border-radius:10px;background:rgba(0,0,0,.35);border:2px solid transparent;color:#fef3c7;font-size:12px;text-align:left;cursor:pointer;line-height:1.35}
  .camp-card b{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.camp-card:hover{border-color:#f59e0b}
  .mp-navbtn{position:relative}.mp-navbtn [data-campdot]{font-style:normal}.mp-navbtn .camp-dot{position:absolute;top:6px;right:8px;width:10px;height:10px;border-radius:50%;background:#ef4444;box-shadow:0 0 0 2px #14111f}`;
  document.head.appendChild(css);

  function shell(title, sub) {
    let ov = document.getElementById('camp-ov');
    if (!ov) { ov = document.createElement('div'); ov.id = 'camp-ov'; document.body.appendChild(ov); ov.addEventListener('click', e => { if (e.target === ov) close(); }); }
    ov.innerHTML = `<div id="camp-box" role="dialog" aria-label="훈련소"><div class="ch"><span>${title}</span><button class="cx" aria-label="닫기">×</button></div><div class="csub">${sub || ''}</div><div class="cbody"></div></div>`;
    ov.querySelector('.cx').onclick = close;
    return ov.querySelector('#camp-box');
  }
  function close() { document.getElementById('camp-ov')?.remove(); clearInterval(tick); paint(); }
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && document.getElementById('camp-ov')) close(); });

  async function load() { st = await rpc('camp_status'); try { const s = await window.VRStory?.summary?.(); owned = (s?.ok ? s.owned : []).map(meta); } catch { owned = []; } paint(); return st; }
  async function open() {
    const box = shell('🏋️ 훈련소'); box.querySelector('.cbody').innerHTML = '<div class="camp-empty">불러오는 중...</div>';
    try { await load(); } catch (e) { box.querySelector('.cbody').innerHTML = `<div class="camp-empty">${off ? '훈련소 준비 중이에요' : esc(errText(e))}</div>`; return; }
    draw();
  }

  function slotHTML(s, firstLocked) {
    if (!s.open) {
      const can = s.slot === firstLocked && st.level >= s.need_level;
      return `<div class="camp-slot locked"><span class="camp-no">🔒</span><div class="grow"><b>${s.slot}번 칸</b><small>플레이어 Lv${s.need_level} · ${costText(s.cost)}</small></div>
        ${s.slot === firstLocked ? `<button class="go" data-unlock="${s.slot}" ${can ? '' : 'disabled'}>${can ? '열기' : `Lv${s.need_level}`}</button>` : ''}</div>`;
    }
    if (!s.uid) return `<div class="camp-slot"><span class="camp-no">${s.slot}</span><div class="grow"><b>비어 있어요</b><small>인재를 넣으면 시간당 EXP ${fmt(Math.floor(st.rate))}</small></div><button class="go" data-put="${s.slot}">넣기</button></div>`;
    const c = meta(s.card || owned.find(o => o.uid === s.uid) || { id: '?' }), lv = c.level || 1, cap = capOf(c), need = lv * 100, pct = lv >= cap ? 100 : Math.min(100, (c.exp || 0) / need * 100);
    return `<div class="camp-slot ${s.pending > 0 ? 'ready' : ''}"><span class="camp-no">${s.slot}</span><div class="grow"><span class="camp-g" style="background:${GC[c.g]}">${GS[c.g]}</span> <b>${esc(c.name)}</b> Lv${lv}<small style="opacity:.6">/ 최대 Lv${cap}</small>
      <div class="camp-bar"><i style="width:${pct}%"></i></div><small>${s.pending > 0 ? `<span class="camp-pend">+${fmt(s.pending)} EXP 받을 수 있어요</span>` : lv >= cap ? '최대 레벨이에요. 빼 주세요' : '쌓이는 중...'}</small><small data-since="${esc(s.last_at || '')}">${sinceText(s.last_at)}</small></div>
      <button data-remove="${s.slot}">빼기</button></div>`;
  }

  function draw() {
    const box = shell('🏋️ 훈련소', `칸당 시간당 EXP ${fmt(Math.floor(st.rate))} (20 + 플레이어 Lv${st.level} × 1.5) · 최대 ${st.max_hours}시간 쌓임<br>최대 레벨: 등급 최대와 플레이어 Lv − ${st.cap_minus ?? 5} 중 낮은 쪽 · 훈련 중에도 덱에서 쓸 수 있어요`);
    const firstLocked = (st.slots.find(s => !s.open) || {}).slot, total = st.slots.reduce((a, s) => a + (s.pending || 0), 0);
    box.querySelector('.cbody').innerHTML = st.level < st.slots[0].need_level
      ? `<div class="camp-empty">플레이어 Lv${st.slots[0].need_level}부터 훈련소를 쓸 수 있어요</div>`
      : st.slots.map(s => slotHTML(s, firstLocked)).join('') + '<div class="camp-empty">훈련 중인 인재는 거래·분해·합성 재료로 쓸 수 없어요</div>';
    box.insertAdjacentHTML('beforeend', `<div class="camp-acts"><button class="go" data-all ${total ? '' : 'disabled'}>🎁 모두 받기${total ? ` (+${fmt(total)} EXP)` : ''}</button></div>`);
    box.querySelectorAll('[data-put]').forEach(b => b.onclick = () => pick(+b.dataset.put));
    box.querySelectorAll('[data-remove]').forEach(b => b.onclick = async () => {
      if (!await (window.VRAsk ? window.VRAsk('빼면 지금까지 쌓인 EXP 를 받고 칸이 비어요. 뺄까요?') : confirm('뺄까요?'))) return;
      try { const r = await rpc('camp_remove', { p_slot: +b.dataset.remove }); done(r); } catch (e) { toast(errText(e)); } });
    box.querySelectorAll('[data-unlock]').forEach(b => b.onclick = async () => {
      const s = st.slots.find(x => x.slot === +b.dataset.unlock);
      if (!await (window.VRAsk ? window.VRAsk(`${costText(s.cost)}(으)로 ${s.slot}번 칸을 열까요?`) : confirm('열까요?'))) return;
      try { st = await rpc('camp_unlock', { p_slot: s.slot }); toast(`🔓 ${s.slot}번 칸을 열었어요`); if (s.cost?.gem) window.VRGem?.status?.(true); window.VRPlayer?.status?.(true); draw(); } catch (e) { toast(errText(e)); } });
    box.querySelector('[data-all]').onclick = async () => { try { done(await rpc('camp_claim')); } catch (e) { toast(errText(e)); } };
    clearInterval(tick); tick = setInterval(() => { if (!document.getElementById('camp-ov')) return clearInterval(tick);
      document.querySelectorAll('#camp-box [data-since]').forEach(el => { if (el.dataset.since) el.textContent = sinceText(el.dataset.since); }); }, 30000);
    paint();
  }

  async function done(r) {
    st = r; const got = (r.got || []).filter(x => x.exp > 0);
    if (got.length) toast(`🏋️ EXP +${fmt(got.reduce((a, x) => a + x.exp, 0))}${got.some(x => x.level > x.from) ? ' · LEVEL UP!' : ''}`);
    try { const s = await window.VRStory?.summary?.(); owned = (s?.ok ? s.owned : owned).map(meta); } catch {}
    draw();
  }

  // 인재 고르기: 훈련 중·최대 레벨 인재 제외, 레벨 낮은 순
  function pick(slot) {
    const busy = new Set(st.slots.map(s => s.uid).filter(Boolean));
    const pool = owned.filter(c => !busy.has(c.uid) && (c.level || 1) < capOf(c)).sort((a, b) => (a.level || 1) - (b.level || 1) || a.g - b.g);
    const box = shell(`🏋️ ${slot}번 칸에 넣을 인재`, `레벨이 낮은 인재부터 보여요 · 최대 Lv${Math.max(0, st.level - (st.cap_minus ?? 5))}까지 (등급 최대가 더 낮으면 그쪽)`);
    box.querySelector('.cbody').innerHTML = `<div class="camp-list">${pool.map(c => `<button class="camp-card" data-u="${esc(c.uid)}"><span class="camp-g" style="background:${GC[c.g]}">${GS[c.g]}</span> Lv${c.level || 1}<b>${esc(c.name)}</b><span style="font-size:10px;opacity:.8">최대 Lv${capOf(c)}</span></button>`).join('') || '<div class="camp-empty">넣을 수 있는 인재가 없어요</div>'}</div>`;
    box.insertAdjacentHTML('beforeend', '<div class="camp-acts"><button data-back>뒤로</button></div>');
    box.querySelector('[data-back]').onclick = draw;
    box.querySelectorAll('[data-u]').forEach(b => b.onclick = async () => { b.disabled = true;
      try { st = await rpc('camp_put', { p_slot: slot, p_uid: b.dataset.u }); toast('🏋️ 훈련을 시작했어요'); draw(); } catch (e) { toast(errText(e)); b.disabled = false; } });
  }

  // 마이페이지 버튼 빨간 점
  function paint() { document.querySelectorAll('[data-campdot]').forEach(el => { el.innerHTML = ready() ? '<i class="camp-dot" aria-label="받을 EXP 있음"></i>' : ''; }); }
  async function refresh() { if (off || (!window.VRCloud?.user && !window.VRCamp?._mock)) return paint(); try { st = await rpc('camp_status'); } catch {} paint(); }
  window.addEventListener('vr:user', () => setTimeout(refresh, 2000));
  setInterval(refresh, 10 * 60e3);
  new MutationObserver(() => { if (document.querySelector('[data-campdot]:empty') && ready()) paint(); }).observe(document.body, { childList: true, subtree: true });
  window.VRCamp = { open, close, refresh, ready, get off() { return off; }, _set: (s, o) => { st = s; owned = o.map(meta); paint(); }, _draw: () => draw(), _pick: s => pick(s) };
})();
