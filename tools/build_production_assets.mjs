import { buildMediaManifest } from './build_media_manifest.mjs';
import { buildAssetManifest } from './build_asset_manifest.mjs';
// Hosting-only build: copy the same web allowlist as staging, never SQL/tools/DB.
import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
await buildMediaManifest();
const out = path.join(root, '.production-dist');
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
// robots.txt·sitemap.xml·네이버 소유확인 파일: ag 운영 도메인 검색 등록용 (운영 robots는 Allow)
for (const name of ['index.html', 'admin.html', 'terms.html', 'privacy.html', 'favicon.ico', 'robots.txt', 'sitemap.xml', 'naver34493a6b3ecfab810dabeb7bd30674d1.html', 'naver3f65526c87e433092cebf702df729832.html', 'js', 'css', 'data', 'img', 'audio', 'video']) {
  await cp(path.join(root, name), path.join(out, name), { recursive: true });
}
// 기기 캐시 (#593·#595~#597, 스테이징과 같은 규칙): 서비스 워커는 루트에서만 전체 범위 + 자산 목록(내용 해시)
await cp(path.join(root, 'sw.js'), path.join(out, 'sw.js'));
const assets = await buildAssetManifest(out);
console.log(`기기 캐시 목록: ${Object.keys(assets.files).length}개 · ${(assets.total / 1048576).toFixed(1)}MB · v${assets.v}`);
// 그림·보이스 (#582): 10분은 그대로 쓰고, 그 뒤 하루는 캐시 것을 바로 쓰며 뒤에서 새로 확인. sw.js·자산 목록은 매번 서버 확인.
const MEDIA_CACHE = 'public, max-age=600, stale-while-revalidate=86400';
const mediaRules = ['/data/fx/*', '/data/event/*', '/data/voice/*', '/img/*'].map(p => `${p}\n  Cache-Control: ${MEDIA_CACHE}\n`).join('');
const swRules = ['/sw.js', '/asset-manifest.json'].map(p => `${p}\n  Cache-Control: no-cache\n`).join('');
// Only the candidate workers.dev host is noindex. This is not a TEST badge,
// staging robots.txt, or a global production-domain search exclusion.
await writeFile(path.join(out, '_headers'), 'https://vr-tcg-prod.notcold.workers.dev/*\n  X-Robots-Tag: noindex, nofollow\n' + mediaRules + swRules);
console.log('운영 콘텐츠 후보 준비 완료 (.production-dist). DNS/Pages/DB 변경 없음.');
