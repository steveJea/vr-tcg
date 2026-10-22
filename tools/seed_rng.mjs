// 테스트 전용: Math.random 을 고정 시드 난수로 바꿔 결과가 매번 같게 (게임 코드는 그대로).
// 각 테스트 파일에서 다른 import 보다 먼저 import 해야 js/skills.js 의 기본 rng(Math.random)도 시드 난수를 잡음.
// 시드 바꾸기: TEST_SEED=123 node tools/test_xxx.mjs (tools/seed_rng.mjs)
const seed0 = Number(process.env.TEST_SEED ?? 20261022) >>> 0;
let s = seed0;
Math.random = () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };   // mulberry32
export const TEST_SEED = seed0;
