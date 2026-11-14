import { config } from './config.js';
import { readReturn, confirm, verifyError } from './age-verify.js';

const title = document.getElementById('age-title');
const msg = document.getElementById('age-msg');
const home = document.getElementById('age-home');
const raw = window.__VR_AGE_RETURN; delete window.__VR_AGE_RETURN;
function show(ok, text) {
  title.textContent = ok ? '본인인증 완료' : '본인인증 확인';
  msg.textContent = text;
  home.hidden = false;
}
let evidence = readReturn(raw || location.href);
if (!evidence) {
  try { evidence = readReturn('https://dummy.invalid/?' + (sessionStorage.getItem('vrTcg.age.vid.v1') ? 'identityVerificationId=' + sessionStorage.getItem('vrTcg.age.vid.v1') : '')); } catch {}
}
if (!config.enabled || !config.isStaging) show(false, '테스트 서버에서만 본인인증을 확인할 수 있어요.');
else if (!evidence || evidence.failed) show(false, verifyError(evidence?.failed ? 'verification not completed' : 'verification not completed'));
else {
  try {
    const { createClient } = await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm');
    const sb = createClient(config.supabaseUrl, config.anonKey, { auth: { persistSession: true, detectSessionInUrl: false, flowType: 'pkce' } });
    await sb.auth.initialize();
    const { data, error } = await sb.auth.getUser();
    if (error || !data.user) throw Error('login required');
    await confirm(sb, evidence.identityVerificationId);
    try { sessionStorage.removeItem('vrTcg.age.vid.v1'); } catch {}
    location.replace('/');
  } catch (e) {
    show(false, verifyError(e.message));
  }
}
