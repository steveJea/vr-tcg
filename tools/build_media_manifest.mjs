// ASSETS.fetch() does not guarantee Content-Length inside a Worker. Bundle sizes
// from the exact deployed asset tree instead of buffering entire media files.
import { readdir, stat, readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL, fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
export async function buildMediaManifest({ check = false } = {}) {
  const files = [];
  async function walk(relative) {
    for (const entry of await readdir(path.join(root, relative), { withFileTypes: true })) {
      const name = relative + '/' + entry.name;
      if (entry.isDirectory()) await walk(name);
      else if (entry.isFile() && /\.(mp4|mp3)$/.test(name)) files.push(name);
    }
  }
  for (const name of ['video', 'audio', 'data', 'img']) await walk(name);
  const pairs = await Promise.all(files.sort().map(async name => ['/' + name, (await stat(path.join(root, name))).size]));
  const target = new URL('../worker/media-sizes.json', import.meta.url), source = JSON.stringify(Object.fromEntries(pairs), null, 2) + '\n';
  if (check) {
    if (await readFile(target, 'utf8') !== source) throw Error('media-sizes.json stale: node tools/build_media_manifest.mjs');
  } else await writeFile(target, source);
  return pairs.length;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  console.log(`미디어 크기 목록: ${await buildMediaManifest({ check: process.argv.includes('--check') })}개 OK`);
}
