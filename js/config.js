// 접속 환경의 단일 설정. URL / anon(publishable) 키는 공개 값입니다.
// 비밀 키는 절대 넣지 마세요. 운영은 아래의 정확한 주소에서만 연결합니다.
export const PRODUCTION_HOSTNAMES = Object.freeze(['tcg.mbbs.kr', 'vr-tcg-prod.notcold.workers.dev']);
const PRODUCTION = Object.freeze({
  supabaseUrl: 'https://htarwisgkkphutxxnuak.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0YXJ3aXNna2twaHV0eHhudWFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNTMwOTgsImV4cCI6MjEwNzcyOTA5OH0.xaIda-o8QwRhoG5yDRLAcMo8LbU1rNHUA7xznO-tEfc',
});

// 별도 테스트 DB 공개 설정. Cloudflare 주소 발급 후 hostnames를 맞추세요 (docs/STAGING.md).
export const STAGING = Object.freeze({
  supabaseUrl: 'https://cuyqchmdcnsgzkwyclji.supabase.co', // 테스트 전용 (운영 URL 금지)
  anonKey: 'sb_publishable_N3rWy8v7bsWu8CdgHJM0Hg_6dGqsKn-', // 공개 publishable 키
  hostnames: Object.freeze([
    'dev-tcg.mbbs.kr',
    'vr-tcg-staging.notcold.workers.dev',
  ]),
});

function validStaging(value) {
  try {
    const url = new URL(value.supabaseUrl);
    if (url.protocol !== 'https:' || !/^[a-z0-9]+\.supabase\.co$/.test(url.hostname)
      || url.origin === PRODUCTION.supabaseUrl || url.pathname !== '/' || url.search || url.hash || url.port || url.username || url.password) return false;
    const key = value.anonKey;
    if (typeof key !== 'string' || key === PRODUCTION.anonKey) return false;
    if (key.startsWith('sb_publishable_') && key.length > 20) return true;
    // 옛 JWT 형식 anon 키: 서비스 권한 키를 실수로 넣어도 연결하지 않음.
    const body = key.split('.')[1];
    const claims = JSON.parse(atob(body.replace(/-/g, '+').replace(/_/g, '/')));
    return claims.role === 'anon' && claims.ref === url.hostname.split('.')[0];
  } catch { return false; }
}

export function resolveConfig(locationLike, staging = STAGING) {
  const host = String(locationLike.hostname || '').toLowerCase();
  const local = ['localhost', '127.0.0.1', '[::1]', '::1'].includes(host);
  const flag = local ? new URLSearchParams(locationLike.search || '').get('vrEnv') : null;
  const production = PRODUCTION_HOSTNAMES.includes(host) || (local && flag === 'production');
  const test = !production && ((staging.hostnames || []).map(h => h.toLowerCase()).includes(host) || (local && flag === 'staging'));
  const enabled = production || (test && validStaging(staging));
  return Object.freeze({
    environment: production ? 'production' : test ? 'staging' : 'disabled',
    isStaging: test,
    enabled,
    supabaseUrl: enabled ? (production ? PRODUCTION.supabaseUrl : new URL(staging.supabaseUrl).origin) : '',
    anonKey: enabled ? (production ? PRODUCTION.anonKey : staging.anonKey) : '',
    reason: enabled ? '' : test ? '테스트 DB 미설정' : '등록되지 않은 주소',
  });
}

export const config = resolveConfig(typeof location === 'undefined' ? {} : location);

// 운영 화면은 바꾸지 않음. 테스트 환경에만 작게 항상 표시.
export function showTestBadge(doc, selected = config) {
  if (!selected.isStaging || doc.getElementById('vr-test-badge')) return;
  const badge = doc.createElement('div');
  badge.id = 'vr-test-badge';
  badge.textContent = selected.enabled ? 'TEST' : 'TEST · DB 미설정';
  badge.setAttribute('aria-label', '테스트 서버 · 운영 데이터와 별개');
  badge.style.cssText = 'position:fixed;top:max(4px,env(safe-area-inset-top));left:6px;z-index:2147483647;padding:3px 7px;border-radius:5px;background:#fbbf24;color:#171717;font:700 11px/1.4 sans-serif;pointer-events:none;box-shadow:0 1px 4px #0008';
  doc.body.appendChild(badge);
}
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => showTestBadge(document), { once: true });
  else showTestBadge(document);
}
