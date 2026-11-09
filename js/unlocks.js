// Level-only navigation policy. The database is authoritative for actions/rewards.
(() => {
  'use strict';
  const P = window.VR_UNLOCK_POLICY; if (!P) return;
  const $ = id => document.getElementById(id);
  let state = null, account = '', refreshed = 0, loading = false, active = null, wasLobby = false;
  const deferred = new Set();
  const level = () => { const uid=window.VRCloud?.user?.id; if(uid && account && uid!==account) return 1; return Number(state?.level || window.VRPlayer?.now?.()?.level || 1); };
  const need = key => P.features[key] ?? Infinity;
  const allowed = key => level() >= need(key);
  const cue = key => `🔒 Lv${need(key)}`;
  const pvpKey = (league, mode) => mode === 'boss' ? 'pvp_boss' : mode === '3v3' ? 'pvp_3v3' : league === 'hr' ? 'pvp_hr' : 'pvp_open';
  const toast = text => { if (window.VRGem?.toast) return window.VRGem.toast(text); const el = document.createElement('div'); el.className = 'ul-toast'; el.textContent = text; document.body.appendChild(el); setTimeout(() => el.remove(), 1800); };
  const guard = key => { if (allowed(key)) return true; toast(cue(key)); return false; };
  function levelPop(n) {
    document.getElementById('ul-lockpop')?.remove();
    const el = document.createElement('div'); el.id = 'ul-lockpop'; el.className = 'ul-lockpop';
    el.setAttribute('role', 'dialog'); el.setAttribute('aria-modal', 'true');
    const box = document.createElement('div'); box.className = 'ul-lockpop-box';
    const p = document.createElement('p'); p.textContent = `계정레벨 ${n} 이후 이용할 수 있습니다`;
    const b = document.createElement('button'); b.type = 'button'; b.textContent = '확인';
    const close = () => { el.remove(); document.removeEventListener('keydown', onKey); };
    const onKey = e => { if (e.key === 'Escape') close(); };
    b.onclick = close;
    el.addEventListener('click', e => { if (e.target === el) close(); });
    document.addEventListener('keydown', onKey);
    box.append(p, b); el.append(box); document.body.append(el); b.focus();
  }
  const selectors = [
    ['#main-pvp,[data-gnb="pvp"]','pvp_hr'], ['#main-guild,[data-guild-open],[data-gnb="guild"]','guild'],
    ['[data-gnb="tower"],#main-quest','tower'], ['[data-dispatchbtn] button','dispatch'],
    ['[data-friendbtn] button,[data-nav="friends"]','friends'], ['[data-nav="camp"]','camp'],
    ['[data-nav="gearbag"],[data-go="gearbag"],[data-gslot]:not([data-gslot="sigil"])','gear'], ['#main-trade,#main-trade-tile,#story-trade','trade'],
    ['[data-forge]','forge'], ['[data-dojo],[data-dojounlock]','dojo'], ['[data-t="raid"]','raid'], ['[data-t="war"]','war'], ['[data-t="lend"]','lend'],
    ['[data-merge]','merge'], ['[data-skup]','skill'], ['[data-gslot="sigil"]','sigil'],
  ];
  function feature(el) {
    if (el.dataset.unlock) return el.dataset.unlock;
    if (el.matches('.th-card[data-tower]')) return el.dataset.tower === 'normal' ? 'tower' : 'tower_' + el.dataset.tower;
    for (const [sel, key] of selectors) if (el.matches(sel)) return key;
    return null;
  }
  const match = selectors.map(x => x[0]).join(',') + ',[data-unlock],.th-card[data-tower]';
  function paint() {
    document.querySelectorAll(match).forEach(el => {
      const key = feature(el); if (!key) return;
      const locked = !allowed(key), tab = el.matches('.gnb-t'), badge = el.querySelector(':scope > .ul-lock');
      el.classList.toggle('ul-locked', locked);
      if (tab) badge?.remove();   // 하단 탭은 Lv 뱃지 없음
      else if (locked && !badge) { const b = document.createElement('span'); b.className = 'ul-lock'; b.textContent = cue(key); el.appendChild(b); }
      else if (locked && badge && badge.textContent !== cue(key)) badge.textContent = cue(key);
      else if (!locked) badge?.remove();
      if (locked) el.setAttribute('data-level-locked', ''); else el.removeAttribute('data-level-locked');
    });
  }
  document.addEventListener('click', e => {
    const el = e.target.closest?.(match), key = el && feature(el);
    if (!key || allowed(key)) return;
    e.preventDefault(); e.stopImmediatePropagation();
    if (el.matches('.gnb-t')) levelPop(need(key)); else toast(cue(key));
  }, true);
  // Native keyboard activation produces a click, and the same guard applies to it.
  const visible = el => !!el && !el.classList.contains('hidden') && !el.hidden;
  function lobby() {
    if (!visible($('start-screen')) || visible($('story-screen')) || window.VRPages?.depth) return false;
    if (window.__storyVideo?.el?.isConnected || Array.from(document.querySelectorAll('video')).some(v=>!v.paused&&!v.ended)) return false;
    if (window.VRGnb?.busy?.() || visible($('game')) || visible($('intro')) || visible($('story-intro'))) return false;
    return !Array.from(document.querySelectorAll('#gr-vid,.story-vcut,.story-ovp,#story-video,.pvp-vsx,#pvp-play,.gr-forced,.gem-pop,#story-pop,#camp-ov,#dispatch-ov,#pvp-modal,#guild-modal,#fr-pop,[role="dialog"]:not(#unlock-intro)')).some(el => !el.closest('.hidden,[hidden]') && getComputedStyle(el).display !== 'none');
  }
  async function rpc(name, args) {
    const c = window.VRCloud; if (!c?.user || !c?.sb) throw Error('login required');
    const r = await c.sb.rpc(name, args); if (r.error) throw r.error; return r.data;
  }
  const routes = {
    pvp: () => window.VRPvp?.open?.(), tower: () => window.VRQuest?.open?.(), guild: () => window.VRGuild?.open?.(),
    dispatch: () => window.VRDispatch?.open?.(), camp: () => window.VRCamp?.open?.(), friends: () => window.VRFriends?.open?.(),
    trade: () => window.VRTrade?.open?.(), cards: () => window.VRStory?.openCards?.(), decks: () => window.VRStory?.openDecks?.(),
    summon: () => window.VRStory?.openShop?.(), raid: () => window.VRRaid?.open?.(), war: () => window.VRWar?.open?.(),
  };
  function dismiss() { active?.remove(); active = null; }
  function show(e) {
    const el = document.createElement('div'); el.id = 'unlock-intro'; el.setAttribute('role','dialog'); el.setAttribute('aria-modal','true');
    el.setAttribute('aria-labelledby','unlock-title');
    const box = document.createElement('div'); box.className = 'ul-box';
    const h = document.createElement('h2'); h.id = 'unlock-title'; h.textContent = e.title;
    const text = document.createElement('p'); text.textContent = e.text;
    const reward = document.createElement('p'); reward.className = 'ul-rewards';
    const labels = {gold:'골드', blood:'순수한 피', soul:'혼', tickets:'소환권', boxes:'희귀 장비상자',sigil_boxes:'증표조각 선택상자'};
    reward.textContent = Object.entries(e.reward).map(([k,n])=>`${labels[k] || k} ${n.toLocaleString('ko-KR')}`).join(' · ');
    if (e.key === 'ch0') reward.textContent = '소환권 10 (챕터 클리어 보상)';
    const buttons = document.createElement('div'); buttons.className = 'ul-actions';
    const done = document.createElement('button'); done.textContent = '확인';
    const go = document.createElement('button'); go.textContent = '살펴보기';
    const uid = window.VRCloud?.user?.id;
    const finish = async navigate => {
      if (window.VRCloud?.user?.id !== uid) { dismiss(); return; }
      done.disabled = go.disabled = true;
      try {
        const r = await rpc('unlock_intro_claim',{p_event:e.key});
        if (r?.wallet) window.VRPlayer?.setWallet?.(r.wallet);
        if (state) { const s = state.entries.find(x=>x.key===e.key); if(s) s.claimed=true; }
        dismiss(); refreshed = 0; window.VRStory?.api?.syncTickets?.(); window.VRGear?.load?.(true);
        if (navigate) routes[e.route]?.();
      } catch (err) { done.disabled=go.disabled=false; toast(/Lv\d|intro locked/.test(err.message || '') ? '다시 확인해 주세요' : '잠시 후 다시 시도해 주세요'); }
    };
    if (e.action_done === false) {
      done.textContent=e.key === 'tower' ? '한 판 도전' : '인재 고르기';
      done.onclick=()=>{deferred.add(e.key);dismiss();routes[e.route]?.();};
      go.textContent='나중에';go.onclick=()=>{deferred.add(e.key);dismiss();};
    } else {done.onclick=()=>finish(false); go.onclick=()=>finish(true);}
    buttons.append(done); if (routes[e.route]) buttons.append(go);
    // No material purchase, guild join or forced auto-assignment can block this intro.
    box.append(h,text); if(reward.textContent) box.append(reward); box.append(buttons); el.append(box);
    el.addEventListener('keydown',event=>{ if(event.key==='Tab'){const all=Array.from(el.querySelectorAll('button:not(:disabled)'));const next=event.shiftKey?all.at(-1):all[0];if((!event.shiftKey&&document.activeElement===all.at(-1))||(event.shiftKey&&document.activeElement===all[0])){event.preventDefault();next?.focus();}}});
    document.body.append(el); active=el; done.focus();
  }
  async function refresh(force=false) {
    const uid=window.VRCloud?.user?.id;
    if (!uid) { state=null; account=''; dismiss(); return; }
    if (uid!==account) { account=uid; state=null; refreshed=0; deferred.clear(); dismiss(); }
    if (loading || (!force && Date.now()-refreshed<20000)) return;
    loading=true; refreshed=Date.now();
    try { const s=await rpc('unlock_status',{}); if(window.VRCloud?.user?.id===uid) state=s; }
    catch { /* Not deployed yet: no client-side grant and no progression block. */ }
    finally { loading=false; paint(); }
  }
  async function tick() {
    paint();
    if (active && (!window.VRCloud?.user || !lobby())) dismiss();
    const here=lobby(); const arrived=here&&!wasLobby; wasLobby=here;
    if (!here) return;
    await refresh(arrived);
    if (!active && lobby() && state) {
      const e=state.entries.find(x=>x.eligible && !x.claimed && (!deferred.has(x.key) || x.action_done === true)); if(e) show(e);
    }
  }
  const css=document.createElement('link'); css.rel='stylesheet'; css.href='css/unlocks.css'; document.head.append(css);
  window.VRUnlocks={level,need,allowed,guard,cue,pvpKey,paint,refresh,lobby,tick};
  window.addEventListener('vr-player-change',()=>{if(state && window.VRCloud?.user?.id===account) state.level=window.VRPlayer?.now?.()?.level || state.level;paint();refreshed=0;});
  document.addEventListener('DOMContentLoaded',paint,{once:true});
  setInterval(tick,1000); paint();
})();
