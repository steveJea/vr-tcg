// 2026-11-12 Drive 그림: 프로필 7장(img/npc 576x864 + img/thumb 300x450, OVERRIDE) · 스킬 연출 4장(data/fx 1792x1008)
// skills.json(엔진 입력)은 그대로 두고 js/img-fallback.js 의 VRSkillFx 로 화면 쪽 fx 만 채움.
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import vm from 'node:vm';
const PORTRAITS = ['10059', '10321', '10329', '10459', '10460', '10461', '10470'];
const FX = { 10025: ['10025_1.webp', '10025_2.webp'], 10321: ['10321_1.webp', '10321_2.webp'], 10329: ['10329_1.webp', '10329_2.webp'] };
const dims = f => { const b = readFileSync(f); assert.equal(b.toString('ascii', 0, 4), 'RIFF', f); assert.equal(b.toString('ascii', 8, 12), 'WEBP', f);
  const k = b.toString('ascii', 12, 16);
  if (k === 'VP8X') return [1 + b.readUIntLE(24, 3), 1 + b.readUIntLE(27, 3)];
  if (k === 'VP8 ') return [b.readUInt16LE(26) & 0x3fff, b.readUInt16LE(28) & 0x3fff];
  if (k === 'VP8L') { const v = b.readUInt32LE(21); return [1 + (v & 0x3fff), 1 + ((v >> 14) & 0x3fff)]; }
  throw Error('webp ' + f); };
const src = readFileSync('js/img-fallback.js', 'utf8');
const npcLocal = new Set(src.match(/NPC_LOCAL = new Set\('([^']*)'/)[1].split(','));
const override = new Set([...src.match(/OVERRIDE = new Set\(\[([^\]]*)\]/)[1].matchAll(/'(\d+)'/g)].map(m => m[1]));
const cards = readFileSync('data/cards.csv', 'utf8');
for (const id of PORTRAITS) {
  assert(new RegExp('^' + id + ',', 'm').test(cards), id + ' in cards.csv');
  assert.deepEqual(dims(`img/npc/${id}.webp`), [576, 864], id);
  assert.deepEqual(dims(`img/thumb/${id}.webp`), [300, 450], id + ' thumb');
  assert(npcLocal.has(id) && override.has(id), id + ' wired');
  assert(readFileSync(`img/npc/${id}.webp`).length <= 100000, id + ' ≤100KB (test_npc_img)');
}
const skills = JSON.parse(readFileSync('data/skills.json', 'utf8'));
for (const [id, list] of Object.entries(FX)) for (const f of list) { assert(existsSync('data/fx/' + f), f); assert.deepEqual(dims('data/fx/' + f), [1792, 1008], f); }
// VRSkillFx: 빈 fx 만 채움, 원본 객체 외 다른 카드·기존 fx 는 그대로
const ctx = { document: { addEventListener() {}, querySelectorAll: () => [], readyState: 'complete' }, window: {}, MutationObserver: class { observe() {} }, HTMLImageElement: class {}, setTimeout, console };
ctx.globalThis = ctx; ctx.window = ctx; vm.createContext(ctx); vm.runInContext(src, ctx);
const sk = JSON.parse(JSON.stringify(skills)); ctx.VRSkillFx(sk);
for (const [id, list] of Object.entries(FX)) list.forEach((f, i) => assert.equal(sk[id][i].fx, f));
for (const id of Object.keys(skills)) if (!FX[id]) assert.equal(JSON.stringify(sk[id]), JSON.stringify(skills[id]), id + ' untouched');
const pre = JSON.parse(JSON.stringify(skills)); pre[10321][0].fx = 'keep.webp'; ctx.VRSkillFx(pre); assert.equal(pre[10321][0].fx, 'keep.webp');
assert.equal(ctx.VRSkillFx(null), null);
for (const [f, re] of [['js/game.js', /VRSkillFx\?\.\(sk\);[^\n]*\n\s*setSkillData\(sk, co\)/], ['js/gallery.js', /globalThis\.VRSkillFx\?\.\(skills\)/], ['js/quest-sim.js', /VRSkillFx\?\.\(sk\);[^\n]*\n\s*SK\.setSkillData/]]) assert.match(readFileSync(f, 'utf8'), re, f);
// 모든 SUPER RARE 카드: 스킬마다 연출 이미지 (skills.json fx 또는 VRSkillFx 추가분), 파일 존재
{ const rows = cards.trim().split('\n'), head = rows[0].split(','), gi = head.indexOf('grade');
  const sr = rows.slice(1).map(l => l.split(',')).filter(c => c[gi] === 'SUPER RARE').map(c => c[0]);
  assert.equal(sr.length, 50, 'SR count');
  const miss = [];
  for (const id of sr) { const list = sk[id] || []; if (!list.length) miss.push(id + ':none');
    list.forEach((s, i) => { if (!s.fx || !existsSync('data/fx/' + s.fx)) miss.push(`${id}_${i + 1}`); }); }
  assert.deepEqual(miss, [], 'SR skill images'); }
console.log('Art 11-12: all 50 SR skills have images · 7 portraits (576x864 + 300x450 thumb, OVERRIDE) · 6 skill fx (1792x1008) via VRSkillFx, skills.json untouched OK');
