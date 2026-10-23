// ===== 카카오톡 공유 (갤러리). Kakao JS SDK 는 처음 누를 때만 불러옴 =====
// 카카오 개발자 콘솔: [앱] → [플랫폼 키] → [JavaScript 키] → [JavaScript SDK 도메인]에 https://tcg.mbbs.kr 등록 필수
// (안 되어 있으면 uploadImage·sendDefault 가 {code:-401, msg:'domain mismatched! ...'} 로 실패). JavaScript 키는 공개 키
(function () {
  const SDK = 'https://t1.kakaocdn.net/kakao_js_sdk/2.7.6/kakao.min.js';
  const KEY = '839f298caef8022398724020f36bd2d8';
  const GAME_URL = 'https://tcg.mbbs.kr/';
  let loading = null;
  /** SDK 로드 + init. 실패하면 reject */
  function ready() {
    if (window.Kakao?.isInitialized?.()) return Promise.resolve(window.Kakao);
    if (!loading) loading = new Promise((res, rej) => {
      const done = () => { try { if (!window.Kakao) throw new Error('Kakao SDK 없음'); if (!Kakao.isInitialized()) Kakao.init(KEY); res(Kakao); } catch (e) { rej(e); } };
      if (window.Kakao) return done();
      const s = document.createElement('script'); s.src = SDK; s.async = true; s.crossOrigin = 'anonymous';
      s.onload = done; s.onerror = () => rej(new Error('Kakao SDK 로드 실패'));
      setTimeout(() => rej(new Error('Kakao SDK 시간 초과')), 10000);
      document.head.appendChild(s);
    }).catch(e => { loading = null; throw e; });
    return loading;
  }
  /** 카드 이미지(File)를 카카오 서버에 올리고 피드 템플릿으로 공유. title = 카드 이름, 버튼 '게임하러 가기' */
  async function share({ title, description, file }) {
    const K = await ready();
    const up = await Promise.race([K.Share.uploadImage({ file: [file] }), new Promise((_, rej) => setTimeout(() => rej(new Error('이미지 업로드 시간 초과')), 8000))]);
    const imageUrl = up?.infos?.original?.url; if (!imageUrl) throw new Error('이미지 업로드 실패');
    const link = { mobileWebUrl: GAME_URL, webUrl: GAME_URL };
    K.Share.sendDefault({
      objectType: 'feed',
      content: { title, description: description || 'VR: Abyss Gate', imageUrl, imageWidth: 1080, imageHeight: 1500, link },
      buttons: [{ title: '게임하러 가기', link }],
    });
    return true;
  }
  /** 실패 원인을 사람이 읽을 수 있게 (토스트용). 전체 오류는 콘솔에 */
  function describe(e) {
    const code = e?.code, msg = String(e?.msg || e?.message || e || '');
    if (/domain mismatch/i.test(msg)) return `카카오 콘솔에 도메인 미등록 (${code ?? -401})`;
    if (code === -401 || /app ?key|appkey/i.test(msg)) return `카카오 앱 키 오류 (${code ?? -401})`;
    if (/시간 초과/.test(msg)) return msg;
    if (/SDK/.test(msg)) return msg;
    return code != null ? `오류 ${code}` : (msg.slice(0, 40) || '알 수 없는 오류');
  }
  window.VRKakaoShare = { ready, share, describe, GAME_URL };
})();
