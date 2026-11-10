// 시트 36·37·39·40·41·42: 파견 카드는 썸네일+아이콘만, 자동 미리보기는 중복·예상 보상 없음,
// 지역 상세는 Max 와 빠른 파견, 홈은 미파견 칸만 즉시 보내기, 미션은 탭·한번에 받기·플레이 x N.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { parseHTML } from 'linkedom';

const tick = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
const mem = {};
const localStorage = { getItem: k => mem[k] ?? null, setItem: (k, v) => { mem[k] = String(v); } };

function dom() {
  const { window, document } = parseHTML('<html><head></head><body></body></html>');
  window.localStorage = localStorage;
  window.VRIcon = { icon: (name, opts = {}) => `<img class="ui-ic ui-ic-${name} dsp-ic" alt="${opts.alt || ''}">` };
  window.cardThumb = id => `img/thumb/${id}.webp`;
  const noopTimer = () => 0;
  const ctx = vm.createContext({
    window, document, console, Object, Map, Set, Date, Promise, localStorage,
    setTimeout: noopTimer, clearTimeout() {}, setInterval: noopTimer, clearInterval() {},
    MutationObserver: class { observe() {} disconnect() {} },
  });
  return { window, document, ctx };
}

const cards = {
  10001: { name: '성재수', grade: 'NORMAL', class: 'FIRE', attribute: 'CHARGE' },
  10002: { name: '허진서', grade: 'RARE', class: 'FIRE', attribute: 'CHARGE' },
  10003: { name: '이재원', grade: 'NORMAL', class: 'ICE', attribute: 'DEFENSE' },
};
const owned = [
  { uid: 'a', id: '10001', level: 5 },
  { uid: 'b', id: '10001', level: 1 },
  { uid: 'c', id: '10002', level: 2 },
  { uid: 'd', id: '10003', level: 3 },
];
function state() {
  return {
    offers: [
      { slot: 1, zone: 'x001', el: 'FIRE', cls: 'CHARGE', taken: false },
      { slot: 2, zone: 'x002', el: 'ICE', cls: 'DEFENSE', taken: true },
    ],
    runs: [],
    zones: [
      { id: 'x001', grp: 'exile', name: '배척지 001', min_grade: 0, size: 2, rw: { shard: 5, blood: 3 } },
      { id: 'x002', grp: 'exile', name: '배척지 002', min_grade: 1, size: 1, rw: { gold: 500 } },
    ],
    mult: { 1: 1, 4: 3.5, 8: 6, 12: 8.5 },
    slots: 3, cap: 12, starts: 0, refreshes: 0, free: 3, refresh_cost: 0,
  };
}

function loadDispatch(ctx) {
  vm.runInContext(fs.readFileSync('js/dispatch.js', 'utf8'), ctx);
}

{
  const { window, document, ctx } = dom();
  const calls = [];
  let st = state();
  window.VRCloud = { user: { id: 'u' }, sb: { rpc: async (name, args) => { calls.push([name, args]); return { data: st, error: null }; } } };
  window.TCG = { cardById: id => cards[id] };
  loadDispatch(ctx);
  window.VRDispatch._set(st, owned);
  window.VRDispatch._draw();
  const now = [...document.querySelectorAll('.dsp-now')];
  assert.equal(now.length, 1, '미파견 지역만 즉시 보내기');
  assert.equal(now[0].textContent, '즉시 보내기');
  assert.equal(document.querySelectorAll('.dsp-off.taken .dsp-now').length, 0);
  now[0].click();
  await tick();
  assert.equal(calls[0][0], 'dispatch_start');
  assert.equal(calls[0][1].p_slot, 1);
  const sentIds = calls[0][1].p_uids.map(u => owned.find(o => o.uid === u).id);
  assert.equal(new Set(sentIds).size, sentIds.length, '즉시 보내기는 같은 카드를 두 번 보내지 않음');
  assert.ok(sentIds.includes('10001') && sentIds.includes('10002'));

  st = state();
  window.VRDispatch._set(st, owned);
  window.VRDispatch._draw();
  document.querySelector('[data-more="1"]').click();
  const pop = document.querySelector('#dsp-mp');
  assert.ok(pop);
  assert.match(pop.textContent, /Max 2/);
  assert.equal(pop.querySelector('[data-quick]').textContent, '빠른 파견');
  assert.equal(pop.querySelector('.dsp-mpx').textContent, '닫기');
  assert.equal(pop.textContent.includes('보상'), false);
  assert.equal(pop.textContent.includes('맞는 인재'), false);
  assert.equal(pop.textContent.includes('CHARGE'), false);
  assert.equal(pop.textContent.includes('불'), false);
  assert.ok(pop.querySelector('.ui-ic-el_fire'));
  assert.ok(pop.querySelector('.ui-ic-atk'));
  document.querySelector('[data-more="2"]').click();
  assert.equal(document.querySelector('#dsp-mp [data-quick]'), null, '보낸 지역 상세에는 빠른 파견이 없음');

  window.VRDispatch._pick(1);
  const picker = document.querySelector('#dsp-box');
  const text = picker.textContent;
  assert.equal(text.includes('예상'), false);
  assert.equal(text.includes('CHARGE'), false);
  assert.equal(text.includes('불'), false);
  assert.equal(text.includes('조각'), false);
  assert.match(text, /Max 2/);
  const faces = [...picker.querySelectorAll('.dsp-card')];
  assert.equal(faces.length, 3, '같은 카드 사본은 한 장만');
  assert.equal(faces.filter(el => el.getAttribute('aria-label') === '성재수').length, 1);
  assert.equal(faces.find(el => el.getAttribute('aria-label') === '성재수').dataset.u, 'b', '낮은 레벨 사본을 대표로');
  assert.ok(faces[0].querySelector('.dsp-th'));
  assert.ok(faces[0].querySelector('.ui-ic-el_fire, .ui-ic-el_ice'));
  assert.ok(picker.querySelector('.ui-ic-atk'));
  assert.equal(picker.textContent.includes('성재수'), false, '이름은 카드 글자로 보이지 않음');

  window.VRDispatch._set(state(), owned);
  window.VRDispatch._auto();
  const prev = document.querySelector('.dsp-prev');
  assert.ok(prev);
  assert.equal(prev.textContent.includes('조각'), false);
  assert.equal(prev.textContent.includes('골드'), false);
  assert.equal(prev.textContent.includes('CHARGE'), false);
  const thumbs = [...prev.querySelectorAll('.dsp-face > img')].map(img => img.getAttribute('src'));
  assert.equal(thumbs.filter(s => s.includes('10001')).length, 1);
  assert.equal(new Set(thumbs).size, thumbs.length);
  assert.ok(prev.querySelector('.ui-ic-atk'));
  assert.ok(prev.querySelector('.dsp-g'));
}

{
  const { window, document, ctx } = dom();
  const calls = [];
  const claimed = { daily: new Set(), weekly: new Set() };
  const mission = (key, name, goal, prog, reward) => ({ key, name, goal, prog, reward, claimed: false });
  const daily = () => ({
    ok: true, next_reset: new Date(Date.now() + 3600e3).toISOString(), reward_held: false,
    attend: { today: true, step: 1, total: 3, rewards: Array.from({ length: 7 }, () => ({ gold: 1 })) },
    missions: [
      mission('arcade', '아케이드 1판 플레이', 1, 1, { gold: 1000 }),
      mission('win', '전투 3회 승리', 3, 1, { gold: 2000 }),
      mission('story', '스토리 스테이지 2회 클리어', 2, 0, { gold: 1 }),
      mission('tower', '시련의 탑 1회 도전', 1, 0, { gold: 1 }),
      mission('skill', '고유기술 10회 사용', 10, 0, { gold: 1 }),
    ].map(m => ({ ...m, claimed: claimed.daily.has(m.key) })),
    all: { reward: { gem: 30 }, done: 1, goal: 5, claimed: claimed.daily.has('all') },
  });
  const weekly = () => ({
    ok: true, next_reset: new Date(Date.now() + 6 * 86400e3).toISOString(), reward_held: false,
    missions: [
      mission('arcade', '아케이드 7판 플레이', 7, 7, { gold: 8000 }),
      mission('win', '전투 15회 승리', 15, 0, { gold: 1 }),
      mission('story', '스토리 스테이지 10회 클리어', 10, 0, { gold: 1 }),
      mission('tower', '시련의 탑 5회 도전', 5, 0, { gold: 1 }),
      mission('skill', '고유기술 50회 사용', 50, 0, { gold: 1 }),
    ].map(m => ({ ...m, claimed: claimed.weekly.has(m.key) })),
    all: { reward: { gem: 100 }, done: 1, goal: 5, claimed: false },
  });
  window.VRCloud = { user: { id: 'u' }, sb: { rpc: async (name, args) => {
    calls.push([name, args]);
    if (name === 'daily_claim') { claimed.daily.add(args.p_key); return { data: { ...daily(), got: { gold: 1000 } }, error: null }; }
    if (name === 'weekly_claim') { claimed.weekly.add(args.p_key); return { data: { ...weekly(), got: { gold: 8000 } }, error: null }; }
    if (name === 'weekly_status') return { data: weekly(), error: null };
    return { data: daily(), error: null };
  } } };
  vm.runInContext(fs.readFileSync('js/daily.js', 'utf8'), ctx);
  await window.VRDaily.status();
  window.VRDaily.open();
  const tabs = [...document.querySelectorAll('.daily-tab')].map(b => b.textContent.replace(/\d/g, '').trim());
  assert.deepEqual(tabs, ['일일 미션', '주간 미션']);
  assert.equal(document.body.textContent.includes('월간'), false);
  assert.match(document.body.textContent, /아케이드 플레이 x 1/);
  assert.match(document.body.textContent, /전투 승리 x 3/);
  assert.equal(document.body.textContent.includes('1판 플레이'), false);
  assert.equal(document.body.textContent.includes('3회 승리'), false);
  assert.equal(document.querySelector('[data-all-ready]').textContent, '한번에 다 받기');
  document.querySelector('[data-all-ready]').click();
  await tick();
  assert.deepEqual(calls.filter(c => c[0] === 'daily_claim').map(c => c[1].p_key), ['arcade']);
  document.querySelector('[data-tab="weekly"]').click();
  assert.match(document.body.textContent, /아케이드 플레이 x 7/);
  assert.equal(document.body.textContent.includes('아케이드 플레이 x 1'), false);
  assert.equal(document.body.textContent.includes('7판 플레이'), false);
  document.querySelector('[data-all-ready]').click();
  await tick();
  assert.deepEqual(calls.filter(c => c[0] === 'weekly_claim').map(c => c[1].p_key), ['arcade']);
}

{
  const sql = fs.readFileSync('supabase/sheet_36_42.sql', 'utf8');
  assert.match(sql, /아케이드 플레이 x 1/);
  assert.match(sql, /아케이드 플레이 x 7/);
  assert.match(sql, /where dispatch_offers\.taken = false/);
  assert.match(sql, /slot = s and taken/);
  const src = fs.readFileSync('supabase/dispatch.sql', 'utf8');
  assert.match(src, /where dispatch_offers\.taken = false/);
  assert.equal(src.includes("name\":\"아케이드 1판"), false);
}

console.log('sheet 36-42 ok');
