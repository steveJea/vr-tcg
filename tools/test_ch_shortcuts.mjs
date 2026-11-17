// 로비 챕터 바로가기: 마크업·URL 폴백·잠금/해금·이어하기. 엔진 파일은 건드리지 않음.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile, stat } from 'node:fs/promises';
import { parseHTML } from 'linkedom';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const htmlSrc = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const cssSrc = await readFile(new URL('../css/main-screen.css', import.meta.url), 'utf8');
const menuSrc = await readFile(new URL('../js/main-menu.js', import.meta.url), 'utf8');
const storySrc = await readFile(new URL('../js/story.js', import.meta.url), 'utf8');
const root = path.dirname(fileURLToPath(new URL('../package.json', import.meta.url)));

const storyBtnAt = htmlSrc.indexOf('id="story-btn"');
const rowAt = htmlSrc.indexOf('id="ch-shortcuts"');
const arcadeAt = htmlSrc.indexOf('id="start-btn"');
assert.ok(storyBtnAt > 0 && rowAt > storyBtnAt && arcadeAt > rowAt, '바로가기 줄이 이어하기 CTA 아래, 아케이드 타일 앞에 있어야 해요');
assert.match(htmlSrc, /id="story-hub-btn"/);
assert.match(htmlSrc, /id="ch-shortcuts-track"/);
assert.match(cssSrc, /scroll-snap-type:\s*x mandatory/);
assert.match(cssSrc, /height:\s*clamp\(130px,\s*19svh,\s*190px\)/);
assert.match(cssSrc, /#start-screen:not\(\.is-guest\) #story-btn/);
assert.match(cssSrc, /#start-screen\.is-guest \.ch-shortcuts/);
assert.match(menuSrc, /loading="lazy"/);
assert.match(menuSrc, /ch_bg_pc_/);
assert.match(menuSrc, /playCurrent/);
assert.match(storySrc, /openPage\(\(\) => renderMap\(i\), true\)/);
assert.match(storySrc, /const playCurrent/);
assert.match(storySrc, /await checkChapters\(\)/);
assert.doesNotMatch(menuSrc, /js\/skills\.js/);

for (const n of [16, 17, 18, 19]) {
  const fp = path.join(root, 'img/ui/main', `story_banner_ch${n}.webp`);
  const st = await stat(fp);
  assert.ok(st.size > 10000 && st.size <= 100 * 1024, `${fp} 크기 ${st.size}는 기존 배너 범위가 아니에요`);
}

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
      <div id="ch-shortcuts" class="ch-shortcuts hidden" hidden>
        <div class="ch-shortcuts-head">
          <span class="ch-shortcuts-label">스토리</span>
          <span id="story-hub-btn" class="main-story-hub" role="button" tabindex="0">📜 스토리</span>
        </div>
        <div id="ch-shortcuts-track" class="ch-shortcuts-track"></div>
      </div>
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
const resumes = [];
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
  summary: async () => ({ ok: true, current: { ...chapters[1], phase: 3 }, chapters }),
  openMap: i => maps.push(i),
  playCurrent: () => resumes.push('go'),
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
const track = window.document.getElementById('ch-shortcuts-track');
assert.equal(row.hidden, false);
assert.equal(row.classList.contains('hidden'), false);
assert.ok(window.document.getElementById('story-hub-btn'), '📜 스토리 허브 버튼이 줄 머리에 있어야 해요');
const cards = [...track.querySelectorAll('.ch-short')];
assert.equal(cards.length, 3);
assert.equal(cards[1].classList.contains('cur'), true);
assert.equal(cards[1].dataset.continue, '1');
assert.match(cards[1].textContent, /이어하기/);
assert.equal(cards[2].classList.contains('locked'), true);
assert.equal(cards[2].querySelector('.ch-short-lock')?.textContent, '🔒');
assert.equal(cards[0].querySelector('img').getAttribute('loading'), 'lazy');
assert.match(cards[1].querySelector('b').textContent, /브레이크/);
assert.match(cards[2].querySelector('small').textContent, /CHAPTER 16/);
assert.equal(cards[2].querySelector('img').getAttribute('src'), 'img/ui/main/story_banner_ch16.webp');
assert.ok(cards[2].querySelector('img').dataset.alts.includes('img/story/ch_bg_pc_16.webp'));

cards[1].click();
assert.deepEqual(resumes, ['go'], '현재 챕터는 이어하기(playCurrent)여야 해요');
assert.deepEqual(maps, [], '현재 챕터는 openMap 을 부르면 안 돼요');
cards[0].click();
assert.deepEqual(maps, [0], '다른 열린 챕터는 openMap(i)로 맵을 열어야 해요');
cards[2].click();
assert.deepEqual(maps, [0], '잠긴 챕터는 openMap 을 호출하면 안 돼요');
assert.ok(toasts.some(t => t.includes('이전 챕터')), '잠긴 챕터는 한국어 안내가 떠야 해요');

window.VRCloud.user = null;
await window.VRMainMenu.paintHome();
assert.equal(row.hidden, true);
assert.equal(track.querySelectorAll('.ch-short').length, 0);
assert.ok(window.document.getElementById('story-hub-btn'), '게스트로 숨길 때도 허브 버튼 마크업은 남아야 해요');

console.log('ch shortcuts: CTA hide, continue, lock toast, openMap, ch16-19 banners, guest hide OK');
