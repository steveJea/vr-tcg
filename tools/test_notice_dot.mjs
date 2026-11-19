// 전체 소식: 5초 폴링을 없애고, 로그인·홈 복귀·화면 이동·탭 복귀(60초) 때만 확인.
// 안 본 소식이 있으면 나팔에 빨간 점, 창을 열면 지워지고 last-seen 을 localStorage에 남김. 토스트는 안 뜸.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';

const root = new URL('..', import.meta.url);
const src = await readFile(new URL('js/notice-global.js', root), 'utf8');
assert.equal(src.includes('setInterval'), false, 'notice-global.js 에 setInterval 이 없어야 해요');
assert.match(src, /dataset\.unread/);
assert.match(src, /vrGnSeen:/);
assert.equal(/toast\(/.test(src), false, '일반 소식 토스트를 띄우면 안 돼요');

const { parseHTML } = await import('linkedom');
const { window } = parseHTML(`<!doctype html><html><body>
  <div id="start-screen"></div>
  <div id="game" class="hidden"></div>
</body></html>`);
const store = new Map();
const localStorage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
const intervals = [];
const rpcCalls = [];
const notices = [
  { id: 10, uid: 'other', nick: '다른사람', card_id: '10001', grade: 'UR', src: 'daily', created_at: new Date().toISOString(), me: false },
  { id: 9, uid: 'me', nick: '나', card_id: '10002', grade: 'MR', src: 'ticket', created_at: new Date().toISOString(), me: true },
];
const tick = (ms = 30) => new Promise(r => setTimeout(r, ms));
Object.defineProperty(window.document, 'hidden', { configurable: true, get: () => window.document.visibilityState === 'hidden' });
window.document.visibilityState = 'visible';

const ctx = vm.createContext({
  window, document: window.document, console, localStorage,
  setTimeout, clearTimeout,
  setInterval: (...a) => { intervals.push(a); return 0; },
  clearInterval() {},
  addEventListener: (...a) => window.addEventListener(...a),
  removeEventListener: (...a) => window.removeEventListener(...a),
  MutationObserver: window.MutationObserver, cardThumb: id => `img/x/${id}.webp`,
});
Object.assign(window, { localStorage, cardThumb: id => `img/x/${id}.webp` });
window.VRCloud = { user: { id: 'tester' }, ready: true };
window.__NOTICE_MOCK = async (fn, args) => { rpcCalls.push({ fn, args, at: Date.now() }); return { ok: true, notices: notices.slice() }; };
vm.runInContext(src, ctx);

assert.equal(intervals.length, 0, '스크립트 로드 때 setInterval 이 돌면 안 돼요');

await window.VRNotice.start();
await tick(40);
const btn = window.document.getElementById('gn-btn');
assert.ok(btn, '나팔 버튼이 있어야 해요');
assert.equal(btn.dataset.unread, '1', '안 본 소식이 있으면 빨간 점');
assert.equal(btn.getAttribute('data-n'), null, '숫자 배지는 쓰지 않아요');
assert.equal(window.document.getElementById('gn-toasts'), null, '접속 때 토스트가 뜨면 안 돼요');
assert.equal(rpcCalls.length, 1, '로그인 때 한 번만 확인');
assert.equal(rpcCalls[0].fn, 'global_notice_list');
assert.equal('p_after' in (rpcCalls[0].args || {}), false);

btn.click();
assert.ok(window.document.querySelector('.gn-log'), '소식 창이 열려야 해요');
assert.equal(btn.dataset.unread, undefined, '창을 열면 빨간 점이 사라져야 해요');
assert.equal(localStorage.getItem('vrGnSeen:tester'), '10', '마지막 본 id 를 기억해야 해요');
assert.equal(window.document.querySelector('.gn-toasts, #gn-toasts'), null);
window.document.querySelector('.gn-x').click();
assert.equal(window.document.querySelector('.gn-log'), null);

const afterOpen = rpcCalls.length;
await window.VRNotice.poll();
await tick(20);
assert.equal(btn.dataset.unread, undefined, '이미 본 소식은 점이 다시 안 떠요');
assert.equal(rpcCalls.length, afterOpen + 1);

notices.unshift({ id: 11, uid: 'other', nick: '새소식', card_id: '10003', grade: 'LR', src: 'event', created_at: new Date().toISOString(), me: false });
window.VRNotice._setLastPollAt(Date.now() - 2500);
const scr = window.document.getElementById('start-screen');
scr.classList.add('hidden'); await tick(20);
scr.classList.remove('hidden'); await tick(40);
assert.equal(btn.dataset.unread, '1', '홈이 다시 보일 때 새 소식을 확인해 빨간 점이 떠요');

const beforeFocus = rpcCalls.length;
window.document.dispatchEvent(new window.Event('visibilitychange'));
window.dispatchEvent(new window.Event('focus'));
await tick(20);
assert.equal(rpcCalls.length, beforeFocus, '60초 안이면 탭 복귀·포커스로 다시 묻지 않아요');

window.VRNotice._setLastPollAt(Date.now() - 61000);
window.document.dispatchEvent(new window.Event('visibilitychange'));
await tick(20);
assert.equal(rpcCalls.length, beforeFocus + 1, '60초가 지나면 탭 복귀 때 다시 확인해요');

const beforeNav = rpcCalls.length;
window.dispatchEvent(new window.Event('hashchange'));
await tick(20);
assert.equal(rpcCalls.length, beforeNav, '방금 확인했으면 화면 이동으로 바로 다시 묻지 않아요');
window.VRNotice._setLastPollAt(Date.now() - 2500);
window.dispatchEvent(new window.Event('hashchange'));
await tick(20);
assert.equal(rpcCalls.length, beforeNav + 1, '조금 지난 뒤 화면 이동이면 다시 확인해요');

assert.equal(intervals.length, 0, '테스트 중에도 5초 타이머가 생기면 안 돼요');
assert.equal(window.document.querySelector('#gn-toasts, .gn-toast'), null, '새 소식이 와도 토스트는 안 떠요');

console.log('notice red dot: no 5s poll, start/home/nav/focus hooks, badge + last-seen, no toast OK');
