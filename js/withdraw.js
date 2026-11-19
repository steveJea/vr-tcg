// ===== 회원탈퇴 (설정 창) · 로그인 유예 취소 확인 =====
// 로그인 계정: 30일 뒤 삭제 예약. 그 사이 로그인하면 취소 여부를 물어봄.
// 게스트: 이 기기 기록만 바로 지움 (서버 계정 없음).
export const CONFIRM_WORD = '탈퇴';

const $ = id => document.getElementById(id);
const user = () => window.VRCloud?.user;
const sb = () => window.VRCloud?.sb;
const toast = msg => (window.VRGem?.toast || alert)(msg);
const missingFn = e => /could not find the function|schema cache|404|PGRST202/i.test(String(e?.message || e?.code || e || ''));

function kstDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const p = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Seoul', year: 'numeric', month: 'numeric', day: 'numeric' }).formatToParts(d);
  const g = t => p.find(x => x.type === t)?.value;
  return `${g('year')}년 ${g('month')}월 ${g('day')}일`;
}

function localKeys(store) {
  const out = [];
  try {
    for (let i = 0; i < store.length; i++) {
      const k = store.key(i);
      if (k && /^(vr|tcg_|consent)/i.test(k)) out.push(k);
    }
  } catch {}
  return out;
}
function wipeLocal() {
  for (const store of [localStorage, sessionStorage]) {
    for (const k of localKeys(store)) {
      try { store.removeItem(k); } catch {}
    }
  }
}

async function rpc(name, args) {
  const client = sb();
  if (!client) throw new Error('login required');
  const { data, error } = await client.rpc(name, args || {});
  if (error) throw error;
  return data;
}

async function status() {
  if (!user() || !sb()) return { ok: true, scheduled: false, guest: !user() };
  try { return { guest: false, ...((await rpc('account_withdraw_status')) || { ok: true, scheduled: false }) }; }
  catch (e) {
    if (missingFn(e)) return { ok: true, scheduled: false, unavailable: true, guest: false };
    throw e;
  }
}

function closeOv() {
  const ov = $('withdraw-ov');
  if (ov) ov.remove();
}

function openOv(html, { lock = true } = {}) {
  closeOv();
  const ov = document.createElement('div');
  ov.id = 'withdraw-ov';
  ov.className = 'wd-ov';
  ov.setAttribute('role', 'dialog');
  ov.setAttribute('aria-modal', 'true');
  ov.innerHTML = `<div class="wd-card" data-clarity-mask="true">${html}</div>`;
  if (!lock) ov.addEventListener('click', e => { if (e.target === ov) closeOv(); });
  document.body.append(ov);
  return ov;
}

const LOSS = `<ul class="wd-lost"><li>보유 인재·카드·덱·장비·훈련소 기록</li><li>골드·심연석·소환권 등 재화</li><li>스토리·아케이드·PvP·조직 진행과 전적</li><li>유료 구매 상품은 환불되지 않아요</li></ul>`;

function accountIntro(st) {
  if (st?.scheduled) {
    return `<h2 class="wd-title">탈퇴 예정 계정이에요</h2>
      <p class="wd-p">${kstDate(st.purge_at) || '예정일'}에 계정이 삭제돼요.${st.days_left != null ? ` (${st.days_left}일 남음)` : ''}</p>
      <p class="wd-p">지금 취소하면 그대로 이용할 수 있어요.</p>
      <div class="wd-row"><button type="button" class="main-btn wd-yes" data-wd="cancel-keep">탈퇴 취소</button><button type="button" class="wd-no" data-wd="close">닫기</button></div>`;
  }
  return `<h2 class="wd-title">회원탈퇴</h2>
    <p class="wd-p">탈퇴를 신청하면 <b>30일 뒤</b>에 계정이 삭제돼요. 그 안에 다시 로그인하면 취소할 수 있어요.</p>
    ${LOSS}
    <p class="wd-p">삭제 후에는 같은 로그인으로 <b>7일 뒤</b>에만 다시 가입할 수 있어요. 결제 기록은 법령에 따라 익명으로 남겨 둘 수 있어요.</p>
    <div class="wd-row"><button type="button" class="main-btn wd-next" data-wd="step2">다음</button><button type="button" class="wd-no" data-wd="close">취소</button></div>`;
}

function accountStep2() {
  return `<h2 class="wd-title">정말 탈퇴할까요?</h2>
    <p class="wd-p">아래 칸에 <b>${CONFIRM_WORD}</b> 를 정확히 입력하면 신청돼요. 30일 안에 로그인해서 취소할 수 있어요.</p>
    <label class="wd-lab" for="wd-confirm">확인 문구</label>
    <input id="wd-confirm" class="wd-inp" type="text" inputmode="text" autocomplete="off" placeholder="${CONFIRM_WORD}" maxlength="10">
    <div class="wd-row"><button type="button" class="main-btn wd-danger" data-wd="submit" disabled>탈퇴 신청</button><button type="button" class="wd-no" data-wd="close">취소</button></div>`;
}

function guestIntro() {
  return `<h2 class="wd-title">이 기기 기록을 지울까요?</h2>
    <p class="wd-p">로그인하지 않은 게스트는 서버 계정이 없어요. 이 기기에 남은 진행·설정만 바로 지워져요. 되돌릴 수 없어요.</p>
    ${LOSS}
    <div class="wd-row"><button type="button" class="main-btn wd-next" data-wd="guest2">다음</button><button type="button" class="wd-no" data-wd="close">취소</button></div>`;
}

function guestStep2() {
  return `<h2 class="wd-title">정말 지울까요?</h2>
    <p class="wd-p">아래 칸에 <b>${CONFIRM_WORD}</b> 를 정확히 입력하면 이 기기 기록이 바로 삭제돼요.</p>
    <label class="wd-lab" for="wd-confirm">확인 문구</label>
    <input id="wd-confirm" class="wd-inp" type="text" inputmode="text" autocomplete="off" placeholder="${CONFIRM_WORD}" maxlength="10">
    <div class="wd-row"><button type="button" class="main-btn wd-danger" data-wd="guest-wipe" disabled>기록 삭제</button><button type="button" class="wd-no" data-wd="close">취소</button></div>`;
}

function bindConfirm(ov, submitAttr) {
  const inp = ov.querySelector('#wd-confirm');
  const go = ov.querySelector(`[data-wd="${submitAttr}"]`);
  const sync = () => { go.disabled = (inp.value || '').trim() !== CONFIRM_WORD; };
  inp.addEventListener('input', sync);
  inp.addEventListener('keydown', e => { if (e.key === 'Enter' && !go.disabled) go.click(); });
  setTimeout(() => inp.focus(), 50);
}

async function submitRequest() {
  const data = await rpc('account_withdraw_request', { p_confirm: CONFIRM_WORD });
  closeOv();
  toast(`${kstDate(data?.purge_at) || '30일 뒤'}에 계정이 삭제되도록 신청했어요. 그 안에 로그인하면 취소할 수 있어요.`);
  await paintSettings();
}

async function cancelSchedule({ keepSession = true, after } = {}) {
  await rpc('account_withdraw_cancel');
  closeOv();
  toast('탈퇴 신청을 취소했어요. 계정을 그대로 쓸 수 있어요.');
  if (after) await after();
  if (keepSession) await paintSettings();
}

export function openDialog(mode = 'auto', st = null) {
  const logged = !!user();
  const kind = mode === 'account' || (mode === 'auto' && logged) ? 'account' : 'guest';
  const ov = openOv(kind === 'account' ? accountIntro(st) : guestIntro(), { lock: false });
  ov.addEventListener('click', async e => {
    const act = e.target.closest('[data-wd]')?.dataset.wd;
    if (!act) return;
    if (act === 'close') return closeOv();
    if (act === 'step2') {
      ov.querySelector('.wd-card').innerHTML = accountStep2();
      bindConfirm(ov, 'submit');
      return;
    }
    if (act === 'guest2') {
      ov.querySelector('.wd-card').innerHTML = guestStep2();
      bindConfirm(ov, 'guest-wipe');
      return;
    }
    if (act === 'submit') {
      const btn = e.target.closest('[data-wd="submit"]');
      btn.disabled = true;
      try { await submitRequest(); }
      catch (err) { btn.disabled = false; toast(err?.message === 'confirm required' ? '확인 문구를 다시 입력해 주세요.' : '탈퇴 신청을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.'); }
      return;
    }
    if (act === 'guest-wipe') {
      wipeLocal();
      closeOv();
      location.reload();
      return;
    }
    if (act === 'cancel-keep') {
      const btn = e.target.closest('[data-wd="cancel-keep"]');
      btn.disabled = true;
      try { await cancelSchedule(); }
      catch { btn.disabled = false; toast('탈퇴 취소를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.'); }
    }
  });
  return ov;
}

export async function paintSettings() {
  const box = $('withdraw-settings');
  if (!box) return;
  let st = { scheduled: false, guest: !user() };
  try { st = await status(); } catch { st = { scheduled: false, guest: !user(), error: true }; }
  box.classList.remove('hidden');
  if (st.unavailable) {
    box.innerHTML = `<div class="set-row wd-row-set"><span class="set-label">회원탈퇴<small>서버 준비가 끝나면 열려요</small></span><button id="main-withdraw" class="set-toggle as-btn wd-btn" type="button" disabled>준비 중</button></div>`;
    return;
  }
  if (!user()) {
    box.innerHTML = `<div class="set-row wd-row-set"><span class="set-label">이 기기 기록 삭제<small>게스트 진행만 지워져요</small></span><button id="main-withdraw" class="set-toggle as-btn wd-btn" type="button">삭제</button></div>`;
    $('main-withdraw').onclick = () => openDialog('guest');
    return;
  }
  if (st.scheduled) {
    box.innerHTML = `<div class="set-row wd-row-set"><span class="set-label">탈퇴 예정<small>${kstDate(st.purge_at) || ''}${st.days_left != null ? ` · ${st.days_left}일 남음` : ''}</small></span><button id="main-withdraw-cancel" class="set-toggle as-btn" type="button">취소</button></div>`;
    $('main-withdraw-cancel').onclick = () => openDialog('account', st);
    return;
  }
  box.innerHTML = `<div class="set-row wd-row-set"><span class="set-label">회원탈퇴<small>30일 뒤 삭제 · 그 사이 취소 가능</small></span><button id="main-withdraw" class="set-toggle as-btn wd-btn" type="button">탈퇴</button></div>`;
  $('main-withdraw').onclick = () => openDialog('account', st);
}

let ensuring = false;
export async function ensureActive(client, u, { onKeepScheduled } = {}) {
  if (!u || !client) return true;
  if (ensuring) return true;
  ensuring = true;
  try {
    let st;
    try {
      const { data, error } = await client.rpc('account_withdraw_status');
      if (error) {
        if (missingFn(error)) return true;
        console.warn('[withdraw] status', error);
        return true;
      }
      st = data;
    } catch (e) {
      if (missingFn(e)) return true;
      console.warn('[withdraw] status', e);
      return true;
    }
    if (!st?.scheduled) return true;
    return await new Promise(res => {
      const ov = openOv(`<h2 class="wd-title">탈퇴 예정 계정이에요</h2>
        <p class="wd-p">${kstDate(st.purge_at) || '예정일'}에 계정이 삭제돼요.${st.days_left != null ? ` (${st.days_left}일 남음)` : ''}</p>
        <p class="wd-p">취소할까요? 취소하면 계정을 그대로 쓸 수 있어요.</p>
        <div class="wd-row"><button type="button" class="main-btn wd-yes" data-wd="yes">탈퇴 취소</button><button type="button" class="wd-no" data-wd="no">로그아웃</button></div>`, { lock: true });
      ov.addEventListener('click', async e => {
        const act = e.target.closest('[data-wd]')?.dataset.wd;
        if (act === 'yes') {
          const btn = e.target.closest('[data-wd="yes"]');
          btn.disabled = true;
          try {
            const { error } = await client.rpc('account_withdraw_cancel');
            if (error) throw error;
            closeOv();
            toast('탈퇴 신청을 취소했어요. 계정을 그대로 쓸 수 있어요.');
            await paintSettings();
            res(true);
          } catch {
            btn.disabled = false;
            toast('탈퇴 취소를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.');
          }
        } else if (act === 'no') {
          closeOv();
          try { await onKeepScheduled?.(); } catch {}
          res(false);
        }
      });
    });
  } finally { ensuring = false; }
}

export const _test = { kstDate, localKeys, wipeLocal, CONFIRM_WORD, accountIntro, accountStep2, guestIntro, guestStep2 };

function init() {
  paintSettings();
  window.addEventListener('vr:user', () => { paintSettings(); });
}
if (typeof window !== 'undefined') {
  window.VRWithdraw = { openDialog, paintSettings, ensureActive, CONFIRM_WORD };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
}
