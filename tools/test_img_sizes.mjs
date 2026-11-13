// 그림 크기 규칙: img/thumb 가로 300 · img/npc 576x864·100KB 이하 (MR/LR 10334·10335 원본 유지) · data/event 1280x720
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
const dims = f => { const b = readFileSync(f); const k = b.toString('ascii', 12, 16);
  if (k === 'VP8X') return [1 + b.readUIntLE(24, 3), 1 + b.readUIntLE(27, 3)];
  if (k === 'VP8 ') return [b.readUInt16LE(26) & 0x3fff, b.readUInt16LE(28) & 0x3fff];
  if (k === 'VP8L') { const v = b.readUInt32LE(21); return [1 + (v & 0x3fff), 1 + ((v >> 14) & 0x3fff)]; }
  throw Error('webp ' + f); };
const webp = d => readdirSync(d).filter(f => f.endsWith('.webp'));
const bad = [];
for (const f of webp('img/thumb')) { const [w] = dims('img/thumb/' + f); if (w !== 300) bad.push('thumb ' + f + ' w=' + w); }
for (const f of webp('img/npc')) { if (/^(10334|10335)\./.test(f)) continue; const p = 'img/npc/' + f, [w, h] = dims(p);
  if (w !== 576 || h !== 864) bad.push(`npc ${f} ${w}x${h}`); if (readFileSync(p).length > 100000) bad.push('npc ' + f + ' >100KB'); }
// 카드 원본 (vr-ideal-worldcup 에서 옮겨 온 것, tools/sync_card_art 참고): 576x864 이하·100KB 이하
for (const f of webp('img/bt_img')) { const p = 'img/bt_img/' + f, [w, h] = dims(p); if (w > 576 || h > 864) bad.push(`bt_img ${f} ${w}x${h}`); if (readFileSync(p).length > 100000) bad.push('bt_img ' + f + ' >100KB'); }
for (const f of webp('data/event')) { const [w, h] = dims('data/event/' + f); if (w !== 1280 || h !== 720) bad.push(`event ${f} ${w}x${h}`); }
assert.deepEqual(bad, []);
console.log('Image sizes: thumb 300w, npc 576x864 ≤100KB (except MR/LR 10334/10335), event 1280x720, bt_img ≤576x864 ≤100KB OK');
