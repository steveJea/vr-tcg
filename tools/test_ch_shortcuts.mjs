// 로비 챕터 바로가기: 마크업·URL 폴백·잠금/해금 동작. 엔진 파일은 건드리지 않음.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { parseHTML } from 'linkedom';

const htmlSrc = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const cssSrc = await readFile(new URL('../css/main-screen.css', import.meta.url), 'utf8');
const menuSrc = await readFile(new URL('../js/main-menu.js', import.meta.url), 'utf8');
const storySrc = await readFile(new URL('../js/story.js', import.meta.url), 'utf8');

const storyBtnAt = htmlSrc.indexOf('id="story-btn"');
const rowAt = htmlSrc.indexOf('id="ch-shortcuts"');
const arcadeAt = htmlSrc.indexOf('id="start-btn"');
assert.ok(storyBtnAt > 0 && rowAt > storyBtnAt && arcadeAt > rowAt, '바로가기 줄이 이어하기 CTA 아래, 아케이드 타일 앞에 있어야 해요');
assert.match(cssSrc, /scroll-snap-type:\s*x mandatory/);
assert.match(cssSrc, /height:\s*clamp\(80px,\s*10svh,\s*100px\)/);
assert.match(cssSrc, /#start-screen\.is-guest \.ch-shortcuts/);
assert.match(menuSrc, /loading="lazy"/);
assert.match(menuSrc, /ch_bg_pc_/);
assert.match(menuSrc, /openMap/);
assert.match(storySrc, /openPage\(\(\) => renderMap\(i\), true\)/);
assert.match(storySrc, /await checkChapters\(\)/);
assert.doesNotMatch(menuSrc, /js\/skills\.js/);

const fixture = `<!doctype html><html><body>
  <div id="intro" class="hidden"><video id="intro-video"></video>
    <button id="intro-login"></button><button id="intro-login-kakao"></button>
    <button id="intro-login-x"></button><button id="intro-guest"></button>
    <div class="oauth-row"></div></div>
  <div id="vr-confirm" class="hidden"><div id="vr-confirm-msg"></div>
    <button data-yn="y">Y</button><button data-yn="n">N</button></div>
  <div id="start-screen">
    <div id="acct-box"></div>
    <div id="main-cur"></div>
    <button id="main-logout" class="hidden"></button>
    <button id="main-settings"></button>
    <div id="main-menu-pop" class="hidden"><div class="gm-grid"></div><div id="gm-foot"></div></div>
    <button id="main-settings-open"></button>
    <button id="main-tutorial" class="hidden"></button>
    <div id="notice-line" class="hidden"><span id="notice-text"></span></div>
    <div class="main-menu main-grid">
      <button id="story-btn" data-auth data-mode="story">
        <img src="img/ui/v2/btn_story.webp" data-alt="img/ui/main/story_banner.webp" alt="">
        <small id="main-cta-sub">STORY</small>
      </button>
      <div id="ch-shortcuts" class="ch-shortcuts hidden" hidden></div>
      <button id="start-btn"></button>
    </div>
    <button id="tab-home"></button>
    <button id="tab-talent"></button>
  </div>
  <div id="game" class="hidden"></div>
</body></html>`;

const { window } = parseHTML(fixture);
const store = new Map([['vrTcgIntroSeen', '1']]);
const toasts = [];
const maps = [];
const chapters = [
  { i: 0, id: 0, title: 'CHAPTER 0', subtitle: '공허한 여신', done: 5, total: 5, open: true, lockWhy: '', bg: '0', variant: null },
  { i: 1, id: 1, title: 'CHAPTER 1', subtitle: '브레이크', done: 2, total: 5, open: true, lockWhy: '', bg: '1_10111', variant: '10111' },
  { i: 16, id: 16, title: 'CHAPTER 16', subtitle: '젊은 베르테르의 슬픔', done: 0, total: 12, open: false, lockWhy: '이전 챕터를 클리어하면 열려요', bg: '16', variant: null },
];
window.VRCloud = { user: { id: 'tester' }, ready: true };
window.__NOTICE_MOCK = async () => [];
window.VRPlayer = { status: async () => ({ level: 20 }), wallet: async () => ({ gold: 10 }) };
window.VRGem = { status: async () => ({ gem: 1 }), toast: t => toasts.push(t) };
window.VRStory = {
  summary: async () => ({ ok: true, current: chapters[1], chapters }),
  openMap: i => maps.push(i),
  api: { toast: t => toasts.push(t) },
};
window.Image = class { constructor() { this.onload = null; this.onerror = null; } set src(v) { this._src = v; queueMicrotask(() => this.onload && this.onload()); } get src() { return this._src; } };
const localStorage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
const ctx = vm.createContext({
  window, document: window.document, console, localStorage,
  navigator: { userAgent: 'test' }, performance: { now: () => 0 },
  setTimeout, clearTimeout, setInterval, clearInterval,
  addEventListener() {}, requestAnimationFrame: f => f(),
  getComputedStyle: () => ({ display: 'block' }),
  location: { search: '', hash: '', pathname: '/' },
  matchMedia: () => ({ matches: false, addEventListener() {} }),
  MutationObserver: class { observe() {} disconnect() {} },
  Image: window.Image,
  URL, fetch: async () => ({ json: async () => ({}) }),
});
// linkedom window needs the same globals the script touches
Object.assign(window, { localStorage, matchMedia: ctx.matchMedia, setTimeout, clearTimeout, setInterval, clearInterval, Image: window.Image });
vm.runInContext(menuSrc, ctx);

const urls1 = window.VRMainMenu.chBannerSrcs(chapters[1]);
assert.deepEqual(urls1[0], 'img/ui/main/story_banner_ch1_10111.webp');
assert.ok(urls1.includes('img/ui/main/story_banner_ch1.webp'));
assert.ok(urls1.includes('img/story/ch_bg_pc_1_10111.webp'));
assert.equal(urls1.at(-1), 'img/ui/main/story_banner.webp');

const urls16 = window.VRMainMenu.chBannerSrcs(chapters[2]);
assert.equal(urls16[0], 'img/ui/main/story_banner_ch16.webp');
assert.ok(urls16.includes('img/story/ch_bg_pc_16.webp'));
assert.ok(urls16.includes('img/story/ch_bg_16.webp'));
assert.equal(urls16.at(-1), 'img/ui/main/story_banner.webp');
assert.ok(!urls16.some(u => u.includes('ch16_')), '변형 없는 챕터는 variant 경로가 없어야 해요');

await window.VRMainMenu.paintHome();
const row = window.document.getElementById('ch-shortcuts');
assert.equal(row.hidden, false);
assert.equal(row.classList.contains('hidden'), false);
const cards = [...row.querySelectorAll('.ch-short')];
assert.equal(cards.length, 3);
assert.equal(cards[1].classList.contains('cur'), true);
assert.equal(cards[2].classList.contains('locked'), true);
assert.equal(cards[2].querySelector('.ch-short-lock')?.textContent, '🔒');
assert.equal(cards[0].querySelector('img').getAttribute('loading'), 'lazy');
assert.match(cards[1].querySelector('b').textContent, /브레이크/);
assert.match(cards[2].querySelector('small').textContent, /CHAPTER 16/);
assert.ok(cards[2].querySelector('img').dataset.alts.includes('img/story/ch_bg_pc_16.webp'));

cards[1].click();
assert.deepEqual(maps, [1], '열린 챕터는 openMap(i)로 맵을 열어야 해요');
cards[2].click();
assert.deepEqual(maps, [1], '잠긴 챕터는 openMap 을 호출하면 안 돼요');
assert.ok(toasts.some(t => t.includes('이전 챕터')), '잠긴 챕터는 한국어 안내가 떠야 해요');

window.VRCloud.user = null;
await window.VRMainMenu.paintHome();
assert.equal(row.hidden, true);
assert.equal(row.querySelectorAll('.ch-short').length, 0);

console.log('ch shortcuts: banner fallback, lock toast, openMap, guest hide OK');
