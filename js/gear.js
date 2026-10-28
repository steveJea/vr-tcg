// ===== 장비 (PR2: 화면) — supabase/gear_v1.sql 의 gear_status / gear_equip / gear_unequip / gear_lock / gear_expand 사용 =====
// 인재 정보에 2×2 칸(무기·방어구·액세서리·증표). 증표 칸은 SR 이상만. 가방(100~200칸). 팝업은 바깥 누르면 닫힘
// 아이콘: img/gear/{weapon|armor|accessory}_{tier}_{n}.webp, 없으면 {slot}_0_1 실루엣. 증표: sigil_1_1~3, 없으면 sigil_0_1
(() => {
  const SLOTS = [['weapon', '무기'], ['armor', '방어구'], ['acc', '액세서리']];
  const TIER = ['', '낡은', '일반', '고급', '희귀', '영웅', '전설', '심연'];
  const STAT = { atk: '공격력', hp: '체력', def: '방어력', crit: '치명타', evade: '회피', mp: '시작 MP' };
  const OPT = { crit_dmg: '치명 피해', elem_dmg: '속성 피해', crit: '치명타', dmg_reduce: '피해 감소', debuff_resist: '디버프 저항', evade: '회피', mp_regen: 'MP 회복', kill_mp: '처치 시 MP', cooldown: '쿨타임' };
  const SIGIL_ICON = { '1000100007': 'sigil_1_1', '2000400088': 'sigil_1_2', '2000100001': 'sigil_1_3' };
  const SR_UP = ['SUPER RARE', 'ULTRA RARE', 'MYTHIC RARE', 'LEGENDARY RARE'];
  const file = s => s === 'acc' ? 'accessory' : s;
  const iconOf = d => d ? `img/gear/${file(d.slot)}_${d.tier}_${d.id.split('_')[2]}.webp` : '';
  const sil = s => `img/gear/${s === 'sigil' ? 'sigil' : file(s)}_0_1.webp`;
  const img = (src, slot, cls = '') => `<img class="${cls}" src="${src || sil(slot)}" alt="" loading="lazy" onerror="this.onerror=null;this.src='${sil(slot)}'">`;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const sb = () => window.VRCloud?.sb;
  let st = null, defs = null, sigils = null, off = false;

  async function load(force) {
    if (off || !sb() || !window.VRCloud?.user) return null;
    if (st && !force) return st;
    try {
      if (!defs) {
        const [a, b] = await Promise.all([sb().from('gear_defs').select('*'), sb().from('sigil_defs').select('*')]);
        if (a.error) throw a.error;
        defs = Object.fromEntries((a.data || []).map(d => [d.id, d])); sigils = Object.fromEntries((b.data || []).map(d => [d.card_id, d]));
      }
      const { data, error } = await sb().rpc('gear_status'); if (error) throw error;
      st = data; return st;
    } catch (e) { if (/PGRST20[25]|42883|42P01|does not exist|Could not find/i.test(`${e?.code} ${e?.message}`)) off = true; console.warn('[gear]', e?.message); return null; }
  }
  const mine = cardId => (st?.gear || []).filter(g => g.card === String(cardId));
  const slotOf = g => g.def.split('_')[0];
  const mainTxt = d => `${STAT[d.main_stat] || d.main_stat} +${+d.main_pct}%`;
  const toast = m => (window.VRGem?.toast || window.alert)(m);

  function pop(html, cls = '') {
    const m = document.createElement('div'); m.className = 'gear-pop-bg';
    m.innerHTML = `<div class="gear-pop ${cls}">${html}</div>`;
    let down = false;
    m.onpointerdown = e => { down = e.target === m; };
    m.onclick = e => { if (down && e.target === m) m.remove(); down = false; };   // 바깥 누르면 닫힘
    document.body.appendChild(m); return m;
  }
  async function rpc(fn, args) {
    const { data, error } = await sb().rpc(fn, args);
    if (error) { toast(`⚠️ ${error.message}`); return null; }
    if (data && data.ok === false) { toast(`⚠️ ${({ 'card not owned': '이 인재가 서버에 아직 없어요', gem: `보석이 부족해요 (${data.need})`, max: '가방이 최대예요', 'not found': '장비를 찾을 수 없어요' })[data.reason] || data.reason}`); return null; }
    await load(true); return data || {};
  }

  // 인재 정보의 4칸
  function slotsHTML(cardId, grade) {
    if (!st) return '';
    const eq = mine(cardId), sr = SR_UP.includes(grade);
    const t = (slot, label, g) => { const d = g && defs[g.def]; return `<button class="gear-slot ${d ? 'gt' + d.tier : 'empty'}" data-gslot="${slot}" title="${esc(d ? d.name : label)}">${img(d && iconOf(d), slot)}${g?.plus ? `<i>+${g.plus}</i>` : ''}<span>${esc(d ? d.name : label)}</span></button>`; };
    const sg = sr && sigils[cardId], own = (st.sigils || []).find(s => s.card === String(cardId));
    const sigTile = sr ? `<button class="gear-slot sigil ${own?.plus != null ? 'on' : 'empty'}" data-gslot="sigil" title="증표">${img(sg && own?.plus != null ? `img/gear/${SIGIL_ICON[cardId]}.webp` : '', 'sigil')}${own?.plus != null ? `<i>+${own.plus}</i>` : ''}<span>${sg ? esc(sg.name) : '증표'}</span></button>` : '';
    return `<div class="gear-slots ${sr ? 'four' : 'three'}">${SLOTS.map(([s, l]) => t(s, l, eq.find(g => slotOf(g) === s))).join('')}${sigTile}</div>`;
  }
  function bind(root, cardId, grade, reopen) {
    root.querySelectorAll('[data-gslot]').forEach(b => b.onclick = e => { e.stopPropagation(); const s = b.dataset.gslot;
      if (s === 'sigil') return sigilPop(cardId);
      const cur = mine(cardId).find(g => slotOf(g) === s);
      cur ? itemPop(cur, { cardId, reopen }) : bag({ slot: s, cardId, reopen }); });
  }

  // 증표: 지금은 보기만 (제작·강화는 다음 PR)
  function sigilPop(cardId) {
    const sg = sigils[cardId], own = (st.sigils || []).find(s => s.card === String(cardId));
    if (!sg) return pop(`<div class="gear-big">${img('', 'sigil')}</div><b>증표</b><p class="gear-dim">이 인재의 증표는 아직 준비 중이에요</p>`);
    const cur = own?.plus ?? null, step = (sg.steps || [])[cur ?? 0];
    pop(`<div class="gear-big">${img(`img/gear/${SIGIL_ICON[cardId]}.webp`, 'sigil', cur == null ? 'dim' : '')}</div><b>${esc(sg.name)}</b> ${cur != null ? `<span class="gear-plus">+${cur}</span>` : ''}
      <div class="gear-sig">${sigTxt(step)}</div>${cur != null && sg.steps[cur + 1] ? `<div class="gear-sig next"><small>다음 +${cur + 1}</small>${sigTxt(sg.steps[cur + 1])}</div>` : ''}
      <p class="gear-dim">조각 ${own?.frags || 0}${cur == null ? ' / 50 · 모으면 증표를 만들 수 있어요' : ''}</p>`);
  }

  const MOD = { hit_pct: v => `타격 ${v}%`, hits: v => `${v}회`, bleed_pct: v => `출혈 ${v}%`, cooldown: v => `쿨타임 ${v}`, mp: v => `MP ${v}`, fallback_hp_pct: v => `대체 대상 HP -${v}%`, targets: v => `대상 ${v}명`, duration: v => `${v}턴`,
    vs_bleed_dmg_pct: v => `출혈 대상 피해 +${v}%`, on_kill_extra_hits: v => `처치 시 추가 ${v}회`, bleed_dmg_pct: v => `출혈 피해 ${v}%`, hp_pct: v => `HP -${v.join('%·')}%`, cap: v => `상한 ${v.join('·')}`, cc_pct: v => `혼란·교란 ${v}%`, cc_then_bleed: () => '혼란 뒤 출혈' };
  const modTxt = o => Object.entries(o).filter(([k]) => MOD[k]).map(([k, v]) => MOD[k](v)).join(' · ');
  const sigTxt = s => !s ? '' : ['a', 'b', 'also', null].map(k => { const o = k ? s[k] : s; if (!o) return ''; const t = modTxt(o); return t ? `<div>${o.skill ? `<b>${esc(o.skill)}</b> ` : ''}${t}</div>` : ''; }).join('');

  // 장비 상세
  function itemPop(g, ctx = {}) {
    const d = defs[g.def], slot = slotOf(g);
    const m = pop(`<div class="gear-big gt${d.tier}">${img(iconOf(d), slot)}</div>
      <div class="gear-name gt${d.tier}"><small>${TIER[d.tier]}</small> ${esc(d.name)}${g.plus ? ` <span class="gear-plus">+${g.plus}</span>` : ''}</div>
      <div class="gear-main">${mainTxt(d)}</div>
      ${(g.opts || []).map(o => `<div class="gear-opt">${esc(OPT[o.opt] || o.opt)} +${o.v}${o.opt === 'cooldown' ? '' : '%'}</div>`).join('')}
      <div class="gear-acts">
        ${ctx.cardId && g.card !== String(ctx.cardId) ? '<button data-a="equip" class="gear-btn main">장착</button>' : ''}
        ${g.card ? '<button data-a="unequip" class="gear-btn">해제</button>' : ''}
        ${ctx.cardId && g.card === String(ctx.cardId) ? '<button data-a="swap" class="gear-btn">바꾸기</button>' : ''}
        <button data-a="lock" class="gear-btn">${g.locked ? '🔓 잠금 해제' : '🔒 잠금'}</button></div>`, 'item');
    const done = () => { m.remove(); ctx.reopen?.(); ctx.back?.(); };
    m.querySelectorAll('[data-a]').forEach(b => b.onclick = async () => { b.disabled = true; const a = b.dataset.a;
      if (a === 'swap') { m.remove(); return bag({ slot, cardId: ctx.cardId, reopen: ctx.reopen }); }
      const r = a === 'equip' ? await rpc('gear_equip', { p_gear: g.id, p_card: String(ctx.cardId) }) : a === 'unequip' ? await rpc('gear_unequip', { p_gear: g.id }) : await rpc('gear_lock', { p_gear: g.id, p_locked: !g.locked });
      if (r) done(); else b.disabled = false; });
  }

  // 가방 (slot 지정 시 그 슬롯만, cardId 있으면 고르면 장착)
  async function bag(ctx = {}) {
    if (!await load()) return toast('장비를 불러오지 못했어요');
    let filt = ctx.slot || 'all';
    const m = pop('', 'bag');
    const draw = () => {
      const list = (st.gear || []).filter(g => filt === 'all' || slotOf(g) === filt).sort((a, b) => (defs[b.def]?.tier || 0) - (defs[a.def]?.tier || 0) || b.plus - a.plus);
      const nx = st.next_expand;
      m.querySelector('.gear-pop').innerHTML = `<div class="gear-bag-top"><b>🎒 ${st.count}/${st.slots}</b>${nx ? `<button class="gear-btn" data-x>+10칸 ${window.VRGem?.ICON || '💎'} ${nx.gem}</button>` : '<small>최대</small>'}</div>
        <div class="gear-tabs">${[['all', '전체'], ...SLOTS].map(([k, l]) => `<button data-f="${k}" class="${filt === k ? 'on' : ''}">${k === 'all' ? '' : img(sil(k), k)}${l}</button>`).join('')}</div>
        <div class="gear-grid">${list.map(g => { const d = defs[g.def]; return `<button class="gear-cell gt${d.tier}" data-g="${g.id}">${img(iconOf(d), slotOf(g))}${g.plus ? `<i>+${g.plus}</i>` : ''}${g.card ? '<b class="gear-eq">E</b>' : ''}${g.locked ? '<b class="gear-lk">🔒</b>' : ''}</button>`; }).join('') || '<div class="gear-dim">아직 장비가 없어요. 소탕·탑·토벌에서 얻을 수 있어요</div>'}</div>`;
      m.querySelectorAll('[data-f]').forEach(b => b.onclick = () => { filt = b.dataset.f; draw(); });
      m.querySelectorAll('[data-g]').forEach(b => b.onclick = () => { const g = st.gear.find(x => String(x.id) === b.dataset.g);
        if (ctx.cardId && !g.card) { rpc('gear_equip', { p_gear: g.id, p_card: String(ctx.cardId) }).then(r => { if (r) { m.remove(); ctx.reopen?.(); } }); return; }
        itemPop(g, { cardId: ctx.cardId, back: () => { if (m.isConnected) draw(); } }); });
      const x = m.querySelector('[data-x]'); if (x) x.onclick = async () => { if (!confirm(`가방을 10칸 늘릴까요? (보석 ${nx.gem})`)) return; x.disabled = true; const r = await rpc('gear_expand', {}); if (r) { window.VRGem?.status?.(true); } if (m.isConnected) draw(); };
    };
    draw();
  }

  window.VRGear = { load, slotsHTML, bind, bag, get ready() { return !!st; }, get off() { return off; }, _defs: () => defs };
})();
