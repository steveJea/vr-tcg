// Clarity loads only on the production game host, and session masking stays on sensitive UI.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile, readdir} from 'node:fs/promises';
import {parseHTML} from 'linkedom';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');
const index = await read('index.html');
const {document} = parseHTML(index);
const tags = [...document.querySelectorAll('script')].filter(s => s.textContent.includes('zbavh1z42t'));
assert.equal(tags.length, 1, 'one inline Clarity guard');
assert.equal(tags[0].parentElement.tagName, 'HEAD');
assert.equal(document.querySelector('script[src*="clarity.ms"]'), null, 'no unconditional Clarity script');
const code = tags[0].textContent;
assert.match(code, /location\.hostname === "ag\.violenceroyale\.com"/);
assert.match(code, /https:\/\/www\.clarity\.ms\/tag\//);
assert.match(code, /t\.async=1/);
assert.doesNotMatch(code, /clarity\s*\(/);
assert.doesNotMatch(index, /clarity\s*\(\s*['"]identify['"]/);

function load(hostname, hooks = {}) {
  const inserted = [];
  const fakeDocument = {
    createElement: hooks.createElement || (tag => ({ tagName: tag, async: 0, src: '' })),
    getElementsByTagName: hooks.getElementsByTagName || (() => [{ parentNode: { insertBefore(node) { inserted.push(node); } } }]),
  };
  const window = {};
  const location = hostname === undefined ? undefined : { hostname };
  let threw = false;
  try { vm.runInNewContext(code, { window, document: fakeDocument, location }); }
  catch { threw = true; }
  return { window, inserted, threw };
}

for (const host of ['vr-tcg-staging.notcold.workers.dev', 'tcg.mbbs.kr', 'localhost', '127.0.0.1', 'www.ag.violenceroyale.com', 'ag.violenceroyale.com.evil.test', 'notcold.workers.dev', '']) {
  const result = load(host);
  assert.equal(result.threw, false, host);
  assert.equal(result.inserted.length, 0, host);
  assert.equal(result.window.clarity, undefined, host);
}
const on = load('ag.violenceroyale.com');
assert.equal(on.threw, false);
assert.equal(on.inserted.length, 1);
assert.equal(on.inserted[0].async, 1);
assert.equal(on.inserted[0].src, 'https://www.clarity.ms/tag/zbavh1z42t');
assert.equal(typeof on.window.clarity, 'function');
assert.equal(load('ag.violenceroyale.com', { createElement() { throw new Error('blocked'); } }).threw, false);
assert.equal(load('ag.violenceroyale.com', { getElementsByTagName() { return [{}]; } }).threw, false);
assert.equal(load(undefined).threw, false);

function masked(html, re) {
  const found = html.match(re);
  assert(found, String(re));
  assert(found[0].includes('data-clarity-mask="true"'), found[0]);
}
masked(index, /<div id="acct-box"[^>]*>/);
masked(index, /<div class="oauth-row"[^>]*>/);
for (const id of ['main-link-google', 'main-link-kakao', 'main-link-x', 'main-logout']) masked(index, new RegExp(`<button id="${id}"[^>]*>`));

const expect = {
  'js/cloud.js': ['class="oauth-row" data-clarity-mask="true"', 'class="acct-chip" data-clarity-mask="true"', 'class="oauth-card" data-clarity-mask="true"', 'id="nick-box" data-clarity-mask="true"'],
  'js/mypage.js': ['class="mp-guest" data-clarity-mask="true"', 'class="mp-who" data-clarity-mask="true"'],
  'js/shop.js': ['class="shop" data-clarity-mask="true"', "setAttribute('data-clarity-mask', 'true')"],
  'js/gem.js': ['class="gem-panel" data-clarity-mask="true"'],
  'js/payments.js': ["setAttribute('data-clarity-mask','true')"],
  'js/friends.js': ['class="fr-info" data-clarity-mask="true"', 'class="fr-search" data-clarity-mask="true"', 'class="fr-code" data-clarity-mask="true"'],
  'js/trade.js': ['class="tr-input tr-want-in" data-clarity-mask="true"', 'class="tr-want" data-clarity-mask="true"', 'class="tr-dwho" data-clarity-mask="true"', 'class="tr-input tr-dmsg" data-clarity-mask="true"', 'class="tr-gc-want" data-clarity-mask="true"'],
  'js/guild.js': ['id="gd-sn" data-clarity-mask="true"', 'id="gd-si" data-clarity-mask="true"', 'id="gd-ci" data-clarity-mask="true"', 'class="gd-search" data-clarity-mask="true"', 'class="gd-notice" data-clarity-mask="true"'],
  'js/gear.js': ['class="gear-msg-b" data-clarity-mask="true"', 'data-msg="${ml.id}" data-clarity-mask="true"'],
};
for (const [file, parts] of Object.entries(expect)) {
  const text = await read(file);
  for (const part of parts) assert(text.includes(part), file + ' missing ' + part);
  assert.doesNotMatch(text, /clarity\s*\(\s*['"]identify['"]/);
}

for (const page of ['terms.html', 'privacy.html']) {
  const html = await read(page);
  assert.match(html, /default-src 'none'/);
  assert.doesNotMatch(html, /clarity\.ms/);
  assert.doesNotMatch(html, /data-clarity-mask/);
}
for (const page of ['payment-return.html', 'admin.html', 'admin-payments.html']) assert.doesNotMatch(await read(page), /clarity\.ms/);
for (const file of ['worker/media-range.mjs', 'tools/build_staging.mjs', 'tools/build_production_assets.mjs', 'wrangler.jsonc', 'wrangler.production.jsonc']) {
  assert.doesNotMatch(await read(file), /content-security-policy/i, file);
}
const names = await readdir(new URL('js/', root));
for (const name of names) {
  if (!name.endsWith('.js')) continue;
  assert.doesNotMatch(await read('js/' + name), /clarity\s*\(\s*['"]identify['"]/, name);
}
console.log('Clarity: production host only, async, no identify, sensitive UI masked, legal CSP unchanged');
