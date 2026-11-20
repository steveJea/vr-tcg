/** 스킬 처치 연출 (화면만). 엔진 입력(skills.js·cards.csv·skills.json 등)은 건드리지 않음.
 *  목록: 배틀_특수효과_리스트 시트 「특수효과부여」 적용열 (2026-11-20). */
export const KILL_FX = {
  10051: 'slash', 10053: 'slash', 10054: 'slash', 10058: 'slash', 10060: 'slash',
  10291: 'slash', 10322: 'slash', 10323: 'slash', 10324: 'slash', 10440: 'slash',
  10513: 'slash', 10525: 'slash', 10117: 'slash', 10181: 'slash', 10200: 'slash',
  10213: 'slash', 10317: 'slash', 10321: 'slash', 10399: 'slash', 10529: 'slash',
  10062: 'shatter', 10312: 'shatter', 10325: 'shatter', 10358: 'shatter', 10517: 'shatter',
  10024: 'shatter', 10045: 'shatter', 10067: 'shatter', 10109: 'shatter', 10112: 'shatter',
  10118: 'shatter', 10127: 'shatter', 10183: 'shatter', 10333: 'shatter', 10523: 'shatter',
  10526: 'shatter', 10530: 'shatter', 10534: 'shatter',
  10304: 'burn', 10326: 'burn', 10435: 'burn', 10504: 'burn', 10524: 'burn',
  10528: 'burn', 10068: 'burn', 10329: 'burn', 10373: 'burn', 10490: 'burn', 10491: 'burn',
  10311: 'shock', 10335: 'shock', 10341: 'shock', 10502: 'shock',
  10359: 'freeze', 10503: 'freeze', 10527: 'freeze', 10255: 'freeze',
};

export const KILL_FX_SE = { slash: 8, shatter: 9, freeze: 10, burn: 11, shock: 12 };
/** 연출 길이(ms). 효과음 길이에 맞추되 1.2~1.7초 안팎. */
export const KILL_FX_MS = { slash: 1200, shatter: 1400, freeze: 1600, burn: 1500, shock: 1300 };

const MAX_OVERLAYS = 5;
let skillKiller = null;
let overlayCount = 0;
let queuedWait = 0;

export function beginSkillKill(u) { skillKiller = u || null; }
export function endSkillKill() { skillKiller = null; }
export function skillKillKind(u = skillKiller) {
  const id = String(u?.card?.id ?? u?.base?.id ?? '');
  return KILL_FX[id] || null;
}
export function killFxWaitMs() { return queuedWait; }
export function takeKillFxWait() { const w = queuedWait; queuedWait = 0; return w; }

function host() {
  let h = document.getElementById('fx-host');
  if (!h) {
    h = document.createElement('div');
    h.id = 'fx-host';
    h.setAttribute('aria-hidden', 'true');
    document.body.appendChild(h);
  }
  return h;
}

function sourceEl(el) {
  return el.querySelector?.('.card-frame, .base-ring') || el;
}

function shardClips(cols = 3, rows = 4) {
  const jitter = (edge, span) => (edge ? 0 : (Math.random() - 0.5) * span);
  const pts = [];
  for (let y = 0; y <= rows; y++) {
    const row = [];
    for (let x = 0; x <= cols; x++) {
      row.push([
        x * (100 / cols) + jitter(x === 0 || x === cols, 10),
        y * (100 / rows) + jitter(y === 0 || y === rows, 8),
      ]);
    }
    pts.push(row);
  }
  const out = [];
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const a = pts[y][x], b = pts[y][x + 1], c = pts[y + 1][x + 1], d = pts[y + 1][x];
      const ang = Math.atan2(y + 0.5 - rows / 2, x + 0.5 - cols / 2);
      out.push({
        path: `polygon(${a[0].toFixed(1)}% ${a[1].toFixed(1)}%, ${b[0].toFixed(1)}% ${b[1].toFixed(1)}%, ${c[0].toFixed(1)}% ${c[1].toFixed(1)}%, ${d[0].toFixed(1)}% ${d[1].toFixed(1)}%)`,
        delay: y * 0.06,
        dx: Math.round(Math.cos(ang) * (18 + y * 8 + x * 3)),
        dy: Math.round(22 + y * 14 + Math.sin(ang) * 8),
        rot: Math.round((x - 1) * 16 + (y + 1) * 10),
      });
    }
  }
  return out;
}

function addParticles(wrap, cls, n, conf) {
  for (let i = 0; i < n; i++) {
    const p = document.createElement('i');
    p.className = cls;
    const a = conf.angle0 + (i / n) * (conf.spread || Math.PI * 2);
    p.style.setProperty('--dx', `${Math.round(Math.cos(a) * (conf.dist0 + (i % 3) * conf.distStep))}px`);
    p.style.setProperty('--dy', `${Math.round(conf.dy0 + Math.sin(a) * conf.distStep + (i % 4) * conf.dyStep)}px`);
    p.style.setProperty('--delay', `${(conf.delay0 || 0) + i * (conf.delayStep || 0.03)}s`);
    wrap.appendChild(p);
  }
}

function fillShards(wrap, src, icy) {
  const clips = shardClips();
  for (const c of clips) {
    const sh = src.cloneNode(true);
    sh.classList.add('kfx-shard');
    if (icy) sh.classList.add('kfx-shard-ice');
    sh.style.clipPath = c.path;
    sh.style.setProperty('--dx', `${c.dx}px`);
    sh.style.setProperty('--dy', `${c.dy}px`);
    sh.style.setProperty('--rot', `${c.rot}deg`);
    sh.style.setProperty('--delay', `${c.delay}s`);
    wrap.appendChild(sh);
  }
}

/**
 * 카드 DOM을 #fx-host 에 복제해 처치 연출을 바로 시작 (이후 render 로 원본이 사라져도 유지).
 * @returns 연출 시간(ms)
 */
export function queueKillFx(el, kind, { playSe, reduced = false } = {}) {
  if (!el || !kind || !KILL_FX_MS[kind]) return 0;
  if (overlayCount >= MAX_OVERLAYS) return 0;
  const src = sourceEl(el);
  const r = src.getBoundingClientRect();
  if (!r.width || !r.height) return 0;

  const ms = reduced ? 160 : KILL_FX_MS[kind];
  const wrap = document.createElement('div');
  wrap.className = `kfx kfx-${kind}${reduced ? ' kfx-reduced' : ''}`;
  wrap.style.cssText = `left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px`;

  if (reduced) {
    const card = src.cloneNode(true);
    card.classList.add('kfx-fade');
    wrap.appendChild(card);
  } else if (kind === 'slash') {
    const a = src.cloneNode(true), b = src.cloneNode(true);
    a.classList.add('kfx-half', 'kfx-half-a');
    b.classList.add('kfx-half', 'kfx-half-b');
    const gleam = document.createElement('span');
    gleam.className = 'kfx-gleam';
    wrap.append(a, b, gleam);
  } else if (kind === 'shatter') {
    fillShards(wrap, src, false);
  } else if (kind === 'freeze') {
    const card = src.cloneNode(true);
    card.classList.add('kfx-frost-card');
    const frost = document.createElement('span');
    frost.className = 'kfx-frost';
    wrap.append(card, frost);
    fillShards(wrap, src, true);
  } else if (kind === 'burn') {
    const card = src.cloneNode(true);
    card.classList.add('kfx-burn-card');
    const edge = document.createElement('span');
    edge.className = 'kfx-burn-edge';
    wrap.append(card, edge);
    addParticles(wrap, 'kfx-ember', 10, { angle0: -Math.PI * 0.85, spread: Math.PI * 0.7, dist0: 8, distStep: 10, dy0: -18, dyStep: -8, delay0: 0.05, delayStep: 0.04 });
    addParticles(wrap, 'kfx-ash', 8, { angle0: 0.2, spread: Math.PI, dist0: 6, distStep: 8, dy0: 16, dyStep: 7, delay0: 0.25, delayStep: 0.05 });
  } else if (kind === 'shock') {
    const card = src.cloneNode(true);
    card.classList.add('kfx-shock-card');
    wrap.appendChild(card);
    for (let i = 0; i < 3; i++) {
      const bolt = document.createElement('span');
      bolt.className = `kfx-bolt kfx-bolt-${i}`;
      wrap.appendChild(bolt);
    }
    const flash = document.createElement('span');
    flash.className = 'kfx-flash';
    wrap.appendChild(flash);
  }

  el.classList.add('kfx-hide');
  host().appendChild(wrap);
  overlayCount++;
  queuedWait = Math.max(queuedWait, ms);
  if (!reduced) {
    const code = KILL_FX_SE[kind];
    try { playSe?.(code); } catch {}
  }
  setTimeout(() => { wrap.remove(); overlayCount = Math.max(0, overlayCount - 1); }, ms + 40);
  return ms;
}

const VRKillFx = { map: KILL_FX, se: KILL_FX_SE, ms: KILL_FX_MS, beginSkillKill, endSkillKill, skillKillKind, queueKillFx, killFxWaitMs, takeKillFxWait };
try { globalThis.VRKillFx = VRKillFx; } catch {}
export default VRKillFx;
