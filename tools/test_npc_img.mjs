import fs from 'fs'; let f = 0; const ok = (n, c) => { console.log((c ? 'PASS ' : 'FAIL ') + n); if (!c) { f++; process.exitCode = 1; } };
const big = fs.readdirSync('img/npc').filter(x => x.endsWith('.webp') && !/^21000000/.test(x) && fs.statSync('img/npc/' + x).size > 100000);
ok('img/npc 엑스트라 초상화 100KB 이하', !big.length);
const s = fs.readFileSync('js/story.js', 'utf8');
ok('대사 초상화 미리 받기·디코드', /new Image\(\);[^\n]*decode\?\.\(\)/.test(s));
