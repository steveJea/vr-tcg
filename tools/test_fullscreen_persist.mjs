// 모바일 웹: 전투가 끝나도 전체화면을 유지. PC·iOS 가드는 그대로.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const game = await readFile(new URL('js/game.js', root), 'utf8');
const story = await readFile(new URL('js/story.js', root), 'utf8');

assert.match(game, /requestFullscreen\(\{ navigationUI: 'hide' \}\)/);
assert.match(game, /\(pointer: coarse\) and \(max-width: 767px\)/);
assert.match(game, /userActivation/);
assert.match(game, /fullscreenchange/);
// 전투 화면을 떠난다고 exitFullscreen 을 부르지 않음
assert.doesNotMatch(game, /if \(!vis\) battleFullscreen\(false\)/);
assert.doesNotMatch(game, /d\.exitFullscreen\) d\.exitFullscreen/);
assert.match(game, /on=false 여도 exitFullscreen 하지 않음/);
assert.match(game, /VRMaint\.ensureOk/);
assert.match(game, /async function startGame/);
assert.match(game, /async function viewBattle/);

// 스토리 엔딩 영상: 게임 전체화면(html)을 끄지 않고, 영상 창이 전체화면일 때만 해제
assert.match(story, /if \(el === m\) \(document\.exitFullscreen/);
assert.doesNotMatch(story, /if \(isFs\(\)\) \(document\.exitFullscreen/);

console.log('fullscreen persist tests: OK');
