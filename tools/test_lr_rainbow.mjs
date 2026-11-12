// LR 등급 무지개 통일 (썸네일·카드 배지·테두리, 모든 화면) — 2026-11-12
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const css = await readFile('css/lr-rainbow.css', 'utf8'), html = await readFile('index.html', 'utf8');
assert.match(html, /<link rel="stylesheet" href="css\/lr-rainbow\.css">/, 'loaded globally');
assert(html.indexOf('css/lr-rainbow.css') > html.indexOf('css/tw.css'), 'after tailwind/screen css');
for (const sel of ['.rar-lr .rar-badge', '.rar-lr .story-rar', '.rar-LR .mp-rar', '.rar-LR .gal-rar', '.rar-LR .q-rar', '.q-g.rar-LR', '.tr-gr.g-LR', '.gn-g.g-LR', '.g-LR .tr-gc-gr'])
  assert(css.includes(sel), 'badge selector ' + sel);
for (const sel of ['.mp-card.rar-LR', '.mp-leader.rar-LR', '.q-enemy.rar-LR', '.gal-card.rar-LR', '.story-card.rar-lr', '.gear-who.rar-lr', '.tr-gc.g-LR'])
  assert(css.includes(sel), 'border selector ' + sel);
assert.match(css, /--lrg: linear-gradient\(90deg,#f87171,#fbbf24,#a3e635,#22d3ee,#818cf8,#e879f9,#f87171\)/, 'same gradient as .rar-badge.rar-lr');
assert.match(css, /@media \(prefers-reduced-motion: reduce\)[\s\S]*animation: none !important/, 'reduced motion');
// 각 화면 코드가 LR 클래스를 실제로 내보내는지
const g = await readFile('js/game.js', 'utf8'); assert.match(g, /'LEGENDARY RARE': \{ short: 'LR', label: '레전더리 레어', cls: 'rar-lr' \}/);
for (const f of ['js/mypage.js', 'js/gallery.js', 'js/quest.js', 'js/story.js']) assert.match(await readFile(f, 'utf8'), /'LEGENDARY RARE': 'LR'/, f);
console.log('LR rainbow: badges + borders on battle/merc, gallery, mypage, story, quest, trade, gear; reduced-motion OK');
