// 기기 캐시(sw.js)용 자산 목록: 경로 → [크기, 내용 해시 8자리]. 빌드 결과 폴더(.staging-dist 등)를 훑어서
// <out>/asset-manifest.json 으로 씀. 같은 이름 파일이 바뀌면 해시가 바뀌어 기기 캐시가 새로 받음.
import { createHash } from 'node:crypto';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
export const ASSET_DIRS = ['js', 'css', 'data', 'img', 'audio', 'video'];
const SKIP = /(^|\/)\.|\.md$|\.DS_Store$/;
async function walk(dir, rel, out) {
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const r = rel + '/' + e.name; if (SKIP.test(r)) continue;
    if (e.isDirectory()) await walk(path.join(dir, e.name), r, out); else if (e.isFile()) out.push(r);
  }
}
export async function buildAssetManifest(outDir) {
  const list = [];
  for (const d of ASSET_DIRS) await walk(path.join(outDir, d), '/' + d, list).catch(e => { if (e.code !== 'ENOENT') throw e; });
  list.sort();
  const files = {}, all = createHash('sha256');
  for (const p of list) {
    const buf = await readFile(path.join(outDir, p.slice(1)));
    const h = createHash('sha256').update(buf).digest('hex').slice(0, 8);
    files[p] = [buf.length, h]; all.update(p + ':' + h + '\n');
  }
  const manifest = { v: all.digest('hex').slice(0, 12), total: list.reduce((n, p) => n + files[p][0], 0), files };
  await writeFile(path.join(outDir, 'asset-manifest.json'), JSON.stringify(manifest));
  return manifest;
}
if (import.meta.url === `file://${process.argv[1]}`) {
  const m = await buildAssetManifest(path.resolve(process.argv[2] || '.staging-dist'));
  console.log(`자산 목록: ${Object.keys(m.files).length}개 · ${(m.total / 1048576).toFixed(1)}MB · v${m.v}`);
}
