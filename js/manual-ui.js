// ===== 수동 전투 화면 (균열 토벌 · PvP 공용) =====
// 전투 계산은 js/pvp-core.js·raid-core.js 의 수동 세션(서버 seed · 덱 스냅샷 그대로). 화면은 입력만 넘기고 상태를 읽어 그린다.
// 내 카드 탭 → 선택(스킬 버튼) → 적 탭 = 공격. 같은 카드 다시 탭 = 선택 해제. 턴 종료 · AUTO(남은 전투 자동)
import { skillState } from './skills.js';
import { attackTargets } from './rules.js';

const IMG = 'https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/';
const MODE_KEY = 'vrBattleMode';
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const n = v => Number(v || 0).toLocaleString('ko-KR');
if (typeof document !== 'undefined' && !document.getElementById('mb-css')) { const l = document.createElement('link'); l.id = 'mb-css'; l.rel = 'stylesheet'; l.href = 'css/manual.css'; document.head.appendChild(l); }

export const battleMode = () => localStorage.getItem(MODE_KEY) === 'manual' ? 'manual' : 'auto';
/** 전투 시작 버튼 옆 AUTO / 수동 토글 */
export const modeToggle = () => `<div class="mb-mode" role="group" aria-label="전투 방식"><button type="button" data-bmode="auto" class="${battleMode() === 'auto' ? 'on' : ''}">AUTO</button><button type="button" data-bmode="manual" class="${battleMode() === 'manual' ? 'on' : ''}">수동</button></div>`;
export function bindMode(root) {
  root.querySelectorAll('.mb-mode [data-bmode]').forEach(b => b.onclick = e => { e.stopPropagation(); localStorage.setItem(MODE_KEY, b.dataset.bmode);
    root.querySelectorAll('.mb-mode [data-bmode]').forEach(x => x.classList.toggle('on', x === b)); });
}

/** 수동 한 판. session = manualMatch/manualRaid 결과, rec = 그 세션의 기록 배열. 끝나면 결과로 resolve */
export function playManual({ session, rec = [], title = '', maxTurns = 0, raid = false, round = '' }) {
  return new Promise(done => {
    const ov = document.createElement('div'); ov.className = 'mb-ov'; document.body.appendChild(ov);
    let x = session.next(), sel = null, seen = rec.length, fx = [], auto = false;
    const finish = () => { ov.remove(); done(x.value); };
    const go = inp => { if (x.done) return; x = session.next(inp); sel = null; collect(); if (x.done) { paint(); setTimeout(finish, 700); } else paint(); };
    const collect = () => {   // 새 기록 → 짧은 효과 글
      const st = x.value || {}, A0 = st.A0 || [], nm = uid => (A0.find(u => u.uid === uid) || (st.B0 || []).find(u => u.uid === uid))?.card?.name || '';
      fx = rec.slice(seen).filter(f => f.k === 'skill' || f.k === 'atk').slice(-3).map(f => `${f.side === 'A' ? '' : '⚠ '}${esc(nm(f.u))}${f.k === 'skill' && f.s ? ` ✨${esc(f.s)}` : ' ⚔'}${f.d ? ` <b>-${n(f.d)}</b>` : ''}`);
      seen = rec.length;
    };
    const unit = (u, i, side, st, tg) => {
      const dead = u.hp <= 0 || !(side === 'A' ? st.A : st.B).field.includes(u), ready = side === 'A' && !dead && u.canAttack;
      return `<button type="button" class="mb-u ${side === 'A' ? 'me' : 'foe'} ${dead ? 'dead' : ''} ${ready ? 'ready' : ''} ${sel === i && side === 'A' ? 'sel' : ''} ${tg ? 'tg' : ''}" data-side="${side}" data-i="${i}" ${dead ? 'disabled' : ''}>
        <img src="${IMG}${u.base?.id || u.card.id}.webp" alt="${esc(u.card.name)}"><i class="hp"><b style="width:${raid && side === 'B' ? 100 : Math.max(0, Math.min(100, u.hp / u.maxHp * 100))}%"></b></i>${side === 'A' ? `<i class="mp"><b style="width:${u.maxMp ? Math.min(100, u.mp / u.maxMp * 100) : 0}%"></b></i>` : ''}</button>`;
    };
    const paint = () => {
      const st = x.value || {}; if (!st.A0) return;
      const su = sel != null ? st.A0[sel] : null, tgs = su ? attackTargets(st.A, st.B, su).units : [];
      const sks = su ? su.sk.filter(s => s.mode === 'active' && su.level >= s.unlock) : [];
      ov.innerHTML = `<div class="mb-top"><b>${esc(title)}</b><small>${round ? esc(round) + ' · ' : ''}T${Math.min(st.t || 1, maxTurns || 99)}${maxTurns ? '/' + maxTurns : ''}</small>${raid ? `<em>${n(x.done ? x.value.damage : st.damage)}</em>` : ''}<button type="button" class="mb-auto" data-auto>AUTO ⏩</button></div>
        <div class="mb-side foe ${raid ? 'boss' : ''}">${(st.B0 || []).map((u, i) => unit(u, i, 'B', st, tgs.includes(u))).join('')}</div>
        <div class="mb-fx">${x.done ? (raid ? `<b>${n(x.value.damage)}</b>` : `<b class="${x.value.win ? 'win' : 'lose'}">${x.value.win ? 'WIN' : 'LOSE'}</b>`) : fx.join('<br>')}</div>
        <div class="mb-side me">${st.A0.map((u, i) => unit(u, i, 'A', st)).join('')}</div>
        <div class="mb-bar">${su ? sks.map(s => { const ok = skillState(su, s).ok; return `<button type="button" class="mb-sk" data-sk="${esc(s.name)}" ${ok ? '' : 'disabled'}>✨${esc(s.label || s.name)}<small>${s.mp}</small></button>`; }).join('') + (raid && tgs.length ? '<button type="button" class="mb-sk atk" data-atk>⚔ 공격</button>' : '') : `<span class="mb-hint">${x.done ? '' : '내 카드를 누르세요'}</span>`}
          <button type="button" class="mb-end" data-end ${x.done ? 'disabled' : ''}>턴 종료</button></div>`;
    };
    ov.addEventListener('click', e => {
      if (x.done || auto) return;
      const st = x.value, b = e.target.closest('button'); if (!b) { sel = null; return paint(); }
      if (b.dataset.auto != null) { auto = true; const run = () => { if (x.done) return; go({ k: 'auto' }); setTimeout(run, 30); }; return run(); }
      if (b.dataset.end != null) return go({ k: 'end' });
      if (b.dataset.sk) return go({ k: 'skill', i: sel, s: b.dataset.sk });
      if (b.dataset.atk != null) return go({ k: 'atk', i: sel, t: 0 });
      const i = +b.dataset.i;
      if (b.dataset.side === 'A') { sel = sel === i ? null : (st.A0[i].canAttack ? i : null); return paint(); }
      if (b.dataset.side === 'B' && sel != null) { const t = st.B0[i]; if (attackTargets(st.A, st.B, st.A0[sel]).units.includes(t)) return go({ k: 'atk', i: sel, t: i }); }
    });
    collect(); paint();
  });
}
