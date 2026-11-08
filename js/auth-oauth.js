// Public OAuth helpers only: provider secrets belong in Supabase, never in this bundle.
export const OAUTH_PROVIDERS = Object.freeze({ google: '구글', kakao: '카카오' });
const text = v => typeof v === 'string' ? v.trim() : '';
export function profileSeed(u) {
  const m = u?.user_metadata || {};
  const nickname = text(m.name) || text(m.full_name) || text(m.preferred_username) || text(m.nickname) || text(u?.email).split('@')[0] || '플레이어';
  return { nickname: nickname.slice(0, 20), avatar_url: text(m.avatar_url) || text(m.picture) || null };
}
export function hasIdentity(u, provider) {
  return (u?.identities || []).some(i => i?.provider === provider);
}
export function oauthRequest(provider, redirectTo) {
  if (!Object.hasOwn(OAUTH_PROVIDERS, provider)) throw new Error('Unsupported OAuth provider');
  return { provider, options: { redirectTo } };
}
export async function discoverKakao(config, fetcher = fetch, timeout = 4000) {
  if (!config.enabled) return false;
  const controller = new AbortController();
  let timer;
  try {
    // The anonymous settings endpoint, NOT a user/management endpoint. Fail closed.
    const result = await Promise.race([
      (async () => {
        const res = await fetcher(config.supabaseUrl + '/auth/v1/settings', { headers: { apikey: config.anonKey }, signal: controller.signal, cache: 'no-store' });
        return res.ok && (await res.json())?.external?.kakao === true;
      })(),
      new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(false); }, timeout); })
    ]);
    return result === true;
  } catch { return false; }
  finally { clearTimeout(timer); }
}
const CALLBACK_KEYS = ['code', 'access_token', 'refresh_token', 'expires_in', 'expires_at', 'token_type', 'provider_token', 'provider_refresh_token', 'error', 'error_code', 'error_description'];
export function oauthErrorCode(error) {
  const code = text(error?.code) || text(error?.details?.code);
  if (code) return code;
  const message = text(error?.message);
  if (/^Identity is already linked(?: to another user)?[.!]?$/i.test(message)) return 'identity_already_exists';
  if (/manual linking.*disabled/i.test(message)) return 'manual_linking_disabled';
  return '';
}
export function readOAuthCallback(loc) {
  const url = new URL(loc.href), hash = new URLSearchParams(url.hash.slice(1));
  const value = key => url.searchParams.get(key) || hash.get(key) || '';
  const has = key => url.searchParams.has(key) || hash.has(key);
  const failed = ['error', 'error_code', 'error_description'].some(has);
  return { attempted: CALLBACK_KEYS.some(has), failed, hasCode: has('code'),
    errorCode: failed ? oauthErrorCode({code:value('error_code'),message:value('error_description')}) || value('error') : '' };
}
export function cleanOAuthCallback(loc, hist) {
  const url = new URL(loc.href), hash = new URLSearchParams(url.hash.slice(1));
  const callback = readOAuthCallback(loc);
  if (callback.attempted) {
    CALLBACK_KEYS.forEach(k => { url.searchParams.delete(k); hash.delete(k); });
    // A normal anchor is not an OAuth fragment and must survive.
    if (CALLBACK_KEYS.some(k => new URLSearchParams(loc.hash.slice(1)).has(k))) url.hash = hash.toString();
    hist.replaceState(null, '', url.pathname + url.search + url.hash);
  }
  return callback.failed;
}
const linkKey = project => 'vrTcgOAuthLink.v1:' + project;
export function saveLinkIntent(storage, project, intent, now = Date.now()) {
  if (!intent?.uid || !Object.hasOwn(OAUTH_PROVIDERS, intent.provider)) throw new Error('invalid link intent');
  // Context only, never credentials/tokens/authorization codes. Tab- and project-scoped.
  storage.setItem(linkKey(project), JSON.stringify({ uid:intent.uid, provider:intent.provider, startedAt:intent.startedAt ?? now }));
}
export function takeLinkIntent(storage, project, now = Date.now()) {
  try {
    const raw = storage.getItem(linkKey(project)); storage.removeItem(linkKey(project));
    const intent = JSON.parse(raw || 'null');
    return intent && typeof intent.uid === 'string' && intent.uid && Object.hasOwn(OAUTH_PROVIDERS, intent.provider) && Number.isFinite(intent.startedAt) && intent.startedAt <= now && now - intent.startedAt <= 20 * 60 * 1000 ? intent : null;
  } catch { return null; }
}
export function oauthFailureMessage(code, intent = null) {
  const name = OAUTH_PROVIDERS[intent?.provider];
  if (['identity_already_exists', 'email_exists'].includes(code)) return name ? `이미 다른 계정에 연결된 ${name} 계정이에요.` : '이미 다른 계정에 연결된 로그인입니다.';
  if (code === 'manual_linking_disabled') return '계정 연결 기능이 아직 꺼져 있어요.';
  if (['access_denied', 'user_cancelled', 'user_canceled'].includes(code)) return intent ? '계정 연결을 취소했어요.' : '로그인을 취소했어요.';
  if (['bad_code_verifier', 'flow_state_expired', 'flow_state_not_found'].includes(code)) return '같은 브라우저에서 다시 시도해 주세요.';
  return intent ? '계정 연결을 완료하지 못했어요. 다시 시도해 주세요.' : '로그인이 취소되었거나 완료되지 않았어요. 다시 시도해 주세요.';
}
export async function resolveOAuthReturn(auth, callback, intent, sessionUser, initError = null, timeout = 6000) {
  const code = callback.errorCode || oauthErrorCode(initError);
  if (!intent) return { user:sessionUser, message:callback.failed || initError ? oauthFailureMessage(code) : '' };
  let timer;
  try {
    const result = await Promise.race([
      auth.getUser(),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('verification timeout')), timeout); })
    ]);
    if (result.error) throw result.error;
    const verified = result.data?.user;
    if (!verified || verified.id !== intent.uid) return { user:verified || null, message:'연결을 시작한 계정이 달라졌어요. 다시 로그인해 주세요.' };
    // A linked identity on the SAME server-verified UUID is the success criterion,
    // not a stale session cache, a successful redirect, or an error fragment alone.
    if (hasIdentity(verified, intent.provider)) return { user:verified, message:`${OAUTH_PROVIDERS[intent.provider]} 계정이 연결되었어요.` };
    return { user:verified, message:oauthFailureMessage(code, intent) };
  } catch {
    return { user:sessionUser, message:callback.failed || initError ? oauthFailureMessage(code, intent) : '연결 상태를 확인하지 못했어요. 새로고침해 주세요.', retry:!callback.failed && !initError };
  } finally { clearTimeout(timer); }
}
