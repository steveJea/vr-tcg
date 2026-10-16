// ===== 계정 + 클라우드 저장 (Supabase) =====
// 로그아웃 상태는 기존과 동일하게 게스트(브라우저 저장)로 플레이.
// Supabase 접속 실패 시 조용히 게스트 모드로 동작.
const SUPABASE_URL = 'https://htarwisgkkphutxxnuak.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0YXJ3aXNna2twaHV0eHhudWFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNTMwOTgsImV4cCI6MjEwNzcyOTA5OH0.xaIda-o8QwRhoG5yDRLAcMo8LbU1rNHUA7xznO-tEfc';
const SDK = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
const REDIRECT = location.hostname === 'tcg.mbbs.kr' ? 'https://tcg.mbbs.kr/' : location.origin + location.pathname;

// 클라우드에 동기화할 localStorage 키 (전적 + 설정)
const STATS_KEY = 'vrTcgStats.v1';
const SYNC_KEYS = [STATS_KEY, 'vrTcgSkipFx', 'vrTcgVoiceOn', 'vrTcgVoiceVol', 'vrTcgSound', 'tcg_hand_sort', 'tcg_skip_endturn_confirm', 'vrTutorialDone'];

let sb = null, user = null, ready = false, pushTimer = null, applying = false;
const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function readLocal() {
  const o = {};
  for (const k of SYNC_KEYS) { const v = localStorage.getItem(k); if (v !== null) o[k] = v; }
  return o;
}
function parseStats(v) { try { return { wins: 0, losses: 0, draws: 0, ...JSON.parse(v || '{}') }; } catch { return { wins: 0, losses: 0, draws: 0 }; } }

// 첫 로그인 병합: 설정은 클라우드 우선(없으면 로컬), 전적은 항목별 큰 값
function merge(local, cloud) {
  const out = { ...local, ...cloud };
  if (local[STATS_KEY] || cloud[STATS_KEY]) {
    const a = parseStats(local[STATS_KEY]), b = parseStats(cloud[STATS_KEY]);
    out[STATS_KEY] = JSON.stringify({ wins: Math.max(a.wins, b.wins), losses: Math.max(a.losses, b.losses), draws: Math.max(a.draws, b.draws) });
  }
  return out;
}
function applyLocal(data) {
  applying = true;
  try { for (const k of SYNC_KEYS) if (typeof data[k] === 'string') localStorage.setItem(k, data[k]); } finally { applying = false; }
}

async function push() {
  if (!sb || !user) return;
  try { await sb.from('saves').upsert({ user_id: user.id, data: readLocal(), updated_at: new Date().toISOString() }); }
  catch (e) { console.warn('[cloud] save failed', e); }
}
function schedulePush() { if (!user) return; clearTimeout(pushTimer); pushTimer = setTimeout(push, 1500); }

// 동기화 대상 키가 바뀌면 자동 업로드 (game.js 수정 최소화)
const origSet = Storage.prototype.setItem;
Storage.prototype.setItem = function (k, v) {
  origSet.call(this, k, v);
  if (this === localStorage && !applying && SYNC_KEYS.includes(k)) schedulePush();
};

async function syncOnLogin() {
  try {
    const { data, error } = await sb.from('saves').select('data').eq('user_id', user.id).maybeSingle();
    if (error) throw error;
    const merged = merge(readLocal(), data?.data || {});
    applyLocal(merged);
    await push();
  } catch (e) { console.warn('[cloud] sync failed', e); }
}

async function loadProfile() {
  const meta = user.user_metadata || {};
  let p = { nickname: meta.name || meta.full_name || (user.email || '').split('@')[0] || '플레이어', avatar_url: meta.avatar_url };
  try {
    const { data } = await sb.from('profiles').select('nickname, avatar_url').eq('id', user.id).maybeSingle();
    if (data) p = data;
    else await sb.from('profiles').upsert({ id: user.id, nickname: p.nickname.slice(0, 20), avatar_url: p.avatar_url });
  } catch {}
  return p;
}

function render(p) {
  const box = $('acct-box'); if (!box) return;
  if (!ready) { box.innerHTML = ''; return; }
  if (!user) {
    box.innerHTML = `<button id="acct-login" class="main-btn main-btn-sub w-full">🔑 구글로 로그인 <span class="text-[11px] opacity-70">(전적 저장)</span></button>`;
    $('acct-login').onclick = login;
  } else {
    const av = p?.avatar_url ? `<img src="${esc(p.avatar_url)}" alt="" referrerpolicy="no-referrer" class="w-6 h-6 rounded-full">` : '👤';
    box.innerHTML = `<div class="flex items-center justify-between gap-2 px-3 py-2 rounded-xl bg-black/40 text-sm text-amber-100">
      <span class="flex items-center gap-2 truncate">${av}<span class="truncate">${esc(p?.nickname)}님</span><span class="text-[11px] text-emerald-300">☁️ 저장 중</span></span>
      <button id="acct-logout" class="text-xs underline opacity-80 hover:opacity-100 shrink-0">로그아웃</button></div>`;
    $('acct-logout').onclick = logout;
  }
}

async function login() {
  if (!sb) return alert('지금은 로그인 서버에 연결할 수 없어요. 게스트로 플레이해 주세요.');
  const { error } = await sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: REDIRECT } });
  if (error) alert('로그인을 시작하지 못했어요: ' + error.message);
}
async function logout() {
  try { await push(); await sb.auth.signOut(); } catch {}
  user = null; render();
}

// 판 결과 기록 (game.js가 'vr:match' 이벤트 발생)
window.addEventListener('vr:match', async e => {
  if (!sb || !user) return;
  const m = e.detail || {};
  try {
    await sb.from('matches').insert({
      user_id: user.id, result: m.result, reason: m.reason ? String(m.reason).slice(0, 20) : null,
      turns: m.turns | 0, damage: Math.max(0, m.damage | 0), skills: m.skills | 0,
      mvp_id: m.mvpId ? String(m.mvpId).slice(0, 40) : null, mvp_name: m.mvpName ? String(m.mvpName).slice(0, 40) : null,
      merc_id: m.mercId ? String(m.mercId).slice(0, 40) : null,
    });
  } catch (err) { console.warn('[cloud] match save failed', err); }
});

async function init() {
  try {
    const mod = await Promise.race([import(SDK), new Promise((_, r) => setTimeout(() => r(new Error('timeout')), 8000))]);
    sb = mod.createClient(SUPABASE_URL, SUPABASE_ANON, { auth: { persistSession: true, detectSessionInUrl: true, flowType: 'pkce' } });
    const { data } = await sb.auth.getSession();
    ready = true;
    const onUser = async u => {
      const isNew = u && u.id !== user?.id;
      user = u || null;
      if (!user) return render();
      render({ nickname: '불러오는 중...' });
      if (isNew) await syncOnLogin();
      render(await loadProfile());
    };
    await onUser(data?.session?.user);
    sb.auth.onAuthStateChange((_ev, session) => { if ((session?.user?.id || null) !== (user?.id || null)) onUser(session?.user); });
    // OAuth 콜백 파라미터 정리
    if (/[?&]code=|access_token=/.test(location.search + location.hash)) history.replaceState(null, '', location.pathname);
  } catch (e) {
    console.warn('[cloud] Supabase 연결 실패 - 게스트 모드', e);
    sb = null; ready = false; render();
  }
}
window.VRCloud = { get user() { return user; }, login, logout, push };
init();
