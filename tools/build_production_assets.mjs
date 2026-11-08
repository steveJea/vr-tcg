import { buildMediaManifest } from './build_media_manifest.mjs';
// Hosting-only build: copy the same web allowlist as staging, never SQL/tools/DB.
import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
await buildMediaManifest();
const out = path.join(root, '.production-dist');
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
for (const name of ['index.html', 'admin.html', 'terms.html', 'privacy.html', 'favicon.ico', 'js', 'css', 'data', 'img', 'audio', 'video']) {
  await cp(path.join(root, name), path.join(out, name), { recursive: true });
}
// Only the candidate workers.dev host is noindex. This is not a TEST badge,
// staging robots.txt, or a global production-domain search exclusion.
await writeFile(path.join(out, '_headers'), 'https://vr-tcg-prod.notcold.workers.dev/*\n  X-Robots-Tag: noindex, nofollow\n');
console.log('운영 콘텐츠 후보 준비 완료 (.production-dist). DNS/Pages/DB 변경 없음.');
