// 메인 BGM 제스처 언락: 실패해도 리스너를 버리지 않고, hold 중에도 유지, 소리 OFF 는 시도하지 않음.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const src = readFileSync(new URL('../js/main-screen.js', import.meta.url), 'utf8');
assert.match(src, /const tryPlay = /);
assert.match(src, /visibilitychange/);
assert.match(src, /touchstart/);
assert.match(src, /pointerdown/);
assert.doesNotMatch(src, /removeEventListener\('pointerdown'/);
assert.doesNotMatch(src, /const first = \(\) => \{ play\(\); removeEventListener/);
assert.match(src, /if \(!soundOn \|\| held \|\| jingleA\) return Promise\.resolve\(false\)/);
assert.match(src, /held \? stop\(\) : play\(\)/);
assert.match(src, /soundOn \? play\(\) : stop\(\)/);
console.log('ALL OK');
