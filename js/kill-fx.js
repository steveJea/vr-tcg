/** 스킬 처치 연출 (화면만). 엔진 입력(skills.js·cards.csv·skills.json 등)은 건드리지 않음.
 *  목록: 배틀_특수효과_리스트 시트 「특수효과부여」 적용열 (2026-11-20). */
export const KILL_FX = {
  10291: 'slash', 10322: 'slash', 10323: 'slash', 10324: 'slash', 10440: 'slash',
  10513: 'slash', 10525: 'slash', 10117: 'slash', 10181: 'slash', 10200: 'slash',
  10213: 'slash', 10317: 'slash', 10321: 'slash', 10399: 'slash', 10529: 'slash',
  10051: 'shatter', 10053: 'shatter', 10054: 'shatter', 10058: 'shatter', 10060: 'shatter',
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

function lite() {
  try {
    return window.innerWidth < 768
      || document.documentElement.classList.contains('ios')
      || (window.matchMedia && matchMedia('(pointer: coarse)').matches && window.innerWidth < 900);
  } catch { return false; }
}
const pt = (x, y) => [x, y];
const poly = pts => `polygon(${pts.map(p => `${p[0].toFixed(1)}% ${p[1].toFixed(1)}%`).join(', ')})`;
function jag(a, b, amt) {
  const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
  const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy) || 1;
  const s = (Math.random() > 0.5 ? 1 : -1) * amt * (0.4 + Math.random() * 0.8);
  return [mx - (dy / len) * s, my + (dx / len) * s];
}
function jagged(pts, amt) {
  const out = [];
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i], b = pts[(i + 1) % pts.length];
    out.push(a, jag(a, b, amt));
  }
  return out;
}
function motion(cx, cy, fromTop) {
  const ang = Math.atan2(cy - 42, cx - 50);
  return {
    dx: Math.round(Math.cos(ang) * (16 + Math.abs(cx - 50) * 0.35) + (Math.random() - 0.5) * 8),
    dy: Math.round((fromTop ? 14 + cy * 0.28 : 10 + (cy - 40) * 0.35) + Math.abs(Math.sin(ang)) * 10),
    rot: Math.round((cx - 50) * 0.5 + (Math.random() - 0.5) * 28),
  };
}

/** 잘게, 위부터 부서짐. 삼각형이라 네모 그리드처럼 안 보임. 모바일은 조각을 줄임. */
function shatterClips() {
  const mobile = lite(), cols = mobile ? 4 : 6, rows = mobile ? 5 : 7;
  const jitter = (edge, span) => (edge ? 0 : (Math.random() - 0.5) * span);
  const g = [];
  for (let y = 0; y <= rows; y++) {
    const row = [];
    for (let x = 0; x <= cols; x++) {
      row.push([
        x * (100 / cols) + jitter(x === 0 || x === cols, 8),
        y * (100 / rows) + jitter(y === 0 || y === rows, 7),
      ]);
    }
    g.push(row);
  }
  const out = [];
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const a = g[y][x], b = g[y][x + 1], c = g[y + 1][x + 1], d = g[y + 1][x];
      const split = Math.random() > 0.5;
      const tris = split ? [[a, b, c], [a, c, d]] : [[a, b, d], [b, c, d]];
      for (const t of tris) {
        const cx = (t[0][0] + t[1][0] + t[2][0]) / 3, cy = (t[0][1] + t[1][1] + t[2][1]) / 3;
        out.push({ path: poly(t), delay: y * (mobile ? 0.045 : 0.035), ...motion(cx, cy, true) });
      }
    }
  }
  return out;
}

/** 깨진 유리: 중심에서 방사되는 들쭉날쭉한 삼각형·다각형 + 외곽 코너 포함. */
function glassClips() {
  const mobile = lite(), rays = mobile ? 9 : 12, rings = mobile ? 3 : 4;
  const cx = 48 + Math.random() * 6, cy = 34 + Math.random() * 8;
  const rayBox = ang => {
    const dx = Math.cos(ang), dy = Math.sin(ang);
    let t = Infinity;
    if (dx > 1e-6) t = Math.min(t, (100 - cx) / dx);
    else if (dx < -1e-6) t = Math.min(t, (0 - cx) / dx);
    if (dy > 1e-6) t = Math.min(t, (100 - cy) / dy);
    else if (dy < -1e-6) t = Math.min(t, (0 - cy) / dy);
    return [cx + dx * t, cy + dy * t];
  };
  const angles = [];
  let a0 = -Math.PI / 2 + (Math.random() - 0.5) * 0.25;
  for (let i = 0; i < rays; i++) angles.push(a0 + (i * Math.PI * 2) / rays + (Math.random() - 0.5) * 0.16);
  const corners = [[0, 0], [100, 0], [100, 100], [0, 100]];
  const edgeAt = ang => {
    let p = rayBox(ang);
    // snap nearly-at-corner hits so coverage stays tight
    for (const c of corners) if (Math.hypot(p[0] - c[0], p[1] - c[1]) < 8) return c;
    return p;
  };
  const raysPts = angles.map(ang => {
    const edge = edgeAt(ang);
    const pts = [pt(cx, cy)];
    for (let r = 1; r < rings; r++) {
      const t = r / rings;
      pts.push([
        cx + (edge[0] - cx) * t + (Math.random() - 0.5) * 5,
        cy + (edge[1] - cy) * t + (Math.random() - 0.5) * 5,
      ]);
    }
    pts.push(edge);
    return pts;
  });
  const cracks = raysPts.map(pts => pts.map(p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' '));
  const out = [];
  for (let i = 0; i < rays; i++) {
    const A = raysPts[i], B = raysPts[(i + 1) % rays];
    for (let r = 0; r < rings; r++) {
      const quad = [A[r], A[r + 1], B[r + 1], B[r]];
      const jagAmt = r === 0 ? 2.2 : 3.6;
      const shape = r === 0 || Math.random() > 0.35
        ? (Math.random() > 0.5
          ? [jagged([quad[0], quad[1], quad[3]], jagAmt), jagged([quad[1], quad[2], quad[3]], jagAmt)]
          : [jagged(quad, jagAmt)])
        : [jagged(quad, jagAmt)];
      for (const pts of shape) {
        const cxp = pts.reduce((s, p) => s + p[0], 0) / pts.length;
        const cyp = pts.reduce((s, p) => s + p[1], 0) / pts.length;
        out.push({ path: poly(pts), delay: 0.08 + cyp * 0.0022, ...motion(cxp, cyp, false) });
      }
    }
  }
  return { shards: out, cracks };
}

function cardArtUrl(src) {
  const img = src.matches?.('img') ? src : src.querySelector?.('img');
  return img?.currentSrc || img?.src || '';
}
function makeShard(url, clip, icy) {
  const sh = document.createElement('div');
  sh.className = `kfx-shard${icy ? ' kfx-shard-ice' : ''}`;
  if (url) {
    sh.style.backgroundImage = `url("${url}")`;
    sh.style.backgroundSize = '100% 100%';
  }
  sh.style.clipPath = clip.path;
  sh.style.setProperty('--dx', `${clip.dx}px`);
  sh.style.setProperty('--dy', `${clip.dy}px`);
  sh.style.setProperty('--rot', `${clip.rot}deg`);
  sh.style.setProperty('--delay', `${clip.delay}s`);
  return sh;
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

function fillShatter(wrap, src) {
  const url = cardArtUrl(src);
  for (const c of shatterClips()) wrap.appendChild(makeShard(url, c, false));
}
function fillGlass(wrap, src) {
  const url = cardArtUrl(src);
  const { shards, cracks } = glassClips();
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('class', 'kfx-cracks');
  svg.setAttribute('viewBox', '0 0 100 100');
  svg.setAttribute('preserveAspectRatio', 'none');
  svg.setAttribute('aria-hidden', 'true');
  for (const d of cracks) {
    const pl = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
    pl.setAttribute('points', d);
    svg.appendChild(pl);
  }
  wrap.appendChild(svg);
  for (const c of shards) wrap.appendChild(makeShard(url, c, true));
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
    fillShatter(wrap, src);
  } else if (kind === 'freeze') {
    const card = src.cloneNode(true);
    card.classList.add('kfx-frost-card');
    const frost = document.createElement('span');
    frost.className = 'kfx-frost';
    wrap.append(card, frost);
    fillGlass(wrap, src);
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
