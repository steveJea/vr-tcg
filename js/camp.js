// ===== 훈련소 1단계 (서버: supabase/camp.sql) =====
// 인재를 칸에 넣어 두면 시간이 지나며 EXP 가 쌓임 (칸당 시간당 20 + 플레이어 Lv × 1.5, 최대 24시간, 상한 min(등급 최대, 플레이어 Lv − 5))
// 마이페이지 [🏋️ 훈련소] 버튼 · 받을 EXP 가 있으면 빨간 점. 시간·EXP 는 전부 서버가 계산 (화면은 보여주기만)
(() => {
  const G = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE'];
  const GS = ['N', 'R', 'HR', 'SR', 'UR', 'MR', 'LR'], GC = ['#9ca3af', '#22c55e', '#3b82f6', '#a855f7', '#f59e0b', '#ef4444', '#ef4444'];
  const GCAP = [20, 30, 40, 50, 60, 70, 70];
  const ERR = { 'slot locked': '아직 열지 않은 칸이에요', 'slot busy': '이미 인재가 있는 칸이에요', 'already training': '이미 훈련 중인 인재예요', 'not owned': '보유하지 않은 인재예요',
    'at cap': '훈련소에서 올릴 수 있는 최대 레벨이에요', 'already open': '이미 열린 칸이에요', 'open previous': '앞 칸부터 열어 주세요', 'need level': '플레이어 레벨이 부족해요',
    'not enough gold': '골드가 부족해요', 'not enough gem': '심연석이 부족해요', 'not enough dust': '장비 가루가 부족해요', 'not enough soul': '각성자의 혼이 부족해요',
    'max camp level': '훈련소가 최대 레벨이에요', 'forge locked': '🔒 Lv20', 'forge busy': '연마소에 이미 장비가 있어요', 'max plus': '이미 +5 장비예요',
    'dojo locked': '도장이 아직 안 열렸어요', 'dojo max': '도장에서는 스킬 Lv7까지만 올릴 수 있어요', 'skill locked': '아직 배우지 않은 스킬이에요', 'invalid skill': '올릴 수 없는 스킬이에요', 'not done': '아직 끝나지 않았어요' };
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
  const ready = () => (st?.slots || []).some(s => s.pending > 0) || (st?.jobs || []).some(j => j.done || new Date(j.ends_at) <= Date.now());
  const RW = { gold: '💰', gem: '🔮', dust: '✨ 가루', soul: '🔥 혼' };
  const costAll = c => Object.entries(c || {}).filter(([, v]) => v).map(([k, v]) => `${RW[k] || k} ${fmt(v)}`).join(' · ') || '무료';
  const left = t => { const ms = new Date(t) - Date.now(); if (ms <= 0) return '완료'; const h = Math.floor(ms / 3600e3), m = Math.floor(ms % 3600e3 / 60000); return h ? `${h}시간 ${m}분` : `${m}분 ${Math.floor(ms % 60000 / 1000)}초`; };
  const FH = { 1: 2, 2: 4, 3: 8, 4: 12, 5: 24 };
  const SOUL = [1, 2, 3, 5, 8, 12, 12], GV = [1, 1.5, 2, 3, 4, 6, 6];   // phaseE_6 스킬 비용 (미리보기용, 최종 값은 서버)
  let enhCost = null;
  async function loadEnh() { if (enhCost) return enhCost; if (window.VRCamp?._enh) return (enhCost = window.VRCamp._enh);
    try { const { data } = await window.VRCloud.sb.from('gear_enhance_cost').select('*'); enhCost = Object.fromEntries((data || []).map(x => [x.plus, x])); } catch { enhCost = {}; } return enhCost; }
  const gearName = g => { const d = window.VRGear?._defs?.()?.[g?.def || g]; return d ? `${d.name}` : String(g?.def || g || '장비'); };
  const rawOwned = uid => (window.VRStory?.save?.owned || []).find(o => o.uid === uid) || owned.find(o => o.uid === uid) || {};
  const skillName = (id, k) => (window.TCG?.skillsOf?.(id) || [])[k - 1]?.name || `스킬 ${k}`;

  const thumbImg = (id, name) => `<img class="camp-th" src="${(window.cardThumb || (x => 'img/thumb/' + x + '.webp'))(id)}" alt="${esc(name)}" loading="lazy" onerror="this.style.visibility='hidden'">`;
  const RCL = ['n', 'r', 'hr', 'sr', 'ur', 'mr', 'lr'];
  const skCount = id => (window.TCG?.skillsOf?.(id) || []).length;
  // 내 인재 화면과 같은 타일 (story.css 의 story-grid · story-card)
  const tile = (c, attrs, lvTxt, extra = '') => `<div class="story-owned" ${attrs}><div class="story-card story-own-tile rar-${RCL[c.g]}"><div class="story-card-img">${thumbImg(c.id, c.name)}${extra}</div><div class="story-card-name">${esc(String(c.name).replace(/^\[EX\d+\] /, ''))}</div><div class="story-own-lv">${lvTxt}</div></div></div>`;
  const css = document.createElement('style');
  css.textContent = `
  #camp-ov{position:fixed;inset:0;z-index:9600;background:rgba(0,0,0,.72);display:flex;align-items:center;justify-content:center;padding:10px}
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
  .camp-sec{margin:12px 2px 6px;font-size:14px;font-weight:900;display:flex;align-items:center;gap:6px}.camp-sec small{font-weight:600;opacity:.7;font-size:11px}.camp-lvbox{display:flex;align-items:center;gap:8px;padding:10px;margin:2px 0 8px;border-radius:12px;background:rgba(245,158,11,.1);border:1px solid rgba(245,158,11,.4)}.camp-lvbox .grow{flex:1;min-width:0}.camp-lvbox small{display:block;font-size:11px;opacity:.85}.camp-lvbox button{padding:8px 10px;border-radius:10px;border:0;background:#f59e0b;color:#1a1200;font-weight:800;font-size:13px;white-space:nowrap}.camp-lvbox button:disabled{opacity:.45}.camp-lvn{font-size:20px;font-weight:900}.camp-th{width:46px;height:62px;flex:none;object-fit:cover;object-position:top;border-radius:8px;border:2px solid var(--cg,#9ca3af);background:#0003}.camp-grid{margin-top:4px}.camp-grid .story-owned{cursor:pointer}.camp-grid .story-skn{pointer-events:none}.camp-grid .camp-skl{position:absolute;left:4px;right:4px;bottom:4px;font-size:10px;font-weight:800;padding:2px 4px;border-radius:6px;background:rgba(0,0,0,.78);color:#e9d5ff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-align:center}.mp-navbtn{position:relative}.mp-navbtn [data-campdot]{font-style:normal}.mp-navbtn .camp-dot{position:absolute;top:6px;right:8px;width:10px;height:10px;border-radius:50%;background:#ef4444;box-shadow:0 0 0 2px #14111f}`;
  document.head.appendChild(css);

  function shell(title, sub) {
    let ov = document.getElementById('camp-ov');
    if (!ov) { ov = document.createElement('div'); ov.id = 'camp-ov'; document.body.appendChild(ov); ov.addEventListener('click', e => { if (e.target === ov && !ov.classList.contains('vr-in-page')) close(); });
      window.VRPages?.host?.('camp', '🏋️ 훈련소', ov, () => { clearInterval(tick); paint(); }); }   // 페이지 시스템 (마이페이지 등 페이지 위에 뜨고 확인창도 그 위). 실패하면 팝업 (z 9600 > 상단바 9050)
    ov.innerHTML = `<div id="camp-box" role="dialog" aria-label="훈련소"><div class="ch"><span>${title}</span><button class="cx" aria-label="닫기">×</button></div>${sub ? `<div class="csub">${sub}</div>` : ''}<div class="cbody"></div></div>`;
    ov.querySelector('.cx').onclick = close;
    return ov.querySelector('#camp-box');
  }
  function close() { document.getElementById('camp-ov')?.remove(); clearInterval(tick); paint(); }
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && document.getElementById('camp-ov')) close(); });

  async function load() { st = await rpc('camp_status'); try { const s = await window.VRStory?.summary?.(); owned = (s?.ok ? s.owned : []).map(meta); } catch { owned = []; } paint(); return st; }
  async function open() {
    if (window.VRUnlocks && !window.VRUnlocks.guard('camp')) return;
    const box = shell('🏋️ 훈련소'); box.querySelector('.cbody').innerHTML = '<div class="camp-empty">불러오는 중...</div>';
    try { await load(); } catch (e) { box.querySelector('.cbody').innerHTML = `<div class="camp-empty">${off ? '훈련소 준비 중이에요' : esc(errText(e))}</div>`; return; }
    if (await autoClaim()) return;
    draw();
  }
  // 넣어 둔 동안 쌓인 EXP 를 바로 반영 (열 때 + 열려 있는 동안 10분마다). 빼기를 기다리지 않아도 실제 레벨이 보임
  let auto = 0;
  async function autoClaim() {
    clearInterval(auto); auto = setInterval(async () => { if (!document.getElementById('camp-ov')) return clearInterval(auto);
      try { const r = await rpc('camp_status'); if (r?.slots?.some(s => s.pending > 0)) done(await rpc('camp_claim')); } catch {} }, 600000);
    if (!st?.slots?.some(s => s.uid && s.pending > 0)) return false;
    try { await done(await rpc('camp_claim')); return true; } catch { return false; }
  }

  function slotHTML(s, firstLocked) {
    if (!s.open) {
      const can = s.slot === firstLocked && st.level >= s.need_level;
      return `<div class="camp-slot locked"><span class="camp-no">🔒</span><div class="grow"><b>${s.slot}번 칸</b></div>
        <button class="go" data-unlock="${s.slot}" ${can ? '' : 'disabled'}>${st.level < s.need_level ? `Lv${s.need_level}` : costText(s.cost)}</button></div>`;
    }
    if (!s.uid) return `<div class="camp-slot"><span class="camp-no">${s.slot}</span><div class="grow"><b>비어 있어요</b></div><button class="go" data-put="${s.slot}">넣기</button></div>`;
    const c = meta(s.card || owned.find(o => o.uid === s.uid) || { id: '?' }), lv = c.level || 1, cap = capOf(c), need = lv * 100, pct = lv >= cap ? 100 : Math.min(100, (c.exp || 0) / need * 100);
    return `<div class="camp-slot ${s.pending > 0 ? 'ready' : ''}"><span style="--cg:${GC[c.g]};display:flex">${thumbImg(c.id, c.name)}</span><div class="grow"><span class="camp-g" style="background:${GC[c.g]}">${GS[c.g]}</span> <b>${esc(c.name)}</b> Lv${lv}
      <div class="camp-bar"><i style="width:${pct}%"></i></div>${s.pending > 0 ? `<small class="camp-pend">+${fmt(s.pending)} EXP</small>` : lv >= cap ? '<small>MAX</small>' : ''}</div>
      <button data-remove="${s.slot}">빼기</button></div>`;
  }

  function draw() {
    const box = shell('🏋️ 훈련소');
    const firstLocked = (st.slots.find(s => !s.open) || {}).slot, total = st.slots.reduce((a, s) => a + (s.pending || 0), 0);
    box.querySelector('.cbody').innerHTML = st.level < st.slots[0].need_level
      ? `<div class="camp-empty">🔒 Lv${st.slots[0].need_level}</div>`
      : lvBox() + '<div class="camp-sec">🏋️ 훈련</div>' + st.slots.map(s => slotHTML(s, firstLocked)).join('') + forgeHTML() + dojoHTML();
    const jd = (st.jobs || []).filter(j => j.done || new Date(j.ends_at) <= Date.now()).length;
    box.insertAdjacentHTML('beforeend', `<div class="camp-acts"><button class="go" data-all ${total || jd ? '' : 'disabled'}>🎁 모두 받기${total ? ` (+${fmt(total)} EXP)` : ''}${jd ? ` · 완료 ${jd}` : ''}</button></div>`);
    bindExtra(box);
    box.querySelectorAll('[data-put]').forEach(b => b.onclick = () => pick(+b.dataset.put));
    box.querySelectorAll('[data-remove]').forEach(b => b.onclick = async () => {
      if (!await (window.VRAsk ? window.VRAsk('빼면 지금까지 쌓인 EXP 를 받고 칸이 비어요. 뺄까요?') : confirm('뺄까요?'))) return;
      try { const r = await rpc('camp_remove', { p_slot: +b.dataset.remove }); done(r); } catch (e) { toast(errText(e)); } });
    box.querySelectorAll('[data-unlock]').forEach(b => b.onclick = async () => {
      const s = st.slots.find(x => x.slot === +b.dataset.unlock);
      if (!await (window.VRAsk ? window.VRAsk(`${costText(s.cost)}(으)로 ${s.slot}번 칸을 열까요?`) : confirm('열까요?'))) return;
      try { st = await rpc('camp_unlock', { p_slot: s.slot }); toast(`🔓 ${s.slot}번 칸을 열었어요`); if (s.cost?.gem) window.VRGem?.status?.(true); window.VRPlayer?.status?.(true); draw(); } catch (e) { toast(errText(e)); } });
    box.querySelector('[data-all]').onclick = async () => { try {
      if ((st.jobs || []).some(j => j.done || new Date(j.ends_at) <= Date.now())) { const r = await rpc('camp_job_claim', { p_job: null }); st = r; jobToast(r.got); }
      if (st.slots.some(s => s.pending > 0)) return done(await rpc('camp_claim')); done(st); } catch (e) { toast(errText(e)); } };
    clearInterval(tick); tick = setInterval(() => { if (!document.getElementById('camp-ov')) return clearInterval(tick);
      document.querySelectorAll('#camp-box [data-left]').forEach(el => { el.textContent = '⏳ ' + left(el.dataset.left); }); }, 1000);
    paint();
  }

  async function done(r) {
    st = r; const got = (r.got || []).filter(x => x.exp > 0);
    if (got.length) toast(`🏋️ EXP +${fmt(got.reduce((a, x) => a + x.exp, 0))}${got.some(x => x.level > x.from) ? ' · LEVEL UP!' : ''}`);
    try { const s = await window.VRStory?.summary?.(); owned = (s?.ok ? s.owned : owned).map(meta); } catch {}
    draw();
  }

  // ===== 훈련소 레벨 · 연마소 · 도장 =====
  function lvBox() {
    const n = st.next, can = n && st.level >= n.need_level;
    return `<div class="camp-lvbox"><span class="camp-lvn">Lv${st.camp_lv || 1}</span><div class="grow"><b>훈련소 레벨</b></div>
      ${n ? `<button data-lvup ${can ? '' : 'disabled'}>${can ? `⬆ ${costText(n.cost)}` : `Lv${n.need_level}`}</button>` : '<b>MAX</b>'}</div>`;
  }
  const jobOf = (k, slot = 1) => (st.jobs || []).find(j => j.kind === k && j.slot === slot);
  const jobState = j => { const fin = j.done || new Date(j.ends_at) <= Date.now(); return fin ? '<small class="camp-pend">완료!</small>' : `<small data-left="${esc(j.ends_at)}">⏳ ${left(j.ends_at)}</small>`; };
  function forgeHTML() {
    const need = st.forge_account_level ?? 20, lock = st.level < need, j = jobOf('forge');
    let row;
    if (lock) row = `<div class="camp-slot locked"><span class="camp-no">🔒</span><div class="grow"><b>연마소</b></div><button class="go" disabled>Lv${need}</button></div>`;
    else if (j) { const fin = j.done || new Date(j.ends_at) <= Date.now();
      row = `<div class="camp-slot ${fin ? 'ready' : ''}"><span class="camp-no">⚒️</span><div class="grow"><b>${esc(gearName(j.gear_def))} +${j.from} → +${j.from + 1}</b>${jobState(j)}</div>${fin ? `<button class="go" data-jclaim="${j.id}">받기</button>` : ''}</div>`; }
    else row = `<div class="camp-slot"><span class="camp-no">⚒️</span><div class="grow"><b>비어 있어요</b></div><button class="go" data-forge>넣기</button></div>`;
    return `<div class="camp-sec">⚒️ 연마소</div>${row}`;
  }
  function dojoHTML() {
    const need = st.dojo_account_level ?? 20, lock = st.level < need; let rows = '';
    if (lock) rows = `<div class="camp-slot locked"><span class="camp-no">🔒</span><div class="grow"><b>도장</b></div><button class="go" disabled>Lv${need}</button></div>`;
    else {
      for (let s = 1; s <= st.dojo_slots; s++) { const j = jobOf('dojo', s);
        if (j) { const fin = j.done || new Date(j.ends_at) <= Date.now(), c = meta(rawOwned(j.card_uid).id ? rawOwned(j.card_uid) : { id: j.card });
          rows += `<div class="camp-slot ${fin ? 'ready' : ''}"><span style="--cg:${GC[c.g]};display:flex">${thumbImg(c.id, c.name)}</span><div class="grow"><b>${esc(c.name)}</b><small>「${esc(skillName(c.id, j.skill))}」 Lv${j.from} → Lv${j.from + 1}</small>${jobState(j)}</div>${fin ? `<button class="go" data-jclaim="${j.id}">받기</button>` : ''}</div>`; }
        else rows += `<div class="camp-slot"><span class="camp-no">${s}</span><div class="grow"><b>비어 있어요</b></div><button class="go" data-dojo="${s}">넣기</button></div>`; }
      if (st.dojo_slots < 2) rows += `<div class="camp-slot locked"><span class="camp-no">🔒</span><div class="grow"><b>${st.dojo_slots ? '도장 2번 칸' : '도장'}</b></div><button class="go" data-dojounlock>🔮 ${fmt(st.dojo_next_cost)}</button></div>`;
    }
    return `<div class="camp-sec">🥋 도장</div>${rows}`;
  }
  const ask = async t => window.VRAsk ? window.VRAsk(t) : confirm(t);
  function jobToast(got) { (got || []).forEach(g => toast(g.kind === 'forge' ? `⚒️ 장비 +${g.level} 완료!` : `🥋 스킬 Lv${g.level} 완료!`)); if ((got || []).some(g => g.kind === 'forge')) window.VRGear?.load?.(true); }
  function bindExtra(box) {
    box.querySelector('[data-lvup]')?.addEventListener('click', async () => { const n = st.next; if (!await ask(`${costAll(n.cost)}(으)로 훈련소를 Lv${n.lv}로 올릴까요?`)) return;
      try { st = await rpc('camp_levelup'); toast(`🏋️ 훈련소 Lv${st.camp_lv}!`); if (n.cost.gem) window.VRGem?.status?.(true); window.VRPlayer?.status?.(true); done(st); } catch (e) { toast(errText(e)); } });
    box.querySelectorAll('[data-jclaim]').forEach(b => b.onclick = async () => { try { const r = await rpc('camp_job_claim', { p_job: +b.dataset.jclaim }); jobToast(r.got); done(r); } catch (e) { toast(errText(e)); } });
    box.querySelector('[data-forge]')?.addEventListener('click', pickGear);
    box.querySelectorAll('[data-dojo]').forEach(b => b.onclick = () => pickSkill(+b.dataset.dojo));
    box.querySelector('[data-dojounlock]')?.addEventListener('click', async () => { if (window.VRUnlocks && !window.VRUnlocks.guard('dojo')) return; if (!await ask(`🔮 ${fmt(st.dojo_next_cost)}로 도장 ${st.dojo_slots + 1}번 칸을 열까요?`)) return;
      try { st = await rpc('camp_dojo_unlock'); toast('🥋 도장을 열었어요'); window.VRGem?.status?.(true); draw(); } catch (e) { toast(errText(e)); } });
  }
  // 장비 고르기: +5 미만 장비, 반값 비용 미리보기 (최종 값은 서버)
  async function pickGear() {
    if (window.VRUnlocks && !window.VRUnlocks.guard('forge')) return;
    const box = shell('⚒️ 연마할 장비'); const body = box.querySelector('.cbody');
    body.innerHTML = '<div class="camp-empty">불러오는 중...</div>';
    const [ec] = await Promise.all([loadEnh(), window.VRGear?.load?.(true)]); const list = (window.VRGear?.myGear?.() || []).filter(g => g.plus < 5).sort((a, b) => b.plus - a.plus);
    const half = n => Math.ceil((n || 0) * 0.5);
    body.innerHTML = list.map(g => { const c = ec[g.plus + 1] || {}; return `<div class="camp-slot"><div class="grow"><b>${esc(gearName(g))} +${g.plus}</b><small>⏳ ${FH[g.plus + 1]}시간</small></div><button class="go" data-g="${g.id}">💰${fmt(half(c.gold))} ✨${fmt(half(c.dust))}</button></div>`; }).join('') || '<div class="camp-empty">연마할 장비가 없어요</div>';
    box.insertAdjacentHTML('beforeend', '<div class="camp-acts"><button data-back>뒤로</button></div>'); box.querySelector('[data-back]').onclick = draw;
    body.querySelectorAll('[data-g]').forEach(b => b.onclick = async () => { b.disabled = true;
      try { st = await rpc('camp_forge_start', { p_gear: +b.dataset.g }); toast('⚒️ 연마를 시작했어요'); window.VRPlayer?.status?.(true); window.VRGear?.load?.(true); draw(); } catch (e) { toast(errText(e)); b.disabled = false; } });
  }
  // 스킬 고르기: 액티브 스킬, Lv7 미만, 도장 중 아닌 것
  function pickSkill(slot) {
    if (window.VRUnlocks && !window.VRUnlocks.guard('dojo')) return;
    const busy = new Set((st.jobs || []).filter(j => j.kind === 'dojo').map(j => `${j.card_uid}:${j.skill}`)), rows = [];
    for (const o of owned) { const raw = rawOwned(o.uid), sl = raw.skillLv || {};
      (window.TCG?.skillsOf?.(o.id) || []).forEach((sk, i) => { const k = i + 1, lv = Math.max(1, sl[k] | 0 || 1);
        if (sk.mode !== 'active' || lv >= st.dojo_max || busy.has(`${o.uid}:${k}`)) return;
        rows.push({ o, k, lv, name: sk.name, gold: Math.ceil(GV[o.g] * lv * 100 * 0.5), soul: Math.ceil(SOUL[o.g] * Math.ceil(lv / 2) * 0.5) }); }); }
    rows.sort((a, b) => b.o.g - a.o.g || a.lv - b.lv);
    const box = shell(`🥋 도장 ${slot}번 칸`);
    box.querySelector('.cbody').innerHTML = rows.length ? `<div class="story-grid camp-grid">${rows.map(r => tile(r.o, `data-sk="${esc(r.o.uid)}:${r.k}"`, `Lv.${r.o.level || 1}`, `<span class="camp-skl">${esc(r.name)} Lv${r.lv}→${r.lv + 1}</span>`)).join('')}</div>` : '<div class="camp-empty">없음</div>';
    box.insertAdjacentHTML('beforeend', '<div class="camp-acts"><button data-back>뒤로</button></div>'); box.querySelector('[data-back]').onclick = draw;
    box.querySelectorAll('[data-sk]').forEach(b => b.onclick = async () => { const [u, k] = b.dataset.sk.split(':'), r = rows.find(x => x.o.uid === u && x.k === +k);
      if (!await ask(`「${r.name}」 Lv${r.lv} → Lv${r.lv + 1} · ${r.lv * 4}시간\n🔥 혼 ${fmt(r.soul)} · 💰 ${fmt(r.gold)}`)) return;
      try { st = await rpc('camp_dojo_start', { p_slot: slot, p_uid: u, p_skill: +k }); toast('🥋 수련을 시작했어요'); window.VRPlayer?.status?.(true); draw(); } catch (e) { toast(errText(e)); } });
  }

  // 인재 고르기 (내 인재 화면과 같은 썸네일 그리드): 훈련 중·최대 레벨 인재 제외, 레벨 낮은 순. 비용 없음
  function pick(slot) {
    const busy = new Set(st.slots.map(s => s.uid).filter(Boolean));
    const pool = owned.filter(c => !busy.has(c.uid) && (c.level || 1) < capOf(c)).sort((a, b) => (a.level || 1) - (b.level || 1) || b.g - a.g);
    const box = shell(`🏋️ ${slot}번 칸`);
    box.querySelector('.cbody').innerHTML = pool.length ? `<div class="story-grid camp-grid">${pool.map((c, i) => { const n = skCount(c.id), sl = rawOwned(c.uid).skillLv || {}, mx = Math.max(1, ...Object.values(sl).map(v => v | 0));
      return tile(c, `data-u="${esc(c.uid)}" ${i === 0 ? 'data-recommended' : ''}`, `Lv.${c.level || 1}`, (i === 0 ? '<span class="camp-rec">추천</span>' : '') + (n ? `<span class="story-skn">✦${n}${mx > 1 ? ` Lv${mx}` : ''}</span>` : '')); }).join('')}</div>` : '<div class="camp-empty">없음</div>';
    box.insertAdjacentHTML('beforeend', '<div class="camp-acts"><button data-back>뒤로</button></div>');
    box.querySelector('[data-back]').onclick = draw;
    box.querySelectorAll('[data-u]').forEach(b => b.onclick = async () => { if (b.dataset.busy) return; b.dataset.busy = 1;
      try { st = await rpc('camp_put', { p_slot: slot, p_uid: b.dataset.u }); toast('🏋️ 훈련을 시작했어요'); draw(); } catch (e) { toast(errText(e)); delete b.dataset.busy; } });
  }

  // 마이페이지 버튼 빨간 점
  function paint() { document.querySelectorAll('[data-campdot]').forEach(el => { el.innerHTML = ready() ? '<i class="camp-dot" aria-label="받을 EXP 있음"></i>' : ''; }); }
  async function refresh() { if (off || (!window.VRCloud?.user && !window.VRCamp?._mock)) return paint(); try { st = await rpc('camp_status'); } catch {} paint(); }
  window.addEventListener('vr:user', () => setTimeout(refresh, 2000));
  setInterval(refresh, 10 * 60e3);
  new MutationObserver(() => { if (document.querySelector('[data-campdot]:empty') && ready()) paint(); }).observe(document.body, { childList: true, subtree: true });
  window.VRCamp = { open, close, refresh, ready, get off() { return off; }, _set: (s, o) => { st = s; owned = o.map(meta); paint(); }, _draw: () => draw(), _pick: s => pick(s) };
})();
