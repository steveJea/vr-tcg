// 보이스 캐시 LRU·전투 미리 받기 범위·VRVoice 해제·도감 오디오 재사용 검사 (2026-11-12 버벅임 대응)
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
const g = await readFile('js/game.js', 'utf8'), v = await readFile('js/voice.js', 'utf8'), gal = await readFile('js/gallery.js', 'utf8');
const section = (a, b) => { const i = g.indexOf(a), j = g.indexOf(b, i); assert(i >= 0 && j > i, a); return g.slice(i, j); };
class FakeAudio { constructor() { this.paused = true; this.src = ''; this.loads = 0; this.ev = {}; } addEventListener(e, f) { (this.ev[e] ||= []).push(f); } removeAttribute(k) { if (k === 'src') this.src = ''; } load() { this.loads++; (this.ev.emptied || []).forEach(f => f()); } fire(e) { (this.ev[e] || []).forEach(f => f()); } pause() { this.paused = true; this.fire("pause"); } }
let clock = 0; const made = [];
const ctx = vm.createContext({ performance: { now: () => clock }, Audio: class extends FakeAudio { constructor() { super(); made.push(this); } }, trackVoice() {}, voiceCur: null, voiceSet: null, voiceCache: new Map(), voicePending: new Map(), skillsOf: () => [{ name: 'a' }, { name: 'b' }] });
vm.runInContext('var voiceCur = null, voiceSet = null; const voiceCache = new Map(), voicePending = new Map();' + section('const VOICE_CACHE_MAX', 'function playVoice(u, name)') + ';this.api={voiceAudio,preloadVoice,preloadSkillVoice,get cache(){return voiceCache},setSet(s){voiceSet=s},setCur(a){voiceCur=a}}', ctx);
const api = ctx.api;
// LRU: 61개 넣고 5초 지나면 가장 오래된 것부터 정리, 다시 쓴 것은 남음
for (let i = 0; i < 60; i++) api.voiceAudio('k' + i);
clock = 10000; const k0 = api.voiceAudio('k0');   // k0 최근 사용으로 승격
clock = 20000; api.voiceAudio('new');
assert.equal(api.cache.size, 60); assert(api.cache.has('k0'), 'recently used kept'); assert(!api.cache.has('k1'), 'oldest evicted');
assert.equal(made[1].src, '', 'evicted audio released'); assert.equal(made[1].loads, 1);
// 재생 중이거나 막 쓴(5초 안) 것은 개수 넘어도 안 지움 → 같은 화면에서 반복 다운로드 없음
clock = 20001; for (let i = 0; i < 10; i++) api.voiceAudio('burst' + i);
assert(api.cache.size >= 60);
const before = made.length; for (let i = 0; i < 10; i++) api.voiceAudio('burst' + i); assert.equal(made.length, before, 'no re-create within keep window');
// 미리 받기: 등장(_0)만 / 스킬은 preloadSkillVoice 로
api.setSet(new Set(['7_0', '7_1', '7_2', '7_9']));
api.preloadVoice([{ id: 7 }]); assert(api.cache.has('7_0')); assert(!api.cache.has('7_1'), 'skill voice not preloaded up front');
api.preloadSkillVoice([{ id: 7 }]); assert(api.cache.has('7_1') && api.cache.has('7_2')); assert(!api.cache.has('7_9'), 'win voice on demand');
assert.match(g, /queueHeavy\(\[\.\.\.visible, \.\.\.next\], \[\.\.\.S\.me\.hand, \.\.\.S\.me\.field\.map/, 'skill voices warmed for my hand + fields (after thumbs)');
// VRVoice: 재생 중인 것만 들고 있음
const w = { performance: { now: () => 0 }, document: { readyState: 'complete', getElementById: () => null, addEventListener() {} }, addEventListener() {}, MutationObserver: class { observe() {} } }; w.window = w;
vm.runInContext(v, vm.createContext(w));
const a = new FakeAudio(); w.VRVoice.track(a); assert.equal(a.playbackRate, 1.15, 'rate unchanged');
a.paused = false; a.fire('play'); a.paused = true; a.fire('ended');
a.paused = false; a.fire('play'); w.VRVoice.stopAll(); assert(a.paused, 'replayed voice still stoppable');
assert.match(v, /\['pause', 'ended', 'error', 'abort', 'emptied'\]\.forEach\(ev => a\.addEventListener\(ev, off\)\)/, 'finished voices released');
assert.doesNotMatch(gal, /new Audio\(`data\/voice/, 'gallery reuses one audio element');
console.log('Voice cache: LRU 60 + keep window, _0-only battle preload, skill voices on hand/field, VRVoice releases finished, gallery single audio OK');
