import MEDIA_SIZES from './media-sizes.json' with { type: 'json' };
// Static media only: no DB, API proxy, credentials or runtime game rules.
// Workers Static Assets ignore Range, so slice the identity representation as a
// bounded-memory stream. FixedLengthStream makes Content-Length correct on workerd.
export function parseRange(value, size) {
  if (!value || value.length > 256) return null; // Ignore unsupported/malformed ranges.
  const m = /^bytes=(\d*)-(\d*)$/i.exec(value.trim());
  if (!m || (!m[1] && !m[2])) return null; // Multiple ranges: RFC permits a full 200.
  const n = BigInt(size);
  if (!m[1]) {
    const suffix = BigInt(m[2]);
    if (suffix === 0n || n === 0n) return false;
    return [Number(suffix >= n ? 0n : n - suffix), size - 1];
  }
  const start = BigInt(m[1]), end = m[2] ? BigInt(m[2]) : n - 1n;
  if (m[2] && end < start) return null;
  if (start >= n) return false;
  return [Number(start), Number(end >= n ? n - 1n : end)];
}
export function ifRangeMatches(value, headers) {
  if (!value) return true;
  if (value.startsWith('"')) return value === headers.get('etag');
  if (value.startsWith('W/')) return false;
  const modified = headers.get('last-modified');
  return !!modified && Number.isFinite(Date.parse(value)) && Date.parse(value) === Date.parse(modified);
}
export function sliceBody(body, start, end) {
  const reader = body.getReader(); let offset = 0;
  return new ReadableStream({
    async pull(controller) {
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) throw Error('media ended before its declared length');
          const before = offset; offset += value.byteLength;
          if (offset <= start) continue;
          const from = Math.max(0, start - before), to = Math.min(value.byteLength, end + 1 - before);
          controller.enqueue(value.subarray(from, to));
          if (offset > end) { controller.close(); await reader.cancel(); }
          return;
        }
      } catch (error) { controller.error(error); await reader.cancel(error).catch(() => {}); }
    },
    cancel(reason) { return reader.cancel(reason); },
  });
}
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (!/\.(mp4|mp3)$/i.test(url.pathname) || !['GET', 'HEAD'].includes(request.method)) return env.ASSETS.fetch(request);
    // Apply normal preconditions first. Never forward Range/If-Range to the
    // assets binding or splice a compressed representation with identity offsets.
    const input = new Headers(request.headers);
    input.delete('range'); input.delete('if-range'); input.set('accept-encoding', 'identity');
    const asset = await env.ASSETS.fetch(new Request(request, { headers: input }));
    if (asset.status !== 200 || (asset.headers.get('content-encoding') && asset.headers.get('content-encoding') !== 'identity')) return asset;
    const rawLength = asset.headers.get('content-length');
    let pathname; try { pathname = decodeURIComponent(url.pathname); } catch { return asset; }
    const size = rawLength === null ? MEDIA_SIZES[pathname] : Number(rawLength);
    if (!Number.isSafeInteger(size) || size < 0) return asset;
    const headers = new Headers(asset.headers); headers.set('accept-ranges', 'bytes');
    headers.set('content-length', String(size));
    const range = request.method === 'GET' && ifRangeMatches(request.headers.get('if-range'), headers) ? parseRange(request.headers.get('range'), size) : null;
    if (range === null) return new Response(asset.body, { status: asset.status, headers });
    headers.delete('content-encoding'); headers.delete('content-md5'); headers.delete('digest');
    if (range === false) {
      if (asset.body) await asset.body.cancel();
      headers.set('content-range', `bytes */${size}`); headers.set('content-length', '0');
      return new Response(null, { status: 416, headers });
    }
    if (!asset.body) return asset;
    const [start, end] = range, length = end - start + 1;
    headers.set('content-range', `bytes ${start}-${end}/${size}`); headers.set('content-length', String(length));
    // Do not cache partial bytes under the full-asset URL. The ASSETS binding
    // retains its own cache; validators and Content-Type are preserved.
    const fixed = new FixedLengthStream(length);
    ctx.waitUntil(sliceBody(asset.body, start, end).pipeTo(fixed.writable).catch(error => {
      console.warn(JSON.stringify({ tag: 'media-range', error: error?.name || 'stream-error' }));
    }));
    return new Response(fixed.readable, { status: 206, headers });
  },
};
