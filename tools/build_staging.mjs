import { buildMediaManifest } from './build_media_manifest.mjs';
// 운영 Pages는 이 빌드를 사용하지 않음. 웹 자산만 복사 (SQL/tools/docs/비밀파일 제외).
import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
await buildMediaManifest();
const out = path.join(root, '.staging-dist');
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
for (const name of ['index.html', 'admin.html', 'terms.html', 'privacy.html', 'favicon.ico', 'js', 'css', 'data', 'img', 'audio', 'video']) {
  await cp(path.join(root, name), path.join(out, name), { recursive: true });
}
await writeFile(path.join(out, 'robots.txt'), 'User-agent: *\nDisallow: /\n');
await writeFile(path.join(out, '_headers'), '/*\n  X-Robots-Tag: noindex, nofollow\n');
console.log('테스트용 웹 자산 준비 완료 (.staging-dist). 운영 Pages에는 영향 없음.');
