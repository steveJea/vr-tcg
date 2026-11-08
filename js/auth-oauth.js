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
export function cleanOAuthCallback(loc, hist) {
  const url = new URL(loc.href);
  const keys = ['code', 'access_token', 'refresh_token', 'expires_in', 'expires_at', 'token_type', 'provider_token', 'provider_refresh_token', 'error', 'error_code', 'error_description'];
  const hash = new URLSearchParams(url.hash.slice(1));
  const found = keys.some(k => url.searchParams.has(k) || hash.has(k));
  const failed = url.searchParams.has('error') || hash.has('error');
  if (found) {
    keys.forEach(k => { url.searchParams.delete(k); hash.delete(k); });
    // A normal anchor is not an OAuth fragment and must survive.
    if (keys.some(k => new URLSearchParams(loc.hash.slice(1)).has(k))) url.hash = hash.toString();
    hist.replaceState(null, '', url.pathname + url.search + url.hash);
  }
  return failed;
}
