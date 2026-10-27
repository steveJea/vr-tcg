import fs from 'fs';
const s = fs.readFileSync('js/quest.js', 'utf8'); let f = 0;
const ok = (n, c) => { console.log((c ? 'PASS ' : 'FAIL ') + n); if (!c) { f++; process.exitCode = 1; } };
ok('보스 층(10의 배수) + 최고 기록일 때만', /bossSw = !!next && isBoss\(n\) && best\(\) === n/.test(s));
ok('VICTORY 화면에 소탕하기 버튼', /id="q-win-sweep"[^`]*소탕하기/.test(s));
ok('기존 sweep() 그대로 호출', /\$\('q-win-sweep'\)\.onclick = \(\) => \{ sel = next; sweep\(\); \}/.test(s));
ok('quest_start 성공 후 시작 시각 기록', /return render\(\); \}\n    startedAt = Date\.now\(\);/.test(s));
ok('complete 전에 최소 5.6초 채움 (서버 5초 + 여유)', /MIN_BATTLE_MS = 5600/.test(s) && /startedAt \+ MIN_BATTLE_MS - Date\.now\(\)[^\n]*\n    let res;\n    try \{ res = await trpc\('quest_complete'/.test(s));
