// ===== 첫 로그인 동의 (이용약관·개인정보·만 14세 [필수] + 이벤트·혜택 알림 [선택]) =====
// 로그인(구글·카카오·X 등) 뒤 현재 버전 동의 기록이 없으면 게임 들어가기 전에 한 번 보여 줌. 기존 회원도 기록이 없으면 한 번.
// 게스트(로그인 안 함)·튜토리얼은 개인정보를 모으지 않으므로 묻지 않음 — 로그인하는 순간 물어봄.
// 서버: supabase/consent_staging.sql (user_consents + consent_status / consent_accept / consent_set_marketing).
// SQL 이 아직 없거나 네트워크가 끊겨도: 동의 창은 그대로 뜨고, 이 브라우저에 저장했다가 나중에 서버로 다시 보냄.
export const TERMS_VERSION = '2026-11-draft', PRIVACY_VERSION = '2026-11-draft';
const KEY = uid => `vrConsent.v1:${uid}`;
const RETRY_MS = 30000;
let retryTimer = 0, current = null;   // current: { sb, uid, rec }
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export function readLocal(uid, store = globalThis.localStorage) { try { return JSON.parse(store.getItem(KEY(uid)) || 'null'); } catch { return null; } }
export function saveLocal(uid, rec, store = globalThis.localStorage) { try { store.setItem(KEY(uid), JSON.stringify(rec)); } catch {} return rec; }
export const isCurrent = r => !!r && r.terms_version === TERMS_VERSION && r.privacy_version === PRIVACY_VERSION && r.age14 === true;
export const canStart = ck => !!(ck.terms && ck.privacy && ck.age14);

async function rpc(sb, fn, args) {
  if (!sb) return { ok: false };
  try { const { data, error } = await sb.rpc(fn, args); return error ? { ok: false, error } : { ok: true, data }; } catch (error) { return { ok: false, error }; }
}
/** 서버로 아직 못 보낸 이 브라우저의 동의를 보냄 (동의 → 마케팅 변경 순서) */
export async function pushLocal(sb, uid, store = globalThis.localStorage) {
  const rec = readLocal(uid, store); if (!rec || rec.synced || !isCurrent(rec)) return !!rec?.synced;
  let r = await rpc(sb, 'consent_status');
  if (r.ok && !r.data?.current) r = await rpc(sb, 'consent_accept', { p_terms: rec.terms_version, p_privacy: rec.privacy_version, p_age14: true, p_marketing: !!rec.marketing, p_user_agent: (globalThis.navigator?.userAgent || '').slice(0, 300) });
  if (r.ok && r.data?.current && r.data.record?.marketing !== !!rec.marketing) r = await rpc(sb, 'consent_set_marketing', { p_marketing: !!rec.marketing });
  if (!r.ok) { scheduleRetry(sb, uid, store); return false; }
  saveLocal(uid, { ...rec, synced: true }, store); return true;
}
function scheduleRetry(sb, uid, store) {
  clearTimeout(retryTimer);
  retryTimer = setTimeout(() => { if (current?.uid === uid) void pushLocal(sb, uid, store); }, RETRY_MS);
}

/** 로그인 직후 호출. true = 게임 진행, false = 동의 안 함(로그아웃 처리됨) 또는 다른 계정으로 바뀜 */
export async function ensureConsent(sb, user, { onDecline, store = globalThis.localStorage, show = showModal } = {}) {
  if (!user?.id) return true;
  const uid = user.id; current = { sb, uid };
  const st = await rpc(sb, 'consent_status'), local = readLocal(uid, store);
  if (st.ok && st.data?.current) {
    if (isCurrent(local) && !local.synced) void pushLocal(sb, uid, store);   // 이 브라우저에서 바꾼 알림 설정이 아직 안 올라감
    else saveLocal(uid, { ...st.data.record, synced: true }, store);
    paintSettings(); return true;
  }
  if (isCurrent(local)) { if (!local.synced) void pushLocal(sb, uid, store); paintSettings(); return true; }
  const ck = await show();
  if (current?.uid !== uid) return false;   // 창이 떠 있는 동안 계정이 바뀜
  if (!ck) { await onDecline?.(); return false; }
  saveLocal(uid, { terms_version: TERMS_VERSION, privacy_version: PRIVACY_VERSION, age14: true, marketing: !!ck.marketing, agreed_at: new Date().toISOString(), synced: false }, store);
  await pushLocal(sb, uid, store); paintSettings();
  return true;
}

// --- 동의 창 ---
function css() {
  if (document.getElementById('consent-css')) return;
  const c = document.createElement('style'); c.id = 'consent-css'; c.textContent = `
  #consent-ov{position:fixed;inset:0;z-index:9600;background:rgba(0,0,0,.82);display:flex;align-items:center;justify-content:center;padding:16px}
  #consent-box{width:100%;max-width:380px;background:linear-gradient(#1e1530,#0e0a18);border:1px solid rgba(251,191,36,.45);border-radius:16px;color:#fde68a;padding:18px 16px 14px;box-shadow:0 10px 40px rgba(0,0,0,.6)}
  #consent-box h3{margin:0 0 4px;font-size:18px}#consent-box p.cs-sub{margin:0 0 12px;font-size:12px;opacity:.8;line-height:1.5}
  #consent-box label{display:flex;align-items:center;gap:10px;padding:9px 6px;border-radius:10px;font-size:14px;color:#fff;cursor:pointer}
  #consent-box label.cs-all{background:rgba(251,191,36,.12);border:1px solid rgba(251,191,36,.35);font-weight:800;margin-bottom:6px}
  #consent-box input[type=checkbox]{width:20px;height:20px;accent-color:#f59e0b;flex:none}
  #consent-box .cs-tag{font-size:11px;font-weight:900;color:#fbbf24;flex:none}#consent-box .cs-tag.opt{color:#a1a1aa}
  #consent-box .cs-txt{flex:1}#consent-box a{color:#93c5fd;font-size:12px;text-decoration:underline;flex:none}
  #consent-box .cs-note{font-size:11px;opacity:.7;margin:8px 4px 12px;line-height:1.5}
  #consent-box .cs-btns{display:flex;gap:8px}#consent-box button{flex:1;padding:11px;border-radius:10px;border:1px solid rgba(251,191,36,.35);background:rgba(0,0,0,.3);color:#fde68a;font-weight:800;font-size:14px;cursor:pointer}
  #consent-box button.go{flex:1.4;background:#f59e0b;color:#1a1200}#consent-box button:disabled{opacity:.45;cursor:not-allowed}`;
  document.head.appendChild(c);
}
const ITEMS = [
  ['terms', '필수', '이용약관 동의', '/terms.html'],
  ['privacy', '필수', '개인정보 수집·이용 안내 확인', '/privacy.html'],
  ['age14', '필수', '만 14세 이상입니다', ''],
  ['marketing', '선택', '이벤트·혜택 알림 수신', ''],
];
export function showModal() {
  document.getElementById('consent-ov')?.remove(); css();
  const ov = document.createElement('div'); ov.id = 'consent-ov';
  ov.innerHTML = `<div id="consent-box" role="dialog" aria-modal="true" aria-labelledby="consent-title" data-clarity-mask="true">
    <h3 id="consent-title">시작하기 전에 확인해 주세요</h3><p class="cs-sub">처음 한 번만 물어봐요. 필수 항목에 동의하면 바로 시작해요.</p>
    <label class="cs-all"><input type="checkbox" data-all><span class="cs-txt">전체 동의 <small style="opacity:.7;font-weight:600">(선택 항목 포함)</small></span></label>
    ${ITEMS.map(([k, t, txt, href]) => `<label><input type="checkbox" data-ck="${k}"><span class="cs-tag ${t === '선택' ? 'opt' : ''}">[${t}]</span><span class="cs-txt">${esc(txt)}</span>${href ? `<a href="${href}" target="_blank" rel="noopener noreferrer">보기</a>` : ''}</label>`).join('')}
    <div class="cs-note">선택 항목은 동의하지 않아도 게임을 이용할 수 있고, 설정에서 언제든 바꿀 수 있어요.</div>
    <div class="cs-btns"><button type="button" class="no">동의 안 함·로그아웃</button><button type="button" class="go" disabled>동의하고 시작</button></div></div>`;
  document.body.appendChild(ov);
  const boxes = [...ov.querySelectorAll('[data-ck]')], all = ov.querySelector('[data-all]'), go = ov.querySelector('.go');
  const state = () => Object.fromEntries(boxes.map(b => [b.dataset.ck, b.checked]));
  const sync = () => { const s = state(); go.disabled = !canStart(s); all.checked = boxes.every(b => b.checked); all.indeterminate = !all.checked && boxes.some(b => b.checked); };
  all.onchange = () => { boxes.forEach(b => { b.checked = all.checked; }); sync(); };
  boxes.forEach(b => b.onchange = sync);
  return new Promise(res => {
    const done = v => { window.removeEventListener('vr:user', onUser); ov.remove(); res(v); };
    const onUser = () => { if (current && window.VRCloud?.user?.id !== current.uid) done(null); };
    window.addEventListener('vr:user', onUser);
    go.onclick = () => { if (!go.disabled) done(state()); };
    ov.querySelector('.no').onclick = () => done(null);
    setTimeout(() => all.focus(), 50);
  });
}

// --- 설정 창: 동의 상태 + 이벤트·혜택 알림 켜기/끄기 ---
export function paintSettings() {
  const box = typeof document !== 'undefined' && document.getElementById('consent-settings'); if (!box) return;
  const uid = window.VRCloud?.user?.id, rec = uid && readLocal(uid);
  if (!uid || !isCurrent(rec)) { box.classList.add('hidden'); box.innerHTML = ''; return; }
  const day = String(rec.agreed_at || '').slice(0, 10);
  box.classList.remove('hidden');
  box.innerHTML = `<div class="set-row"><span class="set-label">📩 이벤트·혜택 알림</span><button id="main-marketing" class="set-toggle ${rec.marketing ? 'on' : ''}" type="button" role="switch" aria-checked="${!!rec.marketing}" aria-label="이벤트·혜택 알림">${rec.marketing ? 'ON' : 'OFF'}</button></div>
    <div class="consent-status" style="font-size:11px;opacity:.7;margin:2px 4px 0;line-height:1.5">약관·개인정보 동의 완료${day ? ` · ${esc(day)}` : ''} (버전 ${esc(rec.terms_version)})${rec.synced ? '' : ' · 서버 저장 대기 중'}</div>`;
  box.querySelector('#main-marketing').onclick = () => setMarketing(!rec.marketing);
}
export async function setMarketing(on, { store = globalThis.localStorage } = {}) {
  const uid = window.VRCloud?.user?.id, rec = uid && readLocal(uid, store); if (!isCurrent(rec)) return false;
  saveLocal(uid, { ...rec, marketing: !!on, synced: false }, store); paintSettings();
  const ok = await pushLocal(window.VRCloud?.sb, uid, store); paintSettings(); return ok;
}
if (typeof window !== 'undefined') {
  window.VRConsent = { TERMS_VERSION, PRIVACY_VERSION, ensureConsent, showModal, paintSettings, setMarketing, readLocal, pushLocal };
  window.addEventListener('vr:user', () => { if (!window.VRCloud?.user) { current = null; clearTimeout(retryTimer); } paintSettings(); });
  window.addEventListener('online', () => { if (current) void pushLocal(current.sb, current.uid); });
}
