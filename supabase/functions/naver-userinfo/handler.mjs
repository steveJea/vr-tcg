// Flatten Naver's nested /v1/nid/me payload into the OIDC userinfo shape
// Supabase custom OAuth providers expect. No secrets. The Authorization
// header is a Naver access token, not a Supabase JWT.
export const NAVER_USERINFO_URL = 'https://openapi.naver.com/v1/nid/me';

const text = v => typeof v === 'string' ? v.trim() : '';

export function flattenNaverProfile(data) {
  const profile = data?.response;
  if (data?.resultcode !== '00' || !profile || profile.id == null || String(profile.id).trim() === '') return null;
  const out = { sub: String(profile.id).trim() };
  const name = text(profile.name), nickname = text(profile.nickname);
  const picture = text(profile.profile_image), email = text(profile.email);
  if (name) out.name = name;
  if (nickname) out.nickname = nickname;
  if (picture) out.picture = picture;
  if (email && email.includes('@')) out.email = email;
  return out;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      'access-control-allow-headers': 'Authorization, Content-Type',
      'access-control-allow-methods': 'GET,POST,OPTIONS',
    },
  });
}

export function createHandler({ fetchImpl = fetch, timeout = 8000 } = {}) {
  return async function handler(req) {
    if (req.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: {
        'access-control-allow-origin': '*',
        'access-control-allow-headers': 'Authorization, Content-Type',
        'access-control-allow-methods': 'GET,POST,OPTIONS',
      } });
    }
    if (req.method !== 'GET' && req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
    const authorization = req.headers.get('Authorization') || '';
    if (!/^Bearer\s+\S+/.test(authorization)) return json({ error: 'Missing Authorization header' }, 401);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const naverResponse = await Promise.race([
        fetchImpl(NAVER_USERINFO_URL, {
          headers: { Authorization: authorization, Accept: 'application/json' },
          signal: controller.signal,
          redirect: 'error',
        }),
        new Promise((_, reject) => {
          const fail = () => reject(Object.assign(new Error('timeout'), { name: 'AbortError' }));
          if (controller.signal.aborted) fail();
          else controller.signal.addEventListener('abort', fail, { once: true });
        }),
      ]);
      const data = await naverResponse.json().catch(() => null);
      if (!naverResponse.ok) return json({ error: 'Failed to fetch user info from Naver' }, naverResponse.status === 401 ? 401 : 502);
      const profile = flattenNaverProfile(data);
      if (!profile) return json({ error: 'Invalid Naver profile' }, 502);
      return json(profile);
    } catch {
      return json({ error: 'Failed to fetch user info from Naver' }, 502);
    } finally {
      clearTimeout(timer);
    }
  };
}
