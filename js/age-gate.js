// ===== 본인인증(만 19세) 게이트 — 서버 플래그 age_verification_required, 기본 OFF =====
// 플래그가 꺼져 있거나 SQL/네트워크가 없으면 게임을 막지 않음. 켜져 있고 미인증이면 플레이를 막고 안내만 보여 줌.
// 실제 본인인증 연동(업체 계약 후)은 아직 없음. 클라이언트 우회를 막으려면 서버 RPC에도 같은 검사를 더 붙여야 함.
// 지금은 결제 주문 INSERT 트리거만 서버에서 막음 (supabase/age_19plus_staging.sql).
async function rpc(sb, fn, args) {
  if (!sb) return { ok: false };
  try { const { data, error } = await sb.rpc(fn, args); return error ? { ok: false, error } : { ok: true, data }; } catch (error) { return { ok: false, error }; }
}

export async function ensureAgeGate(sb, user, { show = showBlocked } = {}) {
  if (!user?.id) return true;
  const r = await rpc(sb, 'age_gate_status');
  if (!r.ok) return true;                 // SQL 미설치·네트워크 오류 → 기존 흐름 유지
  if (!r.data?.required || r.data?.verified) return true;
  await show();
  return false;
}

function css() {
  if (typeof document === 'undefined' || document.getElementById('age-gate-css')) return;
  const c = document.createElement('style'); c.id = 'age-gate-css'; c.textContent = `
  #age-gate-ov{position:fixed;inset:0;z-index:9610;background:rgba(0,0,0,.86);display:flex;align-items:center;justify-content:center;padding:16px}
  #age-gate-box{width:100%;max-width:380px;background:linear-gradient(#1e1530,#0e0a18);border:1px solid rgba(251,191,36,.45);border-radius:16px;color:#fde68a;padding:18px 16px 14px;box-shadow:0 10px 40px rgba(0,0,0,.6)}
  #age-gate-box h3{margin:0 0 8px;font-size:18px}#age-gate-box p{margin:0 0 8px;font-size:13px;line-height:1.55;opacity:.9}
  #age-gate-box .ag-note{font-size:11px;opacity:.7}`;
  document.head.appendChild(c);
}

export function showBlocked() {
  if (typeof document === 'undefined') return Promise.resolve();
  document.getElementById('age-gate-ov')?.remove(); css();
  const ov = document.createElement('div'); ov.id = 'age-gate-ov';
  ov.innerHTML = `<div id="age-gate-box" role="dialog" aria-modal="true" aria-labelledby="age-gate-title" data-clarity-mask="true">
    <h3 id="age-gate-title">본인인증이 필요합니다</h3>
    <p>이 게임은 만 19세 미만 이용 불가입니다. 본인인증으로 연령을 확인한 뒤에 이용할 수 있어요.</p>
    <p class="ag-note">인증 연동은 준비 중입니다. 지금은 게임을 진행하거나 결제할 수 없어요.</p>
  </div>`;
  document.body.appendChild(ov);
  return Promise.resolve();
}

if (typeof window !== 'undefined') window.VRAgeGate = { ensureAgeGate, showBlocked };
