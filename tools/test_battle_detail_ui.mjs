import assert from 'node:assert/strict';
import fs from 'node:fs';

const game = fs.readFileSync('js/game.js', 'utf8');
const css = fs.readFileSync('index.html', 'utf8');

// 71: zoom must use in-battle unit stats, not only the POOL base card
assert(game.includes('function battleInfoCard('));
assert(game.includes('function fieldUnitByUid('));
assert(game.includes('live.power = calcPower(live, skillsOf(live.id))'));
assert(game.includes('const unit = fieldUnitByUid(b.dataset.uid)'));
assert(game.includes('const c = battleInfoCard({ ...base, name: b.dataset.name || base.name }, unit)'));
assert(game.includes('const live = battleInfoCard(c, uInfo)'));
// display-only: do not write power/ATK back onto the engine unit
assert(!/unit\.card\.power\s*=/.test(game));

// 72: HP/MP bars beside the portrait, no per-turn regen text, COST beside region
assert(game.includes('function cardHmpBars('));
assert(game.includes('ci-hmp-fill hp'));
assert(game.includes('ci-hmp-fill mp'));
assert(game.includes("cardTitle(live, '', true)"));
assert(game.includes("cardTitle(c, '', true)"));
assert(game.includes('ci-cost'));
assert(game.includes('COST ${fmt(c.cost)}'));
assert(!game.includes('턴당 +${unit.mpRegen}'));
assert(!game.includes("턴당 +"));
assert(css.includes('.ci-hmp'));
assert(css.includes('.ci-hmp-fill.hp'));
assert(css.includes('.ci-hmp-fill.mp'));
assert(css.includes('.ci-cost'));
assert(css.includes('.ci-statrow'));
assert(css.includes('min-width: 768px'));
assert(game.includes('function cardStatRow('));
assert(css.includes('100dvh - 12rem'));

// PC bars: labels/values never wrap; HP/MP columns equal; bar group does not shrink
assert(css.includes('.ci-hmp-lab, .ci-hmp-lab span, .ci-hmp-lab b { white-space: nowrap; overflow-wrap: normal; word-break: keep-all; }'));
const iPc = css.indexOf('/* PC: HP');
const pcBar = css.slice(iPc, css.indexOf('}', css.indexOf('.zoom-info .ci-statrow', iPc)) + 1);
assert(pcBar.includes('flex: 0 0 16.5rem'));
assert(pcBar.includes('min-width: 16.5rem'));
assert(pcBar.includes('width: 16.5rem'));
assert(pcBar.includes('flex-wrap: nowrap'));
assert(!pcBar.includes('flex-wrap: wrap'));
assert(pcBar.includes('.ci-statrow .ci-hmp-col { flex: 1 1 0; width: 0; min-width: 0; }'));

// cost moved out of the battle detail/zoom tag line
assert(!game.includes("cardTags(live, [power ? '' : `⚡${fmt(live.power)}`, `${ic('mana', { alt: '코스트' })}${c.cost}`])"));
assert(!game.includes("cardTags(c, [`⚡${fmt(c.power)}`, `${ic('mana', { alt: '코스트' })}${c.cost}`])"));

console.log('PASS battle detail/zoom uses in-battle stats, HP/MP bars, COST, no 턴당 regen text');
