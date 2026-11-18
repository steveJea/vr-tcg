// 로비 챕터 바로가기 ↔ 실제 스토리 진행: 신규·챕터0 중간·챕터0 완료+챕터1 중간·후반 챕터.
// 진행이 바뀐 뒤 로비로 돌아오면 바로가기가 최신 진행으로 다시 그려져야 함 (예전: 로그인 때 한 번만 그려 1챕터가 잠긴 채 남음).
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile, readdir } from 'node:fs/promises';
import { parseHTML } from 'linkedom';

const root = new URL('..', import.meta.url);
const read = rel => readFile(new URL(rel, root), 'utf8');
const dataFiles = ['js/story-data.js', ...(await readdir(new URL('js/', root))).filter(f => /^story-data-ch\d+\.js$/.test(f)).sort((a, b) => parseInt(a.match(/\d+/)) - parseInt(b.match(/\d+/))).map(f => 'js/' + f)];
const { window } = parseHTML(`<!doctype html><html><body>
  <div id="intro" class="hidden"><video id="intro-video"></video><button id="intro-login"></button><button id="intro-login-kakao"></button>
    <button id="intro-login-x"></button><button id="intro-login-naver"></button><button id="intro-guest"></button><div class="oauth-row"></div></div>
  <div id="vr-confirm" class="hidden"><div id="vr-confirm-msg"></div><button data-yn="y">Y</button><button data-yn="n">N</button></div>
  <div id="start-screen">
    <div id="acct-box"></div><div id="main-cur"></div><button id="main-logout" class="hidden"></button><button id="main-settings"></button>
    <div id="main-menu-pop" class="hidden"><div class="gm-grid"></div><div id="gm-foot"></div></div><button id="main-settings-open"></button>
    <button id="main-tutorial" class="hidden"></button><div id="notice-line" class="hidden"><span id="notice-text"></span></div>
    <div class="main-menu main-grid">
      <button id="story-btn" data-auth data-mode="story"><img src="img/ui/v2/btn_story.webp" data-alt="img/ui/main/story_banner.webp" alt=""><small id="main-cta-sub">STORY</small></button>
      <div id="ch-shortcuts" class="ch-shortcuts hidden" hidden><div class="ch-shortcuts-head"><span class="ch-shortcuts-label">스토리</span><span id="story-hub-btn" class="main-story-hub" role="button" tabindex="0">📜 스토리</span></div>
        <div class="ch-shortcuts-wrap"><button type="button" class="ch-short-arrow ch-short-l" data-ch-move="-1" disabled>‹</button>
          <div id="ch-shortcuts-vp" class="ch-shortcuts-vp"><div id="ch-shortcuts-track" class="ch-shortcuts-track"></div></div><button type="button" class="ch-short-arrow ch-short-r" data-ch-move="1" disabled>›</button></div></div>
      <button id="start-btn"></button></div>
    <button id="tab-home"></button><button id="tab-talent"></button>
  </div>
  <div id="story-screen" class="hidden"></div><div id="game" class="hidden"></div></body></html>`);
const store = new Map([['vrTcgIntroSeen', '1']]);
const localStorage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
class FakeImage { set src(v) { this._src = v; } get src() { return this._src; } }
const toasts = [];
const ctx = vm.createContext({
  window, document: window.document, console, localStorage, navigator, performance, crypto,
  setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {}, addEventListener() {}, removeEventListener() {},
  requestAnimationFrame: f => f(), getComputedStyle: () => ({ display: 'block' }),
  history: { pushState() {}, replaceState() {}, back() {} }, location: { search: '', hash: '', pathname: '/' },
  matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }),
  innerWidth: 390, innerHeight: 844, Image: FakeImage, MutationObserver: window.MutationObserver, URL, fetch: async () => ({ json: async () => ({}) }),
});
Object.assign(window, { localStorage, Image: FakeImage });
window.TCG = { ready: true, POOL: [], NPC: [], skillsOf: () => [], RULES: { MAX_TURNS: 40 } };
window.VRCloud = { user: { id: 'tester' }, ready: true };
window.__NOTICE_MOCK = async () => [];
window.VRPlayer = { status: async () => ({ level: 3 }), wallet: async () => ({ gold: 10 }) };
window.cardThumb = id => `img/x/${id}.webp`;
for (const f of dataFiles) vm.runInContext(await read(f), ctx);
vm.runInContext(await read('js/story.js'), ctx);
window.VRStory.api.toast = t => toasts.push(t);
vm.runInContext(await read('js/main-menu.js'), ctx);
const D = window.STORY_DATA;
const all = c => c.phases.map(p => p.no);
const ch = id => D.chapters.find(c => c.id === id);
const setSave = s => store.set('vrTcgStory.v1:tester', JSON.stringify({ v: 1, owned: [], points: 0, statV: 2, cleared: {}, ...s }));
const hero = (id = '10265') => ({ openingSeen: true, startSeen: true, ch0Pull: true, starter: id, owned: [{ uid: 'u1', id, level: 1, boost: {} }], leader: 'u1' });
const tick = (ms = 120) => new Promise(r => setTimeout(r, ms));
const cards = () => [...window.document.querySelectorAll('#ch-shortcuts-track .ch-short')];
const card = id => cards().find(b => (b.querySelector('small')?.textContent || '').match(new RegExp(`^CHAPTER ${id}\\b`)));
const cur = () => cards().find(b => b.classList.contains('cur'));
const scr = window.document.getElementById('start-screen');
// 로비 → 스토리 → 로비 (story.js home() 와 같은 클래스 토글)
const backToLobby = async () => { scr.classList.add('hidden'); await tick(10); scr.classList.remove('hidden'); await tick(); };

// 1) 신규 (캐릭터 고르기 전, 챕터 0 시작 전)
setSave({});
await window.VRMainMenu.paintHome();
assert.equal(cur()?.querySelector('small').textContent.startsWith('CHAPTER 0'), true, '신규: 현재 칸 = 챕터 0');
assert.equal(card(1).classList.contains('locked'), true, '신규: 챕터 1 잠김');
assert.match(card(1).querySelector('b').textContent, /BRUTAL CITY/, '신규: 시작 캐릭터 전이라 기본 부제');

// 2) 챕터 0 중간
setSave({ cleared: { 0: all(ch(0)).slice(0, 2) } });
await backToLobby();
assert.match(cur().querySelector('small').textContent, /^CHAPTER 0/);
assert.equal(card(1).classList.contains('locked'), true, '챕터 0 중간: 챕터 1 잠김');

// 3) 형님 상황: 챕터 0 전부 + 용지혜(10265) 1-1·1-2 클리어. 로비로 돌아오기만 해도 다시 그려져야 함
setSave({ ...hero(), cleared: { 0: all(ch(0)), 1: [1, 2] } });
await backToLobby();
const c1 = card(1);
assert.equal(c1.classList.contains('locked'), false, '챕터 1이 열려 있어야 해요');
assert.equal(c1.classList.contains('cur'), true, '현재 칸 = 챕터 1');
assert.equal(c1.dataset.continue, '1');
assert.match(c1.querySelector('small').textContent, /CHAPTER 1 · PHASE 3/);
assert.match(c1.querySelector('b').textContent, /개미굴/, '루트 부제(개미굴)');
assert.match(c1.textContent, /이어하기/);
assert.equal(card(0).classList.contains('locked'), false, '깬 챕터 0은 열림');
assert.equal(card(2).classList.contains('locked'), true, '챕터 2는 잠김');
const shot3 = window.document.getElementById('ch-shortcuts').outerHTML;

// 3-b) 예전 그림이 남아 있어도 잠긴 칸을 누르면 최신 진행으로 다시 확인 후 들어감
setSave({});
await window.VRMainMenu.paintHome();
assert.equal(card(1).classList.contains('locked'), true);
setSave({ ...hero(), cleared: { 0: all(ch(0)), 1: [1, 2] } });
let played = 0; const pc = window.VRStory.playCurrent; window.VRStory.playCurrent = () => { played++; };
toasts.length = 0; card(1).click(); await tick();
assert.equal(played, 1, '잠금이 풀렸으면 바로 이어하기');
assert.equal(toasts.length, 0, '풀린 챕터에 잠금 안내가 뜨면 안 돼요');
window.VRStory.playCurrent = pc;

// 4) 후반: 0~3 전부, 4 중간
const cl = {}; for (const c of D.chapters) if (c.id <= 3) cl[c.id] = all(c); cl[4] = [1];
setSave({ ...hero('10111'), cleared: cl });
await backToLobby();
assert.match(cur().querySelector('small').textContent, /^CHAPTER 4/);
for (const id of [0, 1, 2, 3]) assert.equal(card(id).classList.contains('locked'), false, `깬 챕터 ${id} 열림`);
assert.equal(card(4).classList.contains('locked'), false);
assert.equal(card(5).classList.contains('locked'), true, '다음 챕터 잠김');
toasts.length = 0; card(5).click(); await tick();
assert.ok(toasts.some(t => /이전 챕터/.test(t)), '진짜 잠긴 챕터는 안내');

console.log('ch shortcuts progress: fresh / mid ch0 / ch0 done + ch1 mid (repaint on lobby return, 개미굴, continue) / later chapters OK');
if (process.argv.includes('--html')) console.log(shot3);
