import assert from 'node:assert/strict';
import worker, { parseRange, ifRangeMatches, sliceBody } from '../worker/media-range.mjs';
// Node lacks workerd's FixedLengthStream; enforce byte counts in the unit shim.
// The integration suite below also runs the real workerd implementation.
globalThis.FixedLengthStream = class {
  constructor(length) {
    let count = 0;
    const stream = new TransformStream({
      transform(chunk, ctl) { count += chunk.byteLength; assert.ok(count <= length); ctl.enqueue(chunk); },
      flush() { assert.equal(count, length); },
    });
    this.readable = stream.readable; this.writable = stream.writable;
  }
};
for (const [text, size, expected] of [
  ['bytes=0-1', 100, [0, 1]], ['bytes=4-', 100, [4, 99]], ['bytes=-2', 100, [98, 99]],
  ['bytes=-999', 100, [0, 99]], ['bytes=98-999', 100, [98, 99]],
  ['bytes=100-', 100, false], ['bytes=-0', 100, false], ['bytes=0-1', 0, false],
  ['bytes=999999999999999999999999999-', 100, false],
  ['bytes=0-999999999999999999999999999', 100, [0, 99]],
  ['bytes=-999999999999999999999999999', 100, [0, 99]],
  ['bytes=10-9', 100, null], ['items=0-1', 100, null], ['bytes=0-1,4-5', 100, null],
  ['bytes=-', 100, null], ['bytes=a-1', 100, null], ['bytes=1e3-', 100, null],
  ['', 100, null], [null, 100, null], ['bytes=' + '9'.repeat(300) + '-', 100, null],
]) assert.deepEqual(parseRange(text, size), expected, String(text));
const validators = new Headers({ etag: '"strong"', 'last-modified': 'Sun, 08 Nov 2026 00:00:00 GMT' });
assert.equal(ifRangeMatches('"strong"', validators), true);
for (const value of ['"other"', 'W/"strong"', 'bad', 'Sat, 07 Nov 2026 00:00:00 GMT']) assert.equal(ifRangeMatches(value, validators), false);
assert.equal(ifRangeMatches('Sun, 08 Nov 2026 00:00:00 GMT', validators), true);
assert.equal(ifRangeMatches('Sun, 08 Nov 2026 00:00:00 GMT', new Headers()), false);
const bytes = Uint8Array.from({ length: 1024 }, (_, i) => i % 251);
async function run({ url = '/video/opening.mp4', method = 'GET', headers = {}, status = 200, encoding, noLength = false } = {}) {
  let cancelled = false, reads = 0, forwarded;
  const pending = [];
  const response = await worker.fetch(new Request('https://example.test' + url, { method, headers }), {
    ASSETS: { async fetch(req) {
      forwarded = req;
      const h = new Headers({ 'content-type': url.endsWith('.mp3') ? 'audio/mpeg' : 'video/mp4', etag: '"strong"', 'last-modified': validators.get('last-modified'), 'cache-control': 'public, max-age=0, must-revalidate' });
      if (!noLength) h.set('content-length', String(bytes.length));
      if (encoding) h.set('content-encoding', encoding);
      let offset = 0;
      const body = method === 'HEAD' || status === 304 ? null : new ReadableStream({
        pull(ctl) {
          reads++;
          if (offset >= bytes.length) { ctl.close(); return; }
          const end = Math.min(offset + 128, bytes.length); ctl.enqueue(bytes.slice(offset, end)); offset = end;
        }, cancel() { cancelled = true; },
      });
      return new Response(body, { status, headers: h });
    } },
  }, { waitUntil(promise) { pending.push(promise); } });
  return { response, forwarded, pending, cancelled: () => cancelled, reads: () => reads };
}
for (const [url, value, start, end] of [
  ['/video/opening.mp4', 'bytes=0-1', 0, 1], ['/video/story/ch1.mp4', 'bytes=99-200', 99, 200],
  ['/data/fx/mr/10060_1.mp4', 'bytes=500-', 500, 1023], ['/img/gacha/video/v1/a.mp4', 'bytes=-17', 1007, 1023],
  ['/audio/a.mp3', 'bytes=12-25', 12, 25], ['/data/voice/a.mp3', 'bytes=0-999999', 0, 1023],
]) {
  const r = await run({ url, headers: { Range: value } });
  assert.equal(r.response.status, 206, url);
  assert.equal(r.response.headers.get('content-range'), `bytes ${start}-${end}/1024`);
  assert.equal(r.response.headers.get('content-length'), String(end - start + 1));
  assert.equal(r.response.headers.get('accept-ranges'), 'bytes');
  assert.equal(r.response.headers.get('etag'), '"strong"');
  assert.equal(r.forwarded.headers.get('range'), null);
  assert.equal(r.forwarded.headers.get('if-range'), null);
  assert.equal(r.forwarded.headers.get('accept-encoding'), 'identity');
  assert.deepEqual(new Uint8Array(await r.response.arrayBuffer()), bytes.slice(start, end + 1));
  await Promise.all(r.pending); if (end < bytes.length - 1) assert.equal(r.cancelled(), true);
  if (end === 1) assert.ok(r.reads() <= 2, 'no whole-file read for a two-byte range');
}
for (const value of ['bytes=1024-', 'bytes=-0']) {
  const r = await run({ headers: { Range: value } });
  assert.equal(r.response.status, 416); assert.equal(r.response.headers.get('content-range'), 'bytes */1024');
  assert.equal((await r.response.arrayBuffer()).byteLength, 0); assert.equal(r.cancelled(), true);
}
for (const headers of [{}, { Range: 'bytes=3-2' }, { Range: 'bytes=0-1,7-9' }, { Range: 'items=0-1' }, { Range: 'bytes=0-1', 'If-Range': '"stale"' }]) {
  const r = await run({ headers }); assert.equal(r.response.status, 200);
  assert.equal(r.response.headers.get('content-range'), null);
  assert.deepEqual(new Uint8Array(await r.response.arrayBuffer()), bytes);
}
const match = await run({ headers: { Range: 'bytes=0-1', 'If-Range': '"strong"' } });
assert.equal(match.response.status, 206); await match.response.arrayBuffer(); await Promise.all(match.pending);
const head = await run({ method: 'HEAD', headers: { Range: 'bytes=0-1' } });
assert.equal(head.response.status, 200); assert.equal(head.response.headers.get('content-length'), '1024'); assert.equal(await head.response.text(), '');
for (const status of [304, 404, 500]) {
  const r = await run({ status, headers: { Range: 'bytes=0-1', 'If-None-Match': '"strong"' } });
  assert.equal(r.response.status, status); assert.equal(r.forwarded.headers.get('if-none-match'), '"strong"');
  assert.equal(r.pending.length, 0); await r.response.body?.cancel();
}
for (const option of [{ url: '/index.html' }, { method: 'POST' }, { encoding: 'gzip' }, { url: '/video/not-in-manifest.mp4', noLength: true }]) {
  const r = await run({ ...option, headers: { Range: 'bytes=0-1' } });
  assert.equal(r.response.status, 200); assert.equal(r.pending.length, 0); await r.response.body?.cancel();
}
const missingHeader = await run({ noLength: true, headers: { Range: 'bytes=0-1' } });
assert.equal(missingHeader.response.status, 206, 'build manifest supplies missing ASSETS length');
assert.deepEqual(new Uint8Array(await missingHeader.response.arrayBuffer()), bytes.slice(0, 2));
await Promise.all(missingHeader.pending);
const cancelled = await run({ headers: { Range: 'bytes=0-1023' } });
const reader = cancelled.response.body.getReader(); await reader.read(); await reader.cancel('test-client-disconnect'); await Promise.all(cancelled.pending);
assert.equal(cancelled.cancelled(), true, 'client cancellation reaches asset body');
const short = sliceBody(new ReadableStream({ start(ctl) { ctl.enqueue(new Uint8Array(1)); ctl.close(); } }), 0, 2);
await assert.rejects(new Response(short).arrayBuffer(), /declared length/);
console.log('미디어 Range: 단일/접미/경계/조건부/416/취소/스트리밍 OK');
