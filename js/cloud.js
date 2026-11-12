// ===== 계정 + 클라우드 저장 (Supabase) =====
// 로그아웃 상태는 기존과 동일하게 게스트(브라우저 저장)로 플레이.
// Supabase 접속 실패 시 조용히 게스트 모드로 동작.
import { config } from './config.js';
import { ensureConsent } from './consent.js';
import { OAUTH_PROVIDERS, profileSeed, hasIdentity, oauthRequest, discoverOAuthProviders, cleanOAuthCallback, readOAuthCallback, saveLinkIntent, takeLinkIntent, oauthErrorCode, oauthFailureMessage, resolveOAuthReturn } from './auth-oauth.js';
const SUPABASE_URL = config.supabaseUrl;
const SUPABASE_ANON = config.anonKey;
const SDK = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
const REDIRECT = location.hostname === 'tcg.mbbs.kr' ? 'https://tcg.mbbs.kr/' : location.origin + location.pathname;

// 클라우드에 동기화할 localStorage 키 (전적 + 설정)
const STATS_KEY = 'vrTcgStats.v1';
// 아케이드 전적은 동기화하지 않음 (게스트 기록이 계정에 섞이지 않게). 계정 전적은 검증 서버에서 집계
const SYNC_KEYS = ['vrTcgSkipFx', 'vrTcgVoiceOn', 'vrTcgVoiceVol', 'vrTcgSound', 'tcg_hand_sort', 'tcg_skip_endturn_confirm', 'vrTutorialDone'];

let sb = null, user = null, profile = null, ready = false, pushTimer = null, applying = false;
let oauthProviders = { kakao:false, x:null };
let oauthBusy = false, oauthTimer = null, userVersion = 0;
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

async function syncOnLogin(uid) {
  try {
    const { data, error } = await sb.from('saves').select('data').eq('user_id', uid).maybeSingle();
    if (error) throw error;
    if (user?.id !== uid) return;
    const merged = merge(readLocal(), data?.data || {});
    applyLocal(merged);
    await push();
  } catch (e) { console.warn('[cloud] sync failed', e); }
}

// 계정 아케이드 전적 = 검증 서버 arcade_record_v5 집계 (스토리 전투는 기록 안 됨). 실패하면 기존 계정 캐시 유지
async function loadRecord() {
  if (!sb || !user) return;
  const uid = user.id;
  try {
    const {data, error}=await sb.rpc('arcade_record_v5'); if(error)throw error;
    const {wins,losses,draws}=data;
    if (user?.id !== uid) return;
    origSet.call(localStorage, `vrTcgStats.v5:${uid}`, JSON.stringify({ wins, losses, draws }));
  } catch (e) { console.warn('[cloud] 전적 불러오기 실패', e?.message || e); }
  window.dispatchEvent(new CustomEvent('vr:user'));
}
const fireUser = () => window.dispatchEvent(new CustomEvent('vr:user'));

async function loadProfile(u) {
  let p = profileSeed(u);
  try {
    let { data, error } = await sb.from('profiles').select('nickname, avatar_url, nick_set').eq('id', u.id).maybeSingle();
    if (error) ({ data } = await sb.from('profiles').select('nickname, avatar_url').eq('id', u.id).maybeSingle());   // nickname.sql 실행 전
    if (data) p = { ...p, ...data, nickname: typeof data.nickname === 'string' && data.nickname.trim() ? data.nickname : p.nickname };
    else if (user?.id === u.id) {
      const { error: insertError } = await sb.from('profiles').upsert({ id: u.id, nickname: p.nickname, avatar_url: p.avatar_url });
      if (!insertError) p.nick_set = false;
    }
  } catch {}
  return p;
}

function render(p) {
  const box = $('acct-box'); if (!box) return;
  if (!ready) { paintOAuth(); box.innerHTML = ''; return; }
  if (!user) {
    box.innerHTML = `<div class="oauth-row" data-clarity-mask="true"><button id="acct-login" type="button" class="main-btn acct-login" data-oauth-provider="google">구글 로그인</button><button id="acct-login-kakao" type="button" class="main-btn acct-login oauth-kakao" data-oauth-provider="kakao" aria-label="카카오 로그인" hidden><img src="img/ui/kakao-symbol.svg" class="oauth-symbol" width="18" height="18" alt="">로그인</button><button id="acct-login-x" type="button" class="main-btn acct-login oauth-x" data-oauth-provider="x" hidden>X 로그인</button></div>`;
    $('acct-login').onclick = () => login('google');
    $('acct-login-kakao').onclick = () => login('kakao');
    $('acct-login-x').onclick = () => login('x');
  } else {
    const av = p?.avatar_url
      ? `<img src="${esc(p.avatar_url)}" alt="" referrerpolicy="no-referrer" class="acct-avatar" onerror="this.onerror=null;this.src='img/ui/profile.webp'">`
      : `<img src="img/ui/profile.webp" alt="" class="acct-avatar">`;
    box.innerHTML = `<div class="acct-chip" data-clarity-mask="true" title="로그인됨 · 진행 상황이 클라우드에 저장 중">
      ${av}<span class="acct-name">${esc(p?.nickname)}님</span>
      <button id="acct-logout" type="button" class="acct-logout">로그아웃</button></div>`;
    $('acct-logout').onclick = logout;
  }
  paintOAuth();
}

const notify = message => (window.VRGem?.toast || alert)(message);
const backendProvider = provider => ['x', 'twitter'].includes(provider) ? oauthProviders.x : provider;
const canLogin = provider => !!sb && ready && (provider === 'google' || (provider === 'kakao' && oauthProviders.kakao) || (['x', 'twitter'].includes(provider) && !!oauthProviders.x));
function paintOAuth() {
  document.querySelectorAll('[data-oauth-provider]').forEach(button => {
    button.hidden = button.dataset.oauthProvider !== 'google' && !canLogin(button.dataset.oauthProvider);
    button.disabled = oauthBusy || !ready;
  });
  for (const provider of ['google', 'kakao', 'x']) {
    const button = $('main-link-' + provider);
    if (!button) continue;
    button.hidden = !user || !canLogin(provider) || hasIdentity(user, backendProvider(provider));
    button.disabled = oauthBusy;
    button.onclick = () => linkProvider(provider);
  }
  window.dispatchEvent(new CustomEvent('vr:auth-providers'));
}
function chooseLogin() {
  if (document.getElementById('oauth-choose')) return;
  const ov = document.createElement('div'); ov.id = 'oauth-choose'; ov.className = 'oauth-overlay';
  ov.innerHTML = `<div class="oauth-card" data-clarity-mask="true" role="dialog" aria-modal="true" aria-labelledby="oauth-title"><h2 id="oauth-title">로그인</h2><div class="oauth-row"><button type="button" class="main-btn" data-oauth-provider="google">구글 로그인</button><button type="button" class="main-btn oauth-kakao" data-oauth-provider="kakao"><img src="img/ui/kakao-symbol.svg" class="oauth-symbol" width="18" height="18" alt="">카카오 로그인</button><button type="button" class="main-btn oauth-x" data-oauth-provider="x" hidden>X 로그인</button></div><button type="button" class="main-btn oauth-close">닫기</button></div>`;
  const close = () => { ov.remove(); document.removeEventListener('keydown', onKey); };
  const onKey = e => { if (e.key === 'Escape') close(); };
  ov.querySelectorAll('[data-oauth-provider]').forEach(b => { b.onclick = () => { close(); login(b.dataset.oauthProvider); }; });
  ov.querySelector('.oauth-close').onclick = close;
  ov.onclick = e => { if (e.target === ov) close(); };
  document.addEventListener('keydown', onKey); document.body.append(ov); paintOAuth(); ov.querySelector('button').focus();
}
async function startOAuth(provider, linking) {
  if (!Object.hasOwn(OAUTH_PROVIDERS, provider) || oauthBusy) return;
  if (!canLogin(provider)) return notify('지금은 이 로그인을 사용할 수 없어요.');
  provider = backendProvider(provider);
  const uid = user?.id;
  if (linking && (!uid || hasIdentity(user, provider))) return;
  if (!linking && uid) return; // Never switch/replace a signed-in account by accident.
  oauthBusy = true; paintOAuth();
  try {
    if (linking) {
      const question = `현재 계정에 ${OAUTH_PROVIDERS[provider]} 로그인을 연결할까요? 이미 따로 가입한 계정은 합쳐지지 않아요.`;
      const yes = window.VRConfirm ? await window.VRConfirm(question) : window.confirm(question);
      if (!yes || user?.id !== uid) return;
    }
    if (linking) {
      try { saveLinkIntent(sessionStorage, SUPABASE_URL, { uid, provider }); }
      catch { return notify('브라우저 저장 기능을 켠 뒤 다시 시도해 주세요.'); }
    }
    const request = oauthRequest(provider, REDIRECT);
    const result = await (linking ? sb.auth.linkIdentity(request) : sb.auth.signInWithOAuth(request));
    if (result.error) throw result.error;
    // Keep a double click from replacing the PKCE verifier while navigating.
    oauthTimer = setTimeout(() => { oauthTimer = null; oauthBusy = false; paintOAuth(); }, 10000);
  } catch (e) {
    if (linking) takeLinkIntent(sessionStorage, SUPABASE_URL);
    const code = oauthErrorCode(e);
    notify(code ? oauthFailureMessage(code, linking ? {provider} : null) : linking ? '로그인을 연결하지 못했어요. 기존 계정은 그대로예요.' : '로그인을 시작하지 못했어요. 다시 시도해 주세요.');
  } finally {
    if (!oauthTimer) { oauthBusy = false; paintOAuth(); }
  }
}
async function login(provider) {
  if (user) return;
  if (!sb || !ready) return notify('지금은 로그인 서버에 연결할 수 없어요.');
  if (provider === undefined) { if (canLogin('kakao') || canLogin('x')) return chooseLogin(); provider = 'google'; }
  return startOAuth(provider, false);
}
async function linkProvider(provider) { return startOAuth(provider, true); }
async function logout() {
  try { await push(); await sb.auth.signOut(); } catch {}
  takeLinkIntent(sessionStorage, SUPABASE_URL);
  clearTimeout(oauthTimer); oauthTimer = null; oauthBusy = false; ++userVersion; document.getElementById('nick-ov')?.remove(); document.getElementById('consent-ov')?.remove(); user = null; profile = null; render(); fireUser();
}

// Arcade records are settled by arcade-verify-v5, never by a browser vr:match event.

async function init() {
  // 미등록 주소·아직 준비 안 된 테스트 DB는 SDK/로그인/DB 요청 자체를 시작하지 않음.
  if (!config.enabled) { render(); return; }
  // Snapshot BEFORE SDK init: older auth-js treats PKCE error fragments as an
  // invalid flow and can discard the valid signed-in session on link conflict.
  const callback = readOAuthCallback(location);
  const linkIntent = takeLinkIntent(sessionStorage, SUPABASE_URL);
  if (callback.failed) cleanOAuthCallback(location, history);
  try {
    const mod = await Promise.race([import(SDK), new Promise((_, r) => setTimeout(() => r(new Error('timeout')), 8000))]);
    sb = mod.createClient(SUPABASE_URL, SUPABASE_ANON, { auth: { persistSession: true, detectSessionInUrl: true, flowType: 'pkce' } });
    const { error: initError } = await sb.auth.initialize();
    const { data } = await sb.auth.getSession();
    const returned = await resolveOAuthReturn(sb.auth, callback, linkIntent, data?.session?.user || null, initError);
    if (returned.retry) saveLinkIntent(sessionStorage, SUPABASE_URL, linkIntent);
    ready = true;
    const onUser = async u => {
      const isNew = u && u.id !== user?.id;
      const version = ++userVersion;
      if ((u?.id || null) !== (user?.id || null)) document.getElementById('nick-ov')?.remove();
      user = u || null; profile = null;
      fireUser();
      if (!u) return render();
      loadRecord();
      render({ nickname: '불러오는 중...' });
      if (isNew) await syncOnLogin(u.id);
      if (version !== userVersion) return;
      const nextProfile = await loadProfile(u);
      if (version !== userVersion) return;
      profile = nextProfile; render(profile);
      // 첫 로그인 동의 (js/consent.js): 현재 버전 동의가 없으면 게임 전에 한 번. 동의 안 함 → 로그아웃(게스트)
      if (!await ensureConsent(sb, u, { onDecline: logout })) return;
      if (version !== userVersion) return;
      if (profile && profile.nick_set === false) askNickname(true);
    };
    // Register before profile I/O: account changes must invalidate old responses.
    sb.auth.onAuthStateChange((ev, session) => {
      if ((session?.user?.id || null) !== (user?.id || null)) void onUser(session?.user);
      // INITIAL_SESSION / same-UUID SIGNED_IN can carry stale cached identities.
      // Keep getUser()'s authoritative result until a genuine server update.
      else if (session?.user && ['USER_UPDATED', 'TOKEN_REFRESHED'].includes(ev)) { user = session.user; render(profile); }
    });
    void discoverOAuthProviders(config).then(providers => { oauthProviders = providers; paintOAuth(); });
    await onUser(returned.user);
    // Successful PKCE exchange is owned by SDK.initialize(), exactly once.
    cleanOAuthCallback(location, history);
    if (returned.message) notify(returned.message);
  } catch (e) {
    console.warn('[cloud] Supabase 연결 실패 - 게스트 모드', e);
    sb = null; ready = false; render();
  }
}
// ===== 닉네임 (supabase/nickname.sql: set_nickname / nickname_check) =====
const NICK_ERR = { short: '2글자 이상 입력해 주세요', long: '12글자까지 가능해요', bad: '한글·영문·숫자·공백·_ . - 만 쓸 수 있어요', taken: '이미 누가 쓰고 있는 닉네임이에요', banned: '쓸 수 없는 단어가 들어 있어요', same: '지금 닉네임과 같아요', gem: '심연석이 부족해요 (변경 1회 200개)' };
const NICK_PRICE = 200;   // supabase/nickname_v2.sql _nick_price() 와 같은 값 (첫 설정은 무료)
const nickErr = m => { const k = (/nick (\w+)/.exec(m || '') || [])[1]; return NICK_ERR[k] || '저장하지 못했어요. 잠시 후 다시 시도해 주세요'; };
function askNickname(first) {
  if (!user || document.getElementById('nick-ov')) return Promise.resolve(null);
  if (!document.getElementById('nick-css')) { const c = document.createElement('style'); c.id = 'nick-css'; c.textContent = `
  #nick-ov{position:fixed;inset:0;z-index:9500;background:rgba(0,0,0,.78);display:flex;align-items:center;justify-content:center;padding:16px}
  #nick-box{width:100%;max-width:360px;background:linear-gradient(#1e1530,#0e0a18);border:1px solid rgba(251,191,36,.45);border-radius:16px;color:#fde68a;padding:18px 16px 14px;box-shadow:0 10px 40px rgba(0,0,0,.6)}
  #nick-box h3{margin:0 0 6px;font-size:18px}#nick-box p{margin:0 0 12px;font-size:12px;opacity:.85;line-height:1.5}
  #nick-box input{width:100%;box-sizing:border-box;padding:11px 12px;border-radius:10px;border:1px solid rgba(251,191,36,.45);background:rgba(0,0,0,.35);color:#fff;font-size:16px}
  #nick-box .nk-msg{min-height:18px;margin:6px 2px 10px;font-size:12px}#nick-box .nk-msg.bad{color:#fca5a5}#nick-box .nk-msg.good{color:#86efac}
  #nick-box .nk-btns{display:flex;gap:8px}#nick-box button{flex:1;padding:11px;border-radius:10px;border:1px solid rgba(251,191,36,.35);background:rgba(0,0,0,.3);color:#fde68a;font-weight:800;font-size:15px;cursor:pointer}
  #nick-box button.go{background:#f59e0b;color:#1a1200}#nick-box button:disabled{opacity:.5}`; document.head.appendChild(c); }
  const cur = profile?.nick_set ? profile.nickname : '', paid = !first && !!profile?.nick_set;
  const ov = document.createElement('div'); ov.id = 'nick-ov';
  ov.innerHTML = `<div id="nick-box" data-clarity-mask="true" role="dialog" aria-label="닉네임"><h3>${first ? '닉네임을 정해 주세요' : '닉네임 변경'}</h3>
    <p>2~12글자 · 다른 사람과 겹칠 수 없어요${paid ? `<br><b>변경할 때마다 🔮 심연석 ${NICK_PRICE}개가 들어요</b>` : first ? '<br>처음 한 번은 무료예요' : ''}</p>
    <input maxlength="12" autocomplete="off" spellcheck="false" placeholder="닉네임" value="${esc(cur)}"><div class="nk-msg"></div>
    <div class="nk-btns">${first ? '' : '<button class="no" type="button">취소</button>'}<button class="go" type="button">${first ? '시작하기' : paid ? `🔮${NICK_PRICE} 변경` : '저장'}</button></div></div>`;
  document.body.appendChild(ov);
  const inp = ov.querySelector('input'), msg = ov.querySelector('.nk-msg'), go = ov.querySelector('.go');
  const say = (t, cls) => { msg.textContent = t; msg.className = 'nk-msg ' + (cls || ''); };
  let tmr = 0, composing = false, saving = false, submitAfter = false;
  const check = () => { if (composing || saving) return; clearTimeout(tmr); const v = inp.value.trim(); if (!v) return say('');
    const loc = paid && v === cur ? 'same' : v.length < 2 ? 'short' : v.length > 12 ? 'long' : !/^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ _.\-]+$/.test(v) ? 'bad' : null;
    if (loc) return say(NICK_ERR[loc], 'bad');
    tmr = setTimeout(async () => { if (composing || saving) return; try { const { data } = await sb.rpc('nickname_check', { p_nick: v }); if (!composing && !saving && inp.value.trim() === v) say(data === 'ok' ? '사용할 수 있어요' : NICK_ERR[data] || '', data === 'ok' ? 'good' : 'bad'); } catch {} }, 350); };
  return new Promise(res => {
    const done = v => { ov.remove(); res(v); };
    const no = ov.querySelector('.no'); if (no) no.onclick = () => { if (saving) return; done(null); };
    if (!first) ov.addEventListener('click', e => { if (e.target === ov && !saving) done(null); });
    const save = async () => {
      if (composing) { submitAfter = true; return; }
      if (saving) return;
      const v = inp.value.trim();
      if (paid && !await window.VRAsk(`심연석 ${NICK_PRICE}개를 써서 '${v}'(으)로 바꿀까요?`)) return;
      if (composing || saving) return;
      saving = true; go.disabled = true;   // 저장 중에는 문구를 바꾸지 않음
      const { data, error } = await sb.rpc('set_nickname', { p_nick: v });
      if (error) { saving = false; go.disabled = false; return say(nickErr(error.message), 'bad'); }
      profile = { ...(profile || {}), nickname: data?.nickname || v, nick_set: true }; render(profile);
      if (data?.cost) try { window.VRGem?.status?.(true); } catch {}
      window.dispatchEvent(new CustomEvent('vr:nickname', { detail: profile.nickname })); done(profile.nickname);
    };
    inp.addEventListener('compositionstart', () => { composing = true; clearTimeout(tmr); });
    inp.addEventListener('compositionend', () => { composing = false; setTimeout(() => { if (composing || saving) return; check(); if (submitAfter) { submitAfter = false; save(); } }, 0); });
    inp.oninput = e => { if (composing || saving || e.isComposing) return; check(); };
    go.onclick = save;
    inp.onkeydown = e => { if (composing || e.isComposing || e.keyCode === 229 || e.key === 'Process') return; if (e.key === 'Enter') save(); };
    setTimeout(() => inp.focus(), 50);
  });
}

window.VRCloud = { get isStaging() { return config.isStaging === true; }, get profile() { return profile; }, askNickname: () => askNickname(false), get user() { return user; }, get sb() { return sb; }, get ready() { return ready; }, loadRecord, login, logout, push, canLogin, linkProvider };
init();
