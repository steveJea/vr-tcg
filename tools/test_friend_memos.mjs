// 친구 1:1 쪽지(1단계): 가드, 우편 분리, 플래그 기본 OFF, UI 훅, 실페이지 미반영.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { execSync } from 'node:child_process';

const root = new URL('../', import.meta.url);
const read = p => readFile(new URL(p, root), 'utf8');

const staging = await read('supabase/friend_memos_staging.sql');
const production = await read('supabase/friend_memos_production.sql');
const checkS = await read('supabase/friend_memos_check_staging.sql');
const checkP = await read('supabase/friend_memos_check_production.sql');

assert.match(staging, /7703759698107299042/);
assert.match(production, /7692130048193495360/);
assert.doesNotMatch(staging, /7692130048193495360/);
assert.doesNotMatch(production, /7703759698107299042/);
assert.match(staging, /STAGING ONLY/);
assert.match(production, /아직 실행하지 마세요/);
assert.match(production, /PRODUCTION ONLY/);
assert.match(production, /PR #676|release\/2026-11-20/);

for (const sql of [staging, production]) {
  assert.match(sql, /create table if not exists public\.memos/);
  assert.match(sql, /create table if not exists public\.player_blocks/);
  assert.match(sql, /create table if not exists public\.chat_reports/);
  assert.match(sql, /create table if not exists public\.chat_mutes/);
  assert.match(sql, /create table if not exists public\.feature_flags/);
  assert.match(sql, /'friend_memos', false/);
  assert.match(sql, /on conflict \(key\) do nothing/);
  assert.doesNotMatch(sql, /insert into public\.player_mail/);
  assert.doesNotMatch(sql, /into player_mail/);
  assert.match(sql, /enable row level security/);
  assert.match(sql, /revoke all on public\.feature_flags, public\.player_blocks, public\.memos, public\.chat_reports, public\.chat_mutes/);
  assert.match(sql, /_memo_norm/);
  assert.match(sql, /nick_banned/);
  assert.match(sql, /interval '1 second'/);
  assert.match(sql, /interval '1 minute'/);
  assert.match(sql, />= 20/);
  assert.match(sql, /char_length\(body\) between 1 and 200/);
  assert.match(sql, /_memo_blocked/);
  assert.match(sql, /_is_friend/);
  assert.match(sql, /_memo_admin\(\) or public\._memo_flag_on\(\)/);
  assert.match(sql, /interval '30 days'/);
  assert.match(sql, /memo_purge_expired/);
  assert.match(sql, /grant execute on function public\.memo_status\(\)/i);
  assert.doesNotMatch(sql, /grant execute on function public\.memo_purge_expired/);
  assert.match(sql, /admin_feature_flag_set/);
  assert.match(sql, /admin_chat_reports/);
  assert.match(sql, /admin_memo_hide/);
  assert.match(sql, /admin_memo_delete/);
  assert.match(sql, /admin_chat_mute/);
  assert.match(sql, /admin_chat_lift/);
}

assert.match(checkS, /7703759698107299042/);
assert.match(checkP, /7692130048193495360/);
assert.match(checkS, /friend_memos_install_ok/);
assert.match(checkP, /friend_memos_install_ok/);
assert.equal([...checkS.matchAll(/;\s*$/gm)].length, 1);
assert.equal([...checkP.matchAll(/;\s*$/gm)].length, 1);

const js = await read('js/memos.js');
assert.match(js, /friend_memos/);
assert.match(js, /memo_status/);
assert.match(js, /memo_send/);
assert.match(js, /player_block/);
assert.match(js, /chat_report/);
assert.match(js, /stevejean77@gmail\.com/);
assert.doesNotMatch(js, /mail_list|mail_unread|mail_msg_claim/);
assert.doesNotMatch(js, /rpc\('mail_/);

const friends = await read('js/friends.js');
assert.match(friends, /setMemoBadge/);
assert.match(friends, /data-memo/);
assert.match(friends, /VRMemos/);
assert.match(friends, /memo-in/);

const admin = await read('js/admin.js');
assert.match(admin, /data-tab="memos"/);
assert.match(admin, /renderMemos/);
assert.match(admin, /admin_feature_flag_set/);
assert.match(admin, /일반 유저에게 열기/);

const index = await read('index.html');
assert.match(index, /css\/memos\.css/);
assert.match(index, /js\/memos\.js/);

const terms = await read('terms.html');
const privacy = await read('privacy.html');
assert.doesNotMatch(terms, /friend_memos|임시조치 기간은 30일/);
assert.doesNotMatch(privacy, /친구 쪽지/);

const draft = await read('docs/CHAT_TERMS_PRIVACY_DRAFT.md');
assert.match(draft, /임시조치 기간은 30일/);
assert.match(draft, /30일/);
assert.match(draft, /열람/);
assert.match(draft, /미반영/);

const guide = await read('docs/FRIEND_MEMOS_20261120.md');
assert.match(guide, /friend_memos/);
assert.match(guide, /admin_feature_flag_set\('friend_memos', true\)/);

for (const f of ['js/story.js', 'css/story.css', 'data/skills.json', 'data/cards.csv']) {
  const out = execSync(`git diff --name-only -- ${f}`, { cwd: new URL('.', root), encoding: 'utf8' });
  assert.equal(out.trim(), '', `${f} should be untouched`);
}

console.log('ok   friend memos static checks');
