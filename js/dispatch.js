// ===== 파견: 배척지 001~009 · 안전지대 B~SS (서버: supabase/dispatch.sql) =====
// 버튼 [data-dispatchbtn] (메인 상단) · 끝난 파견 수 뱃지. 시간·보상·확률은 전부 서버가 정함 (화면은 보여주기만)
(() => {
  const G = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE'];
  const GS = ['N', 'R', 'HR', 'SR', 'UR', 'MR', 'LR'], GC = ['#9ca3af', '#22c55e', '#3b82f6', '#a855f7', '#f59e0b', '#ef4444', '#ef4444'];
  const EL = { WIND: '🍃 바람', FIRE: '🔥 불', ICE: '❄️ 얼음', DARK: '🌑 어둠', LIGHT: '☀️ 빛' };
  const RW = { gold: '💰 골드', blood: '🩸 순수한 피', shard: '🔹 이상한 조각', soul: '🔥 각성자의 혼', gem: '🔮 심연석', tickets: '🎫 소환권', drink: '🥤 드링크' };
  const HOURS = [1, 4, 8, 12];
  const ERR = { 'slots full': '파견 슬롯이 꽉 찼어요', 'daily cap': '오늘 파견 횟수(12번)를 다 썼어요', busy: '이미 파견 중인 인재가 있어요', 'need grade': '필수 등급을 채우지 못했어요', 'banned grade': 'MR·LR 인재는 아직 파견할 수 없어요', 'not owned': '보유하지 않은 인재예요', taken: '이미 보낸 의뢰예요', 'no offer': '의뢰가 바뀌었어요. 다시 열어 주세요', 'not enough gem': '심연석이 부족해요', 'nothing to claim': '받을 보상이 없어요', 'bad cards': '인원 수가 맞지 않아요' };
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const errText = e => { const m = e?.message || String(e); for (const k in ERR) if (m.includes(k)) return ERR[k]; return '⚠️ ' + m; };
  const toast = t => { const el = document.createElement('div'); el.className = 'gem-toast'; el.textContent = t; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); };
  let st = null, owned = [], off = false, hours = +(localStorage.getItem('vr:dsp_h') || 8), tick = 0;

  async function rpc(name, args) {
    const c = window.VRCloud, sb = c?.sb; if (!sb || !c?.user) throw new Error('login required');
    const { data, error } = await sb.rpc(name, args);
    if (error) { if (/function .* does not exist|Could not find the function/i.test(error.message || '')) off = true; throw error; }
    return data;
  }
  const zone = id => st?.zones?.find(z => z.id === id);
  const busy = () => new Set((st?.runs || []).flatMap(r => r.uids));
  const meta = o => { const c = window.TCG?.cardById?.(o.id) || {}; return { ...o, g: Math.max(0, G.indexOf(c.grade || o.grade)), el: c.class, cls: c.attribute, name: o.name || c.name || o.id }; };
  const rwText = (rw, f = 1) => Object.entries(rw || {}).map(([k, v]) => { const n = v * f; return `${RW[k] || k} ${n >= 1 ? '~' + Math.round(n) : Math.round(n * 100) + '%'}`; }).join(' · ');
  const left = t => { const ms = new Date(t) - Date.now(); if (ms <= 0) return '완료'; const h = Math.floor(ms / 3600e3), m = Math.floor(ms % 3600e3 / 60000), s = Math.floor(ms % 60000 / 1000); return h ? `${h}시간 ${m}분` : `${m}분 ${s}초`; };
  // 보너스: 속성·클래스 맞는 카드 1장당 +15% (최대 60) + 필수보다 높은 등급 +10
  const bonusOf = (cards, o, z) => { const n = cards.filter(c => c.el === o.el).length + cards.filter(c => c.cls === o.cls).length, mx = Math.max(-1, ...cards.map(c => c.g)); return Math.min(60, 15 * n) + (mx > z.min_grade ? 10 : 0); };

  const css = document.createElement('style');
  css.textContent = `
  #dsp-ov{position:fixed;inset:0;z-index:8800;background:rgba(0,0,0,.72);display:flex;align-items:center;justify-content:center;padding:10px}
  #dsp-box{width:100%;max-width:480px;max-height:92vh;display:flex;flex-direction:column;background:linear-gradient(#1e1530,#0e0a18);border:1px solid rgba(251,191,36,.45);border-radius:16px;color:#fde68a;box-shadow:0 10px 40px rgba(0,0,0,.6)}
  #dsp-box .dh{display:flex;justify-content:space-between;align-items:center;padding:12px 14px 4px;font-weight:800;font-size:18px}
  #dsp-box .dx{background:none;border:0;color:#fde68a;font-size:22px;cursor:pointer}
  #dsp-box .dsub{padding:0 14px 6px;font-size:11px;opacity:.8}
  #dsp-box .dbody{overflow:auto;padding:0 10px 8px;flex:1}
  #dsp-box h4{margin:10px 4px 6px;font-size:13px;opacity:.9}
  .dsp-run,.dsp-off{display:flex;align-items:center;gap:8px;padding:9px 10px;margin-bottom:6px;border-radius:12px;background:rgba(0,0,0,.32);border:1px solid rgba(251,191,36,.18);color:#fef3c7}
  .dsp-off{cursor:pointer;flex-wrap:wrap}.dsp-off.taken{opacity:.4;cursor:default}
  .dsp-off.safe{border-color:rgba(34,197,94,.3)}
  .dsp-zn{font-weight:800;font-size:14px;min-width:92px}
  .dsp-g{display:inline-block;padding:1px 6px;border-radius:6px;font-size:11px;font-weight:800;color:#111}
  .dsp-tag{font-size:11px;padding:1px 6px;border-radius:6px;background:rgba(255,255,255,.08)}
  .dsp-rw{flex-basis:100%;font-size:11px;opacity:.8}
  .dsp-run .grow{flex:1;min-width:0}.dsp-run small{display:block;font-size:11px;opacity:.8;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .dsp-run button,.dsp-acts button,.dsp-h button,.dsp-pk-acts button{padding:8px 10px;border-radius:10px;border:1px solid rgba(251,191,36,.35);background:rgba(0,0,0,.3);color:#fde68a;font-weight:700;cursor:pointer;font-size:13px;white-space:nowrap}
  .dsp-run button.go,.dsp-acts button.go,.dsp-pk-acts button.go,.dsp-h button.on{background:#f59e0b;color:#1a1200}
  .dsp-run.done{border-color:#22c55e}
  .dsp-acts{display:flex;gap:6px;padding:8px 10px 12px;border-top:1px solid rgba(255,255,255,.08)}.dsp-acts button{flex:1;padding:10px 4px;font-size:13px}
  .dsp-acts button:disabled,.dsp-pk-acts button:disabled{opacity:.45}
  .dsp-h{display:flex;gap:6px;padding:4px 10px 0}.dsp-h button{flex:1;padding:7px 2px}
  .dsp-empty{padding:12px;text-align:center;opacity:.7;font-size:12px}
  .dsp-pk-list{display:grid;grid-template-columns:repeat(auto-fill,minmax(96px,1fr));gap:6px}
  .dsp-card{padding:7px 6px;border-radius:10px;background:rgba(0,0,0,.35);border:2px solid transparent;color:#fef3c7;font-size:12px;text-align:left;cursor:pointer;line-height:1.35}
  .dsp-card.on{border-color:#f59e0b;background:rgba(245,158,11,.18)}.dsp-card.hit{box-shadow:inset 0 0 0 1px #22c55e}
  .dsp-card b{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .dsp-need{font-size:12px;padding:6px 4px;line-height:1.5}.dsp-need .ok{color:#86efac}.dsp-need .no{color:#fca5a5}
  .dsp-pk-acts{display:flex;gap:6px;padding:8px 10px 12px}.dsp-pk-acts button{flex:1;padding:10px}
  .dsp-prev{font-size:12px;line-height:1.5}.dsp-prev div{padding:6px 4px;border-bottom:1px solid rgba(255,255,255,.06)}`;
  document.head.appendChild(css);

  function shell(title, sub) {
    let ov = document.getElementById('dsp-ov');
    if (!ov) { ov = document.createElement('div'); ov.id = 'dsp-ov'; document.body.appendChild(ov); ov.addEventListener('click', e => { if (e.target === ov && !ov.classList.contains('vr-in-page')) close(); });
      window.VRPages?.host?.('dispatch', '🧭 파견', ov, () => { clearInterval(tick); paint(); }); }   // 페이지 시스템 (실패하면 예전 팝업 그대로)
    ov.innerHTML = `<div id="dsp-box" role="dialog" aria-label="파견"><div class="dh"><span>${title}</span><button class="dx" aria-label="닫기">×</button></div><div class="dsub">${sub || ''}</div><div class="dbody"></div></div>`;
    ov.querySelector('.dx').onclick = close;
    return ov.querySelector('#dsp-box');
  }
  function close() { document.getElementById('dsp-ov')?.remove(); clearInterval(tick); paint(); }
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && document.getElementById('dsp-ov')) close(); });

  const gBadge = g => `<span class="dsp-g" style="background:${GC[g]}">${GS[g]}↑</span>`;
  const offHTML = o => { const z = zone(o.zone); if (!z) return ''; return `<div class="dsp-off ${z.grp} ${o.taken ? 'taken' : ''}" data-slot="${o.slot}"><span class="dsp-zn">${esc(z.name)}</span>${gBadge(z.min_grade)}<span class="dsp-tag">👥${z.size}</span><span class="dsp-tag">${EL[o.el] || o.el}</span><span class="dsp-tag">${esc(o.cls)}</span>${o.taken ? '<span class="dsp-tag">보냄</span>' : ''}<div class="dsp-rw">${hours}시간: ${rwText(z.rw, st.mult[hours])}</div></div>`; };
  const runHTML = r => { const z = zone(r.zone) || { name: r.zone }; const names = r.uids.map(u => owned.find(o => o.uid === u)?.name || '?').join(', ');
    return `<div class="dsp-run ${r.done ? 'done' : ''}"><div class="grow"><b>${esc(z.name)}</b> <span class="dsp-tag">${r.hours}h</span>${r.bonus ? ` <span class="dsp-tag">+${r.bonus}%</span>` : ''}<small>${esc(names)}</small>
      <small data-left="${r.ends_at}">${r.done ? `🎁 ${r.great ? '대성공! ' : ''}${Object.entries(r.reward || {}).map(([k, v]) => `${RW[k] || k} ${v}`).join(' · ')}` : '⏳ ' + left(r.ends_at)}</small></div>
      ${r.done ? `<button class="go" data-claim="${r.id}">받기</button>` : `<button data-recall="${r.id}">귀환</button>`}</div>`; };

  async function load() { st = await rpc('dispatch_status'); try { const s = await window.VRStory?.summary?.(); owned = (s?.ok ? s.owned : []).map(meta); } catch { owned = []; } return st; }

  async function open() {
    const box = shell('🧭 파견'); box.querySelector('.dbody').innerHTML = '<div class="dsp-empty">불러오는 중...</div>';
    try { await load(); } catch (e) { box.querySelector('.dbody').innerHTML = `<div class="dsp-empty">${off ? '파견 준비 중이에요' : esc(errText(e))}</div>`; return; }
    draw();
  }
  function draw() {
    const box = shell('🧭 파견', `오늘 ${st.starts}/${st.cap}회 · 슬롯 ${st.runs.length}/${st.slots} · 매일 0시(한국 시간) 의뢰 교체`);
    const free = Math.max(0, st.free - st.refreshes), done = st.runs.filter(r => r.done).length;
    box.querySelector('.dbody').innerHTML = `<h4>진행 중 (${st.runs.length}/${st.slots})</h4>${st.runs.map(runHTML).join('') || '<div class="dsp-empty">보낸 파견이 없어요</div>'}
      <h4>오늘의 의뢰</h4><div class="dsp-h">${HOURS.map(h => `<button data-h="${h}" class="${h === hours ? 'on' : ''}">${h}시간</button>`).join('')}</div><div style="height:6px"></div>
      ${st.offers.map(offHTML).join('')}
      <div class="dsp-empty">필수: 등급(보낸 인재 중 1명 이상) · 속성·클래스가 맞는 인재 1명당 +15% (최대 60%) · 필수보다 높은 등급 +10% · 보너스 최대면 10% 확률 대성공(2배)</div>`;
    box.insertAdjacentHTML('beforeend', `<div class="dsp-acts"><button data-auto ${st.runs.length >= st.slots || st.starts >= st.cap ? 'disabled' : ''}>🤖 자동 보내기</button><button class="go" data-all ${done ? '' : 'disabled'}>🎁 모두 받기${done ? ` (${done})` : ''}</button><button data-ref>🔄 새로고침<br><small>${free ? `무료 ${free}/${st.free}` : `🔮${st.refresh_cost}`}</small></button></div>`);
    box.querySelectorAll('[data-h]').forEach(b => b.onclick = () => { hours = +b.dataset.h; localStorage.setItem('vr:dsp_h', hours); draw(); });
    box.querySelectorAll('.dsp-off:not(.taken)').forEach(b => b.onclick = () => pick(st.offers.find(o => o.slot === +b.dataset.slot)));
    box.querySelectorAll('[data-claim]').forEach(b => b.onclick = () => claim(+b.dataset.claim));
    box.querySelectorAll('[data-recall]').forEach(b => b.onclick = async () => { if (!await window.VRAsk('지금 부르면 보상 없이 돌아와요. 귀환할까요?')) return; try { st = await rpc('dispatch_recall', { p_run: +b.dataset.recall }); draw(); } catch (e) { toast(errText(e)); } });
    box.querySelector('[data-all]').onclick = () => claim(null);
    box.querySelector('[data-auto]').onclick = auto;
    box.querySelector('[data-ref]').onclick = async () => {
      if (st.refresh_cost > 0 && !await window.VRAsk(`심연석 ${st.refresh_cost}개로 의뢰를 새로고침할까요? (보낸 의뢰는 그대로)`)) return;
      try { st = await rpc('dispatch_refresh'); if (st.spent) window.VRGem?.status?.(true); draw(); } catch (e) { toast(errText(e)); }
    };
    clearInterval(tick); tick = setInterval(() => { if (!document.getElementById('dsp-ov')) return clearInterval(tick);
      let fin = false; document.querySelectorAll('#dsp-box [data-left]').forEach(el => { const t = el.dataset.left; if (el.textContent.startsWith('⏳')) { const l = left(t); el.textContent = '⏳ ' + l; if (l === '완료') fin = true; } });
      if (fin) load().then(draw).catch(() => {}); }, 1000);
  }

  async function claim(id) {
    try { const r = await rpc('dispatch_claim', { p_run: id }); st = r;
      toast(`🎁 ${Object.entries(r.got || {}).map(([k, v]) => `${RW[k] || k} ${v}`).join(' · ') || '받았어요'}`);
      if (r.wallet) window.VRPlayer?.setWallet?.(r.wallet); if (r.got?.gem) window.VRGem?.status?.(true); window.VRPlayer?.status?.(true);
      draw(); } catch (e) { toast(errText(e)); }
  }

  // 인재 고르기: 보낼 수 있는 인재(파견 중·MR 이상 제외), 조건 맞는 인재 위로
  function pick(o) {
    const z = zone(o.zone), bz = busy(); let sel = [];
    const pool = owned.filter(c => !bz.has(c.uid) && c.g <= 4).sort((a, b) => ((b.el === o.el) + (b.cls === o.cls)) - ((a.el === o.el) + (a.cls === o.cls)) || a.g - b.g);
    const box = shell(`${esc(z.name)} <span style="font-size:12px">${gBadge(z.min_grade)}</span>`, `최대 ${z.size}명 · ${EL[o.el] || o.el} · ${esc(o.cls)} · ${hours}시간`);
    const body = box.querySelector('.dbody');
    const paintP = () => {
      const cards = sel.map(u => pool.find(c => c.uid === u)), ok = cards.some(c => c.g >= z.min_grade), b = bonusOf(cards, o, z);
      body.innerHTML = `<div class="dsp-need"><span class="${ok ? 'ok' : 'no'}">${ok ? '✔' : '✖'} 필수: ${GS[z.min_grade]} 이상 1명</span> · 보너스 +${b}%<br>예상: ${rwText(z.rw, st.mult[hours] * (1 + b / 100))}</div>
        <div class="dsp-pk-list">${pool.map(c => `<button class="dsp-card ${sel.includes(c.uid) ? 'on' : ''} ${c.el === o.el || c.cls === o.cls ? 'hit' : ''}" data-u="${esc(c.uid)}"><span class="dsp-g" style="background:${GC[c.g]}">${GS[c.g]}</span> Lv${c.level || 1}<b>${esc(c.name)}</b><span style="font-size:10px;opacity:.85">${EL[c.el] || ''} · ${esc(c.cls || '')}</span></button>`).join('') || '<div class="dsp-empty">보낼 수 있는 인재가 없어요</div>'}</div>`;
      body.querySelectorAll('[data-u]').forEach(btn => btn.onclick = () => { const u = btn.dataset.u; sel = sel.includes(u) ? sel.filter(x => x !== u) : sel.length < z.size ? [...sel, u] : sel; paintP(); });
      go.disabled = !ok;
    };
    box.insertAdjacentHTML('beforeend', `<div class="dsp-pk-acts"><button data-back>뒤로</button><button class="go" data-go>🧭 보내기</button></div>`);
    const go = box.querySelector('[data-go]');
    box.querySelector('[data-back]').onclick = draw;
    go.onclick = async () => { go.disabled = true; try { st = await rpc('dispatch_start', { p_slot: o.slot, p_uids: sel, p_hours: hours }); toast(`🧭 ${z.name}(으)로 보냈어요`); draw(); } catch (e) { toast(errText(e)); go.disabled = false; } };
    paintP();
  }

  // 자동: 의뢰마다 필수 등급을 겨우 넘는 가장 낮은 인재 1명 + 보너스 맞는 인재(낮은 등급부터)로 채움
  function plan() {
    const used = busy(), out = []; let room = Math.min(st.slots - st.runs.length, st.cap - st.starts);
    for (const o of st.offers) {
      if (room <= 0) break; if (o.taken) continue; const z = zone(o.zone); if (!z) continue;
      const free = owned.filter(c => !used.has(c.uid) && c.g <= 4), hit = c => (c.el === o.el) + (c.cls === o.cls);
      const key = free.filter(c => c.g >= z.min_grade).sort((a, b) => a.g - b.g || hit(b) - hit(a))[0]; if (!key) continue;
      const rest = free.filter(c => c !== key && hit(c) > 0).sort((a, b) => hit(b) - hit(a) || a.g - b.g).slice(0, z.size - 1);
      const team = [key, ...rest]; team.forEach(c => used.add(c.uid)); out.push({ o, z, team, bonus: bonusOf(team, o, z) }); room--;
    }
    return out;
  }
  function auto() {
    const p = plan(); if (!p.length) return toast('보낼 수 있는 의뢰·인재가 없어요');
    const box = shell('🤖 자동 보내기 미리보기', `${hours}시간 · ${p.length}건`);
    box.querySelector('.dbody').innerHTML = `<div class="dsp-prev">${p.map(x => `<div><b>${esc(x.z.name)}</b> ${gBadge(x.z.min_grade)} +${x.bonus}%<br>${x.team.map(c => `<span class="dsp-g" style="background:${GC[c.g]}">${GS[c.g]}</span> ${esc(c.name)}`).join(', ')}<br><small style="opacity:.8">${rwText(x.z.rw, st.mult[hours] * (1 + x.bonus / 100))}</small></div>`).join('')}</div>`;
    box.insertAdjacentHTML('beforeend', `<div class="dsp-pk-acts"><button data-back>취소</button><button class="go" data-go>🧭 모두 보내기</button></div>`);
    box.querySelector('[data-back]').onclick = draw;
    const go = box.querySelector('[data-go]');
    go.onclick = async () => { go.disabled = true; let n = 0;
      for (const x of p) { try { st = await rpc('dispatch_start', { p_slot: x.o.slot, p_uids: x.team.map(c => c.uid), p_hours: hours }); n++; } catch (e) { toast(errText(e)); break; } }
      if (n) toast(`🧭 ${n}건 보냈어요`); draw(); };
  }

  // 메인 상단 버튼 + 끝난 파견 뱃지
  function paint() {
    for (const w of document.querySelectorAll('[data-dispatchbtn]')) {
      if (off || !window.VRCloud?.user) { w.innerHTML = ''; continue; }
      if (!w.querySelector('.dsp-btn')) { w.innerHTML = '<button class="story-mailbtn dsp-btn" type="button" aria-label="파견" title="파견">🧭<span>파견</span></button>'; w.firstChild.onclick = open; }
      const b = w.firstChild; b.querySelector('.story-badge')?.remove();
      const k = (st?.runs || []).filter(r => r.done || new Date(r.ends_at) <= Date.now()).length;
      if (k > 0) b.insertAdjacentHTML('beforeend', `<i class="story-badge">${k}</i>`);
    }
  }
  async function refreshBadge() { if (off || !window.VRCloud?.user) return paint(); try { st = await rpc('dispatch_status'); } catch {} paint(); }
  window.addEventListener('vr:user', () => setTimeout(refreshBadge, 1500));
  setInterval(paint, 30000);
  new MutationObserver(() => { if (document.querySelector('[data-dispatchbtn]:empty')) paint(); }).observe(document.body, { childList: true, subtree: true });
  window.VRDispatch = { open, close, plan: () => st && plan(), _set: (s, o) => { st = s; owned = o.map(meta); }, _draw: () => draw(), _auto: () => auto(), _pick: s => pick(st.offers.find(o => o.slot === s)) };
})();
