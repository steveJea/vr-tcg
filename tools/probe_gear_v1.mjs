// supabase/gear_v1.sql 적용 확인 (anon 키만 사용, 권한 키 불필요): node tools/probe_gear_v1.mjs
// 함수: 42501(권한 없음) = 있음 / PGRST202 = 없음.  테이블: 42501 = 있음(잠겨 있음) / PGRST205·42P01 = 없음. 200 이면 anon 에 열려 있음 → 문제
import { readFileSync } from 'fs';
const src = readFileSync(new URL('../js/cloud.js', import.meta.url), 'utf8');
const URL_ = src.match(/SUPABASE_URL = '([^']+)'/)[1], KEY = src.match(/SUPABASE_ANON = '([^']+)'/)[1];
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
const fns = { gear_status: {}, gear_expand: {}, gear_lock: { p_gear: 0, p_locked: true }, gear_equip: { p_gear: 0, p_card: 'x' }, gear_unequip: { p_gear: 0 }, mail_list: {}, mail_claim: { p_id: 0 } };
const tables = ['gear_defs', 'gear_tier_gate', 'gear_slot_price', 'gear_event_grants', 'sigil_defs', 'player_gear', 'player_gear_meta', 'player_sigils', 'player_mail'];
let bad = 0;
for (const [f, body] of Object.entries(fns)) {
  const r = await fetch(`${URL_}/rest/v1/rpc/${f}`, { method: 'POST', headers: H, body: JSON.stringify(body) }); const j = await r.json().catch(() => ({}));
  const st = j.code === '42501' ? '있음 (anon 거부)' : j.code === 'PGRST202' ? '없음' : `확인 필요 ${r.status} ${j.code || ''}`;
  if (j.code !== '42501') bad++; console.log(`rpc  ${f.padEnd(14)} ${st}`);
}
for (const t of tables) {
  const r = await fetch(`${URL_}/rest/v1/${t}?select=*&limit=1`, { headers: H }); const j = await r.json().catch(() => ({}));
  const st = j.code === '42501' ? '있음 (anon 거부)' : ['PGRST205', '42P01'].includes(j.code) ? '없음' : r.ok ? 'anon 에 열림!' : `확인 필요 ${r.status} ${j.code || ''}`;
  if (j.code !== '42501') bad++; console.log(`table ${t.padEnd(17)} ${st}`);
}
console.log(bad ? `\n${bad}개 미적용/확인 필요` : '\n전부 적용됨 (anon 잠김)');
