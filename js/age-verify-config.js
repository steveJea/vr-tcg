// 포트원 V2 본인인증 공개 설정. Store ID·채널 키는 브라우저 SDK용 공개 값.
// V2 API Secret 은 여기나 채팅에 넣지 않음. 테섭 Edge Function 시크릿 PORTONE_API_SECRET 만 사용.
// 값이 비어 있으면 SDK를 부르지 않고, 플래그가 꺼져 있으면 인증 창을 열지 않음.
export const STAGE_HOST = 'vr-tcg-staging.notcold.workers.dev';
export const STAGE_DB = 'https://cuyqchmdcnsgzkwyclji.supabase.co';
export const SDK_SRC = 'https://cdn.portone.io/v2/browser-sdk.js';
export const RETURN_PATH = '/age-verify-return.html';
// 형님이 콘솔에서 확인한 뒤에 채움. 지금은 비워 두어 키가 없어도 게임이 깨지지 않게 함.
export const STAGING_PORTONE = Object.freeze({
  storeId: '',
  channelKey: '',
});
const STORE_ID = /^store-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CHANNEL_KEY = /^channel-key-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function publicConfig(c, locationLike = (typeof location === 'undefined' ? {} : location), keys = STAGING_PORTONE) {
  const host = String(locationLike.hostname || '').toLowerCase();
  const okHost = !!c?.isStaging && c.supabaseUrl === STAGE_DB && host === STAGE_HOST;
  const storeId = typeof keys.storeId === 'string' ? keys.storeId.trim() : '';
  const channelKey = typeof keys.channelKey === 'string' ? keys.channelKey.trim() : '';
  const ready = okHost && STORE_ID.test(storeId) && CHANNEL_KEY.test(channelKey);
  return Object.freeze({
    ready,
    storeId: ready ? storeId : '',
    channelKey: ready ? channelKey : '',
    redirectUrl: ready ? 'https://' + STAGE_HOST + RETURN_PATH : '',
    siteTitle: STAGE_HOST,
  });
}
export function isVerificationId(id) {
  return typeof id === 'string' && /^identity-verification-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
}
