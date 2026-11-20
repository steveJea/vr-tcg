// 포트원 V2 본인인증 클라이언트. 시크릿 없음. 플래그가 켜져 있고 공개 키가 있을 때만 SDK를 부름.
import { config } from './config.js';
import { publicConfig, SDK_SRC, STAGE_DB, isVerificationId } from './age-verify-config.js';

export function readReturn(href) {
  const p = new URL(href).searchParams;
  const id = p.get('identityVerificationId') || '';
  if (p.get('code')) return { failed: true, message: (p.get('message') || p.get('code') || '').slice(0, 200) };
  if (isVerificationId(id)) return { identityVerificationId: id };
  return null;
}

export async function confirm(sb, identityVerificationId, fetcher = fetch, timeout = 14000) {
  if (!isVerificationId(identityVerificationId)) throw Error('invalid request');
  if (config.supabaseUrl !== STAGE_DB || !config.isStaging) throw Error('staging only');
  const { data } = await sb.auth.getSession();
  if (!data?.session?.access_token) throw Error('login required');
  const ctrl = new AbortController();
  let timer;
  try {
    const work = (async () => {
      const r = await fetcher(STAGE_DB + '/functions/v1/age-verify-v1', {
        method: 'POST',
        headers: { 'content-type': 'application/json', apikey: config.anonKey, authorization: 'Bearer ' + data.session.access_token },
        body: JSON.stringify({ identityVerificationId }),
        signal: ctrl.signal,
      });
      let d;
      try { d = await r.json(); } catch { throw Error(r.status === 504 ? 'verification pending' : 'verification not completed'); }
      if (!r.ok || !d?.ok) {
        if (r.status === 401) throw Error('login required');
        if (r.status === 403 && d?.error === 'underage') throw Error('underage');
        if (r.status === 404) throw Error('age verification function missing');
        if (r.status === 503 && d?.error === 'age verification configuration required') throw Error('age verification configuration required');
        throw Error(typeof d?.error === 'string' && d.error.length <= 80 ? d.error : 'verification not completed');
      }
      return d;
    })();
    return await Promise.race([work, new Promise((_, reject) => { timer = setTimeout(() => { ctrl.abort(); reject(Error('verification pending')); }, timeout); })]);
  } finally { clearTimeout(timer); }
}

export function verifyError(code) {
  return ({
    'login required': '로그인이 필요해요.',
    'underage': '만 19세 이상만 이용할 수 있어요.',
    'identity already used': '이미 다른 계정에서 인증된 본인 정보예요.',
    'identity mismatch': '이 계정에 등록된 본인 정보와 달라요.',
    'identity incomplete': '본인인증 결과에 필요한 정보가 없어요. CI 제공이 계약에 포함됐는지 확인해 주세요.',
    'verification not completed': '본인인증이 완료되지 않았어요. 다시 시도해 주세요.',
    'verification pending': '본인인증 확인이 지연되고 있어요. 다시 확인해 주세요.',
    'age verification configuration required': '본인인증 서버 키가 아직 설정되지 않았어요.',
    'age verification function missing': '본인인증 서버가 아직 배포되지 않았어요.',
    'age verify sql required': '본인인증 DB 설정을 확인해 주세요.',
    'profile required': '프로필을 만든 뒤 다시 시도해 주세요.',
    'USER_CANCEL': '본인인증을 취소했어요.',
    'sdk': '본인인증 창을 불러오지 못했어요.',
    'not ready': '본인인증 연동은 준비 중입니다.',
  })[code] || '본인인증을 완료하지 못했어요. 다시 시도해 주세요.';
}

export async function loadSDK(loader = typeof document === 'undefined' ? null : document) {
  if (typeof window !== 'undefined' && window.PortOne?.requestIdentityVerification) return window.PortOne;
  if (!loader) throw Error('sdk');
  await new Promise((resolve, reject) => {
    const s = loader.createElement('script');
    s.src = SDK_SRC;
    s.onload = () => resolve();
    s.onerror = () => reject(Error('sdk'));
    loader.head.appendChild(s);
  });
  if (!window.PortOne?.requestIdentityVerification) throw Error('sdk');
  return window.PortOne;
}

export async function requestVerification(keys = publicConfig(config), PortOneLoader = loadSDK) {
  if (!keys.ready) throw Error('not ready');
  const PortOne = await PortOneLoader();
  const identityVerificationId = 'identity-verification-' + crypto.randomUUID();
  try { sessionStorage.setItem('vrTcg.age.vid.v1', identityVerificationId); } catch {}
  const response = await PortOne.requestIdentityVerification({
    storeId: keys.storeId,
    channelKey: keys.channelKey,
    identityVerificationId,
    redirectUrl: keys.redirectUrl,
    bypass: { danal: { AGELIMIT: 19, CPTITLE: keys.siteTitle } },
  });
  if (response?.code) {
    const cancel = /cancel|canceled|cancelled|user.?cancel/i.test(String(response.code) + ' ' + String(response.message || ''));
    throw Error(cancel ? 'USER_CANCEL' : 'verification not completed');
  }
  const id = response?.identityVerificationId || identityVerificationId;
  if (!isVerificationId(id)) throw Error('verification not completed');
  return id;
}
