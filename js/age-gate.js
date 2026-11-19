// ===== 본인인증(만 19세) 게이트 — 서버 플래그 age_verification_required, 기본 OFF =====
// 플래그가 꺼져 있거나 SQL/네트워크가 없으면 게임을 막지 않음.
// 켜져 있고 미인증이면 막음. 포트원 공개 키가 있으면 인증 버튼을 보여주고, 없으면 준비 중 안내만 함.
import { publicConfig } from './age-verify-config.js';
import { config } from './config.js';
import { requestVerification, confirm, verifyError } from './age-verify.js';

async function rpc(sb, fn, args) {
  if (!sb) return { ok: false };
  try { const { data, error } = await sb.rpc(fn, args); return error ? { ok: false, error } : { ok: true, data }; } catch (error) { return { ok: false, error }; }
}

export async function ensureAgeGate(sb, user, { show = showBlocked } = {}) {
  if (!user?.id) return true;
  const r = await rpc(sb, 'age_gate_status');
  if (!r.ok) return true;
  if (!r.data?.required || r.data?.verified) return true;
  return !!(await show({ sb, user }));
}

function css() {
  if (typeof document === 'undefined' || document.getElementById('age-gate-css')) return;
  const c = document.createElement('style'); c.id = 'age-gate-css'; c.textContent = `
  #age-gate-ov{position:fixed;inset:0;z-index:9610;background:rgba(0,0,0,.86);display:flex;align-items:center;justify-content:center;padding:16px}
  #age-gate-box{width:100%;max-width:380px;background:linear-gradient(#1e1530,#0e0a18);border:1px solid rgba(251,191,36,.45);border-radius:16px;color:#fde68a;padding:18px 16px 14px;box-shadow:0 10px 40px rgba(0,0,0,.6)}
  #age-gate-box h3{margin:0 0 8px;font-size:18px}#age-gate-box p{margin:0 0 8px;font-size:13px;line-height:1.55;opacity:.9}
  #age-gate-box .ag-note{font-size:11px;opacity:.7;margin-bottom:12px}
  #age-gate-box .ag-err{color:#fecaca;font-size:12px;min-height:1.4em}
  #age-gate-box button{width:100%;padding:11px;border-radius:10px;border:1px solid rgba(251,191,36,.35);background:#f59e0b;color:#1a1200;font-weight:800;font-size:14px;cursor:pointer}
  #age-gate-box button:disabled{opacity:.45;cursor:not-allowed}`;
  document.head.appendChild(c);
}

export function showBlocked({ sb } = {}) {
  if (typeof document === 'undefined') return Promise.resolve(false);
  document.getElementById('age-gate-ov')?.remove(); css();
  const keys = publicConfig(config);
  const ov = document.createElement('div'); ov.id = 'age-gate-ov';
  ov.innerHTML = `<div id="age-gate-box" role="dialog" aria-modal="true" aria-labelledby="age-gate-title" data-clarity-mask="true">
    <h3 id="age-gate-title">본인인증이 필요합니다</h3>
    <p>이 게임은 만 19세 미만 이용 불가입니다. 본인인증으로 연령을 확인한 뒤에 이용할 수 있어요.</p>
    <p class="ag-note">${keys.ready ? '휴대폰 본인인증 창이 열리면 안내에 따라 완료해 주세요.' : '인증 연동은 준비 중입니다. 지금은 게임을 진행하거나 결제할 수 없어요.'}</p>
    ${keys.ready ? '<p class="ag-err" id="age-gate-err"></p><button type="button" class="ag-go">본인인증하기</button>' : ''}
  </div>`;
  document.body.appendChild(ov);
  if (!keys.ready || !sb) return Promise.resolve(false);
  return new Promise(resolve => {
    const btn = ov.querySelector('.ag-go'), err = ov.querySelector('#age-gate-err');
    btn.onclick = async () => {
      if (btn.disabled) return;
      btn.disabled = true; err.textContent = '';
      try {
        const id = await requestVerification(keys);
        await confirm(sb, id);
        ov.remove();
        resolve(true);
      } catch (e) {
        err.textContent = verifyError(e.message);
        btn.disabled = false;
      }
    };
  });
}

if (typeof window !== 'undefined') window.VRAgeGate = { ensureAgeGate, showBlocked };
