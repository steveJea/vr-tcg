import { buildMediaManifest } from './build_media_manifest.mjs';
import { buildAssetManifest } from './build_asset_manifest.mjs';
// 운영 Pages는 이 빌드를 사용하지 않음. 웹 자산만 복사 (SQL/tools/docs/비밀파일 제외).
import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
await buildMediaManifest();
const out = path.join(root, '.staging-dist');
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
for (const name of ['index.html', 'admin.html', 'terms.html', 'privacy.html', 'payment-return.html', 'admin-payments.html', 'favicon.ico', 'js', 'css', 'data', 'img', 'audio', 'video']) {
  await cp(path.join(root, name), path.join(out, name), { recursive: true });
}
await writeFile(path.join(out, 'robots.txt'), 'User-agent: *\nDisallow: /\n');
// 기기 캐시: 서비스 워커(sw.js)는 루트에서만 전체 범위를 잡을 수 있음 + 자산 목록(내용 해시)
await cp(path.join(root, 'sw.js'), path.join(out, 'sw.js'));
const assets = await buildAssetManifest(out);
console.log(`기기 캐시 목록: ${Object.keys(assets.files).length}개 · ${(assets.total / 1048576).toFixed(1)}MB · v${assets.v}`);
// 그림·보이스: 기본값(max-age=0, must-revalidate)이면 전투 중 컷인 그림마다 다시 확인 요청이 나감.
// 10분은 그대로 쓰고, 그 뒤 하루는 캐시 것을 바로 쓰면서 뒤에서 새로 확인 (같은 이름으로 교체해도 다음 로드엔 반영).
const MEDIA_CACHE = 'public, max-age=600, stale-while-revalidate=86400';
const mediaRules = ['/data/fx/*', '/data/event/*', '/data/voice/*', '/img/*'].map(p => `${p}\n  Cache-Control: ${MEDIA_CACHE}\n`).join('');
// sw.js·자산 목록은 매번 서버에 확인 (바뀐 배포를 바로 알아차리게)
const swRules = ['/sw.js', '/asset-manifest.json'].map(p => `${p}\n  Cache-Control: no-cache\n`).join('');
await writeFile(path.join(out, '_headers'), '/*\n  X-Robots-Tag: noindex, nofollow\n' + mediaRules + swRules);
console.log('테스트용 웹 자산 준비 완료 (.staging-dist). 운영 Pages에는 영향 없음.');
