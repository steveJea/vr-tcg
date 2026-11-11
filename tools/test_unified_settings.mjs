// Every settings gear (home, top bar on every page/screen, battle) opens the one 게임설정 menu (window.VRMenu).
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const rd=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const [menu,top,game,html,css]=await Promise.all(['js/main-menu.js','js/topnav.js','js/game.js','index.html','css/main-screen.css'].map(rd));
assert.match(menu,/window\.VRMenu = \{ open, close, toggle/);
assert.match(menu,/gear\.addEventListener\('click', e => \{ e\.stopPropagation\(\); toggle\(\); \}\)/,'home gear');
assert.match(top,/\.tnb-set'\)\.onclick = e => \{ e\?\.stopPropagation\?\.\(\); if \(window\.VRMenu\) window\.VRMenu\.toggle\(\);/,'top bar gear on every screen');
assert(!/pop\('bset-btn', 'bset-pop'\)/.test(game),'battle gear no longer opens its own popup');
assert.match(game,/\$\('bset-btn'\)\?\.addEventListener\('click', e => \{[^\n]*\n    if \(window\.VRMenu\) window\.VRMenu\.toggle\(\);/,'battle gear opens the menu');
// battle settings kept: moved into the menu during battle; leaving/logout items hidden mid-fight
assert.match(menu,/if \(battle && bset\) \{ slot\.appendChild\(bset\);/);
for(const id of ['main-rank','main-gallery','main-link-google','main-link-kakao','main-link-x','main-logout'])assert.match(html,new RegExp(`id="${id}"[^>]*data-gm-nobattle`),id);
for(const id of ['main-tutorial','arcade-opts-btn'])assert.match(html,new RegExp(`id="${id}"[^>]*data-gm-home`),id);
assert.match(css,/#main-menu-pop\.gm-in-battle \[data-gm-nobattle\], #main-menu-pop\.gm-in-battle \[data-gm-home\], #main-menu-pop\.gm-away \[data-gm-home\] \{ display: none !important; \}/);
for(const id of ['voice-toggle','voice-vol','se-toggle','fx-skip','help-btn'])assert.match(html,new RegExp(`id="${id}"`),id);
// skill voice + volume also in the main 설정 window
assert.match(html,/id="main-voice"/); assert.match(html,/id="main-voice-vol"/);
assert.match(game,/\$\('main-voice'\)\?\.addEventListener\('click'/); assert.match(game,/\$\('main-voice-vol'\)\?\.addEventListener\('input'/);
console.log('Unified settings: home/top bar/battle gears → one 게임설정 menu; battle settings kept inside; leave/logout hidden mid-battle OK');
