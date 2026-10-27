import fs from 'fs';
const s = fs.readFileSync('js/quest.js', 'utf8'); let f = 0;
const ok = (n, c) => { console.log((c ? 'PASS ' : 'FAIL ') + n); if (!c) { f++; process.exitCode = 1; } };
ok('보스 층(10의 배수) + 최고 기록일 때만', /bossSw = !!next && isBoss\(n\) && best\(\) === n/.test(s));
ok('VICTORY 화면에 소탕하기 버튼', /id="q-win-sweep"[^`]*소탕하기/.test(s));
ok('기존 sweep() 그대로 호출', /\$\('q-win-sweep'\)\.onclick = \(\) => \{ sel = next; sweep\(\); \}/.test(s));
