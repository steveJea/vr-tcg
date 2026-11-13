// 스킬·등장 연출 그림 (data/fx): 1280x720 · 장당 200KB 이하, 미리 디코드(warmFx) 후 컷인, 스테이징 미디어 캐시 헤더
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
const dims = f => { const b = readFileSync(f); const k = b.toString('ascii', 12, 16);
  if (k === 'VP8X') return [1 + b.readUIntLE(24, 3), 1 + b.readUIntLE(27, 3)];
  if (k === 'VP8 ') return [b.readUInt16LE(26) & 0x3fff, b.readUInt16LE(28) & 0x3fff];
  if (k === 'VP8L') { const v = b.readUInt32LE(21); return [1 + (v & 0x3fff), 1 + ((v >> 14) & 0x3fff)]; }
  throw Error('webp ' + f); };
const files = readdirSync('data/fx').filter(f => f.endsWith('.webp'));
assert(files.length >= 300);
const bad = files.filter(f => { const [w, h] = dims('data/fx/' + f); return w !== 1280 || h !== 720 || readFileSync('data/fx/' + f).length > 200000; });
assert.deepEqual(bad, [], 'data/fx 1280x720 ≤200KB');
const g = readFileSync('js/game.js', 'utf8');
assert.match(g, /function warmFx\(src\)[\s\S]{0,400}im\.decode\(\)/, 'warmFx decodes');
assert.match(g, /fxLoaded\.add\(s\.fx\); warmFx\(`data\/fx\/\$\{s\.fx\}`\)/, 'preloadFx → warmFx');
assert.match(g, /if \(fx\) await fxReady\(fx\);[^\n]*\n\s*const el = \$\('cutin'\);\n\s*el\.innerHTML = cutInHTML\(u, name, fx, passive\)/, 'active cut-in waits for decode');
assert.match(g, /async function passiveCutInPlain[\s\S]{0,400}await fxReady\(s\.fx\); if \(S !== st\) return;/, 'passive cut-in waits for decode');
assert.match(g, /function fxReady\(fx, ms = 220\)/, 'bounded wait');
assert.match(g, /fxWarm\.size > 24/, 'decoded LRU bound');
const b = readFileSync('tools/build_staging.mjs', 'utf8');
for (const p of ['/data/fx/*', '/data/voice/*', '/img/*']) assert(b.includes(`'${p}'`), p);
assert.match(b, /max-age=600, stale-while-revalidate=86400/);
console.log(`FX load: ${files.length} images 1280x720 ≤200KB, decode before cut-in (≤220ms wait, 24 LRU), staging media cache headers OK`);
